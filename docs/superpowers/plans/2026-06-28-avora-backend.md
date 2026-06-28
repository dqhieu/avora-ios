# Avora Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Supabase backend for Avora — schema + RLS, server-authoritative credit system, async generation pipeline (pgmq + pg_cron worker + reaper) calling `gpt-image-2`, and the RevenueCat credit-granting webhook.

**Architecture:** Postgres holds all data and the durable queue (pgmq); pg_cron pumps a worker Edge Function that drains the queue at OpenAI-tier-capped concurrency and a reaper that recovers orphaned jobs. Edge Functions (Deno/TypeScript) expose the JWT-verified API and the signed RevenueCat webhook. Credits are mutated only by row-locked Postgres RPCs.

**Tech Stack:** Supabase (Postgres 15, Auth, Storage, Edge Functions/Deno), `pgmq`, `pg_cron`, `pg_net`, pgTAP (tests via `supabase test db`), OpenAI Images API (`gpt-image-2`), RevenueCat webhooks.

## Global Constraints

- Backend lives in `supabase/` **inside the `avora-ios` repo**. Keep `.gitignore` and any CI separate from the Swift app.
- Credits are **server-authoritative only** — no client path ever mutates a balance.
- **Cost per generation = 25 credits.** Starter `extra_credits = 50`. Weekly grant = 1000. Extra pack = 500. All grants are multiples of 25.
- Charge the full 25 from a **single bucket**, weekly-first; never split across buckets.
- `prompt_template` is **never** exposed to clients (column-limited `styles_public` view + RLS deny on base table).
- Image model: `gpt-image-2`, `size="auto"`, `quality="medium"`, server-side OpenAI key only.
- Moderation block (`moderation_blocked`): mark `failed`, **always refund**, never auto-retry.
- Reaper timeout = 5 minutes. Worker concurrency capped to the active OpenAI tier IPM.
- All webhook + refund + reset operations are idempotent.
- Migrations named by domain slug only (no phase/finding references), e.g. `000003_credit_rpcs.sql`.

---

## File Structure

```
avora-ios/supabase/
├── config.toml                              # local stack config
├── .env.local                               # OPENAI_API_KEY, REVENUECAT_WEBHOOK_TOKEN (gitignored)
├── migrations/
│   ├── 000001_extensions.sql                # pgmq, pg_cron, pg_net, pgtap
│   ├── 000002_core_tables.sql               # profiles, styles, generations, purchases, daily_spend
│   ├── 000003_rls_policies.sql              # RLS + styles_public view + storage policies
│   ├── 000004_new_user_trigger.sql          # handle_new_user → profiles row
│   ├── 000005_credit_rpcs.sql               # deduct_credit, refund_credit, lazy_weekly_reset
│   ├── 000006_queue.sql                     # pgmq queue create
│   ├── 000007_cron_jobs.sql                 # worker pump + reaper schedules
│   └── 000008_seed_styles.sql               # initial styles + prompt_templates
├── functions/
│   ├── _shared/
│   │   ├── cors.ts                          # CORS headers helper
│   │   ├── supabase.ts                      # service-role + user-scoped client factories
│   │   └── openai.ts                        # images.edit wrapper, usage extraction
│   ├── submit-generation/index.ts
│   ├── get-generation/index.ts
│   ├── list-generations/index.ts
│   ├── process-queue/index.ts               # worker
│   └── revenuecat-webhook/index.ts
└── tests/
    ├── 010_schema_test.sql                  # pgTAP: tables/columns/constraints
    ├── 020_rls_test.sql                     # pgTAP: cross-user isolation
    ├── 030_credit_rpcs_test.sql             # pgTAP: deduct/refund/reset + concurrency
    └── 040_reaper_test.sql                  # pgTAP: reaper refunds orphans
```

**Local workflow for every task:** `supabase start` (once), apply migrations with `supabase db reset`, run DB tests with `supabase test db`, serve functions with `supabase functions serve`.

---

## Task 1: Local stack + extensions

**Files:**
- Create: `supabase/config.toml` (via `supabase init`)
- Create: `supabase/migrations/000001_extensions.sql`

**Interfaces:**
- Produces: a running local Supabase stack with `pgmq`, `pg_cron`, `pg_net`, `pgtap` extensions available.

- [ ] **Step 1: Initialize Supabase project**

Run from repo root:
```bash
cd /Users/hieudinh/Projects/avora-ios
supabase init        # creates supabase/config.toml, supabase/.gitignore
supabase start       # boots local Postgres/Auth/Storage (Docker)
```
Expected: `supabase start` prints API URL, anon key, service_role key.

- [ ] **Step 2: Write the extensions migration**

`supabase/migrations/000001_extensions.sql`:
```sql
create extension if not exists pgtap with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;
create extension if not exists pgmq;
```

- [ ] **Step 3: Apply and verify**

Run:
```bash
supabase db reset
```
Expected: reset completes with no error; the migration applies.

- [ ] **Step 4: Verify extensions are present**

Run:
```bash
supabase db reset && psql "$(supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '\"')" \
  -c "select extname from pg_extension where extname in ('pgmq','pg_cron','pg_net','pgtap') order by 1;"
```
Expected: four rows — `pg_cron, pg_net, pgmq, pgtap`.

- [ ] **Step 5: Commit**

```bash
git add supabase/config.toml supabase/.gitignore supabase/migrations/000001_extensions.sql
git commit -m "chore: init supabase local stack and core extensions"
```

---

## Task 2: Core tables

**Files:**
- Create: `supabase/migrations/000002_core_tables.sql`
- Test: `supabase/tests/010_schema_test.sql`

**Interfaces:**
- Produces tables: `profiles`, `styles`, `generations`, `purchases`, `daily_spend` with the columns/constraints below. Later tasks rely on: `profiles.weekly_credits/extra_credits`, `generations.status/charged_bucket/charged_amount`, `purchases.transaction_id` PK.

- [ ] **Step 1: Write the failing schema test**

`supabase/tests/010_schema_test.sql`:
```sql
begin;
select plan(9);

select has_table('public', 'profiles', 'profiles exists');
select has_table('public', 'styles', 'styles exists');
select has_table('public', 'generations', 'generations exists');
select has_table('public', 'purchases', 'purchases exists');
select has_table('public', 'daily_spend', 'daily_spend exists');

select col_default_is('public', 'profiles', 'extra_credits', '50', 'starter extra credits = 50');
select col_has_check('public', 'generations', 'status', 'status is constrained');
select has_column('public', 'generations', 'charged_amount', 'charged_amount column exists');
select col_is_pk('public', 'purchases', 'transaction_id', 'purchases pk is transaction_id');

select * from finish();
rollback;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `supabase test db`
Expected: FAIL — tables do not exist yet.

- [ ] **Step 3: Write the tables migration**

`supabase/migrations/000002_core_tables.sql`:
```sql
create table public.profiles (
  id                      uuid primary key references auth.users(id) on delete cascade,
  created_at              timestamptz not null default now(),
  weekly_credits          int not null default 0,
  extra_credits           int not null default 50,
  subscription_period_end timestamptz,
  subscription_active     boolean not null default false
);

create table public.styles (
  id                text primary key,
  name              text not null,
  prompt_template   text not null,
  sample_image_path text,
  default_size      text not null default 'auto',
  default_quality   text not null default 'medium',
  active            boolean not null default true
);

create table public.generations (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  style_id       text not null references public.styles(id),
  status         text not null default 'pending'
                   check (status in ('pending','completed','failed')),
  charged_bucket text not null check (charged_bucket in ('weekly','extra')),
  charged_amount int not null,
  input_path     text not null,
  output_path    text,
  size           text,
  quality        text not null,
  input_tokens   int,
  output_tokens  int,
  error_code     text,
  created_at     timestamptz not null default now(),
  completed_at   timestamptz
);

create index generations_user_created_idx on public.generations (user_id, created_at desc);
create index generations_pending_idx on public.generations (status) where status = 'pending';

create table public.purchases (
  transaction_id text primary key,
  user_id        uuid not null references auth.users(id),
  kind           text not null check (kind in ('renewal','extra_pack','initial')),
  processed_at   timestamptz not null default now()
);

create table public.daily_spend (
  day          date primary key,
  total_tokens bigint not null default 0,
  est_cost_usd numeric not null default 0
);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: PASS — all 9 assertions ok.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/000002_core_tables.sql supabase/tests/010_schema_test.sql
git commit -m "feat: add core tables (profiles, styles, generations, purchases, daily_spend)"
```

---

## Task 3: RLS, styles_public view, storage policies

**Files:**
- Create: `supabase/migrations/000003_rls_policies.sql`
- Test: `supabase/tests/020_rls_test.sql`

**Interfaces:**
- Produces view `public.styles_public (id, name, sample_image_path, active)` — the only style data clients may read.
- Produces RLS such that an authenticated user reads only their own `profiles`/`generations` rows; `styles` base table, `purchases`, `daily_spend` are unreadable by clients.

- [ ] **Step 1: Write the failing RLS test**

`supabase/tests/020_rls_test.sql`:
```sql
begin;
select plan(4);

-- seed two users + their data as superuser
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@test.dev'),
  ('22222222-2222-2222-2222-222222222222', 'b@test.dev');
insert into public.profiles (id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222');
insert into public.styles (id, name, prompt_template) values ('s1','Style 1','SECRET');
insert into public.generations (id, user_id, style_id, charged_bucket, charged_amount, input_path, quality)
  values ('aaaaaaaa-0000-0000-0000-000000000001',
          '11111111-1111-1111-1111-111111111111','s1','extra',25,'in/a.png','medium');

-- act as user A
set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

select is(
  (select count(*)::int from public.generations),
  1, 'user A sees only their own generation');

select is(
  (select count(*)::int from public.generations
     where user_id = '22222222-2222-2222-2222-222222222222'),
  0, 'user A cannot see user B generations');

select is(
  (select count(*)::int from public.styles_public where id = 's1'),
  1, 'user A can read styles_public');

select throws_ok(
  $$ select prompt_template from public.styles where id = 's1' $$,
  '42501', null, 'user A cannot read prompt_template from base styles');

select * from finish();
rollback;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `supabase test db`
Expected: FAIL — RLS not enabled, view missing.

- [ ] **Step 3: Write the RLS migration**

`supabase/migrations/000003_rls_policies.sql`:
```sql
alter table public.profiles    enable row level security;
alter table public.styles      enable row level security;
alter table public.generations enable row level security;
alter table public.purchases   enable row level security;
alter table public.daily_spend enable row level security;

-- profiles: owner read only; no client writes
create policy profiles_select_own on public.profiles
  for select to authenticated using (id = auth.uid());

-- generations: owner read only; writes go through service role (bypasses RLS)
create policy generations_select_own on public.generations
  for select to authenticated using (user_id = auth.uid());

-- styles base table: no client access at all (no policies + RLS on = deny)
-- expose a column-limited view instead:
create view public.styles_public
  with (security_invoker = true) as
  select id, name, sample_image_path, active from public.styles where active = true;
grant select on public.styles_public to authenticated, anon;

-- styles_public must bypass styles RLS for the selected columns:
-- security_invoker view + a read policy scoped to non-secret usage:
create policy styles_public_read on public.styles
  for select to authenticated, anon using (true);
-- revoke direct column access to prompt_template via column privileges:
revoke all on public.styles from authenticated, anon;
grant select (id, name, sample_image_path, active, default_size, default_quality)
  on public.styles to authenticated, anon;
```

> Note on prompt protection: RLS row policy allows the row, but **column-level GRANTs** withhold `prompt_template`. A client `select prompt_template ...` raises `42501` (insufficient privilege). The worker uses the service-role key, which bypasses both.

- [ ] **Step 4: Write storage bucket + policies (same migration, appended)**

Append to `000003_rls_policies.sql`:
```sql
insert into storage.buckets (id, name, public) values
  ('inputs','inputs', false),
  ('outputs','outputs', false)
  on conflict (id) do nothing;

-- users may read/write only objects under their own uid prefix: "<uid>/..."
create policy inputs_own on storage.objects
  for all to authenticated
  using (bucket_id = 'inputs'  and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'inputs' and (storage.foldername(name))[1] = auth.uid()::text);

create policy outputs_read_own on storage.objects
  for select to authenticated
  using (bucket_id = 'outputs' and (storage.foldername(name))[1] = auth.uid()::text);
-- outputs are written by the worker (service role), so no client insert policy.
```

- [ ] **Step 5: Run test to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: PASS — all 4 RLS assertions ok.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/000003_rls_policies.sql supabase/tests/020_rls_test.sql
git commit -m "feat: add RLS policies, styles_public view, storage bucket policies"
```

---

## Task 4: New-user trigger

**Files:**
- Create: `supabase/migrations/000004_new_user_trigger.sql`

**Interfaces:**
- Produces: inserting an `auth.users` row auto-creates a `public.profiles` row with `extra_credits = 50` (exactly once).

- [ ] **Step 1: Append assertion to schema test**

Add to `supabase/tests/010_schema_test.sql` before `finish()` and bump `plan(9)` → `plan(10)`:
```sql
-- new-user trigger grants 50 starter credits exactly once
insert into auth.users (id, email)
  values ('33333333-3333-3333-3333-333333333333','c@test.dev');
select is(
  (select extra_credits from public.profiles
     where id = '33333333-3333-3333-3333-333333333333'),
  50, 'trigger creates profile with 50 starter credits');
```

- [ ] **Step 2: Run test to verify it fails**

Run: `supabase test db`
Expected: FAIL — no profile row created (trigger missing).

- [ ] **Step 3: Write the trigger migration**

`supabase/migrations/000004_new_user_trigger.sql`:
```sql
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;   -- idempotent: retried onboarding cannot double-grant
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
```

- [ ] **Step 4: Run test to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: PASS — starter credits = 50.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/000004_new_user_trigger.sql supabase/tests/010_schema_test.sql
git commit -m "feat: auto-create profile with starter credits on signup"
```

---

## Task 5: Credit RPCs (deduct / refund / lazy reset)

**Files:**
- Create: `supabase/migrations/000005_credit_rpcs.sql`
- Test: `supabase/tests/030_credit_rpcs_test.sql`

**Interfaces:**
- Produces:
  - `deduct_credit(p_uid uuid) returns text` → `'weekly'` or `'extra'`; raises `insufficient_credits` (sqlstate `P0001`) when neither bucket has ≥25.
  - `refund_credit(p_generation_id uuid) returns void` → idempotent; returns `charged_amount` to `charged_bucket`, flipping `pending → failed`.
  - `lazy_weekly_reset(p_uid uuid) returns void` → resets weekly to 1000 if expired + active.

- [ ] **Step 1: Write the failing RPC test**

`supabase/tests/030_credit_rpcs_test.sql`:
```sql
begin;
select plan(7);

insert into auth.users (id, email) values ('44444444-4444-4444-4444-444444444444','d@test.dev');
-- profile auto-created with extra=50, weekly=0
update public.profiles set weekly_credits = 25
  where id = '44444444-4444-4444-4444-444444444444';
insert into public.styles (id, name, prompt_template) values ('s1','S1','x');

-- weekly is spent first
select is(deduct_credit('44444444-4444-4444-4444-444444444444'), 'weekly', 'charges weekly first');
select is((select weekly_credits from public.profiles where id='44444444-4444-4444-4444-444444444444'),
          0, 'weekly now 0');

-- next charge falls to extra
select is(deduct_credit('44444444-4444-4444-4444-444444444444'), 'extra', 'falls back to extra');
select is((select extra_credits from public.profiles where id='44444444-4444-4444-4444-444444444444'),
          25, 'extra now 25 (was 50)');

-- refund is idempotent and returns to the charged bucket
insert into public.generations (id, user_id, style_id, status, charged_bucket, charged_amount, input_path, quality)
  values ('bbbbbbbb-0000-0000-0000-000000000001',
          '44444444-4444-4444-4444-444444444444','s1','pending','extra',25,'in/x.png','medium');
select refund_credit('bbbbbbbb-0000-0000-0000-000000000001');
select is((select extra_credits from public.profiles where id='44444444-4444-4444-4444-444444444444'),
          50, 'refund returns 25 to extra');
select refund_credit('bbbbbbbb-0000-0000-0000-000000000001'); -- second call: no-op
select is((select extra_credits from public.profiles where id='44444444-4444-4444-4444-444444444444'),
          50, 'refund is idempotent (still 50)');

-- insufficient credits raises
update public.profiles set weekly_credits = 0, extra_credits = 0
  where id = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$ select deduct_credit('44444444-4444-4444-4444-444444444444') $$,
  'P0001', 'insufficient_credits', 'raises when no bucket has >= 25');

select * from finish();
rollback;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `supabase test db`
Expected: FAIL — functions do not exist.

- [ ] **Step 3: Write the RPC migration**

`supabase/migrations/000005_credit_rpcs.sql`:
```sql
-- cost per generation
create or replace function public.deduct_credit(p_uid uuid)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  v_cost int := 25;
  v_bucket text;
begin
  -- lock the row first so concurrent submits serialize on this profile
  perform 1 from public.profiles where id = p_uid for update;

  update public.profiles set weekly_credits = weekly_credits - v_cost
    where id = p_uid and weekly_credits >= v_cost
    returning 'weekly' into v_bucket;

  if v_bucket is null then
    update public.profiles set extra_credits = extra_credits - v_cost
      where id = p_uid and extra_credits >= v_cost
      returning 'extra' into v_bucket;
  end if;

  if v_bucket is null then
    raise exception 'insufficient_credits' using errcode = 'P0001';
  end if;

  return v_bucket;
end;
$$;

create or replace function public.refund_credit(p_generation_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_user uuid; v_bucket text; v_amount int;
begin
  -- only refund on the pending -> failed transition; guarantees once-only
  update public.generations
    set status = 'failed', completed_at = now()
    where id = p_generation_id and status = 'pending'
    returning user_id, charged_bucket, charged_amount
    into v_user, v_bucket, v_amount;

  if v_user is null then
    return;  -- already terminal: idempotent no-op
  end if;

  if v_bucket = 'weekly' then
    update public.profiles set weekly_credits = weekly_credits + v_amount where id = v_user;
  else
    update public.profiles set extra_credits = extra_credits + v_amount where id = v_user;
  end if;
end;
$$;

create or replace function public.lazy_weekly_reset(p_uid uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.profiles
    set weekly_credits = 1000
    where id = p_uid
      and subscription_active = true
      and subscription_period_end is not null
      and now() > subscription_period_end;
end;
$$;

revoke all on function public.deduct_credit(uuid)      from public, anon, authenticated;
revoke all on function public.refund_credit(uuid)      from public, anon, authenticated;
revoke all on function public.lazy_weekly_reset(uuid)  from public, anon, authenticated;
-- only service role (used by Edge Functions / cron) may call these.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: PASS — all 7 assertions ok.

- [ ] **Step 5: Add a concurrency assertion**

Append to `030_credit_rpcs_test.sql` (bump `plan(7)` → `plan(8)`): a single-statement check that two deductions on a 25-credit account net exactly one success. Because pgTAP runs in one session, assert the locking contract via `pg_catalog` rather than true parallelism:
```sql
-- exactly-one semantics: with weekly=25, two deducts -> one ok, one raises
update public.profiles set weekly_credits = 25, extra_credits = 0
  where id = '44444444-4444-4444-4444-444444444444';
select lives_ok($$ select deduct_credit('44444444-4444-4444-4444-444444444444') $$,
  'first deduct succeeds');
select throws_ok($$ select deduct_credit('44444444-4444-4444-4444-444444444444') $$,
  'P0001', 'insufficient_credits', 'second deduct on drained account raises');
```
Run: `supabase test db` → PASS. (True parallel load is verified in Task 11.)

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/000005_credit_rpcs.sql supabase/tests/030_credit_rpcs_test.sql
git commit -m "feat: add server-authoritative credit RPCs (deduct/refund/lazy-reset)"
```

---

## Task 6: Queue + shared function utilities

**Files:**
- Create: `supabase/migrations/000006_queue.sql`
- Create: `supabase/functions/_shared/cors.ts`
- Create: `supabase/functions/_shared/supabase.ts`
- Create: `supabase/functions/_shared/openai.ts`

**Interfaces:**
- Produces pgmq queue `generations`.
- Produces helpers:
  - `corsHeaders` (record), `handleOptions(req)`.
  - `serviceClient()` → service-role SupabaseClient; `userClient(req)` → JWT-scoped client + `getUser(req)` returning the authenticated user id or throwing 401.
  - `runEdit({ imageBytes, prompt, size, quality })` → `{ b64, size, inputTokens, outputTokens }`; throws `OpenAIError { retryable: boolean, code: string }`.

- [ ] **Step 1: Write the queue migration**

`supabase/migrations/000006_queue.sql`:
```sql
select pgmq.create('generations');
```

- [ ] **Step 2: Verify the queue exists**

Run:
```bash
supabase db reset && psql "$(supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '\"')" \
  -c "select queue_name from pgmq.list_queues();"
```
Expected: a row `generations`.

- [ ] **Step 3: Write CORS helper**

`supabase/functions/_shared/cors.ts`:
```ts
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, idempotency-key",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

export function handleOptions(req: Request): Response | null {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  return null;
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
```

- [ ] **Step 4: Write Supabase client factory**

`supabase/functions/_shared/supabase.ts`:
```ts
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

export function serviceClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
}

export function userClient(req: Request): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      auth: { persistSession: false },
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    },
  );
}

export async function requireUser(req: Request): Promise<string> {
  const { data, error } = await userClient(req).auth.getUser();
  if (error || !data.user) throw new Response("unauthorized", { status: 401 });
  return data.user.id;
}
```

- [ ] **Step 5: Write OpenAI wrapper**

`supabase/functions/_shared/openai.ts`:
```ts
export class OpenAIError extends Error {
  constructor(public code: string, public retryable: boolean) {
    super(code);
  }
}

export interface EditResult {
  b64: string;
  size: string;
  inputTokens: number;
  outputTokens: number;
}

export async function runEdit(opts: {
  imageBytes: Uint8Array;
  filename: string;
  prompt: string;
  size: string;
  quality: string;
}): Promise<EditResult> {
  const form = new FormData();
  form.append("model", "gpt-image-2");
  form.append("prompt", opts.prompt);
  form.append("size", opts.size);
  form.append("quality", opts.quality);
  form.append("image", new Blob([opts.imageBytes]), opts.filename);

  const res = await fetch("https://api.openai.com/v1/images/edits", {
    method: "POST",
    headers: { Authorization: `Bearer ${Deno.env.get("OPENAI_API_KEY")}` },
    body: form,
  });

  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    const code = body?.error?.code ?? `http_${res.status}`;
    if (code === "moderation_blocked") throw new OpenAIError("moderation_blocked", false);
    const retryable = res.status === 429 || res.status >= 500;
    throw new OpenAIError(code, retryable);
  }

  const data = await res.json();
  const item = data.data[0];
  return {
    b64: item.b64_json,
    size: item.size ?? opts.size,
    inputTokens: data.usage?.input_tokens ?? 0,
    outputTokens: data.usage?.output_tokens ?? 0,
  };
}
```

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/000006_queue.sql supabase/functions/_shared/
git commit -m "feat: create pgmq queue and shared edge-function utilities"
```

---

## Task 7: submit-generation Edge Function

**Files:**
- Create: `supabase/functions/submit-generation/index.ts`

**Interfaces:**
- Consumes: `requireUser`, `serviceClient`, `json`, `handleOptions`; RPCs `lazy_weekly_reset`, `deduct_credit`; pgmq `generations`.
- Produces: `POST` accepting `{ style_id, input_path }` → `202 { job_id }`; `402 { error: "insufficient_credits" }`; `400` on bad input; `401` unauthorized.

- [ ] **Step 1: Write the function**

`supabase/functions/submit-generation/index.ts`:
```ts
import { handleOptions, json } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pre = handleOptions(req); if (pre) return pre;
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let uid: string;
  try { uid = await requireUser(req); } catch { return json({ error: "unauthorized" }, 401); }

  const { style_id, input_path } = await req.json().catch(() => ({}));
  if (typeof style_id !== "string" || typeof input_path !== "string") {
    return json({ error: "bad_request" }, 400);
  }
  // input_path must belong to this user: "<uid>/<file>"
  if (!input_path.startsWith(`${uid}/`)) return json({ error: "forbidden_path" }, 403);

  const db = serviceClient();

  // style must exist and be active
  const { data: style } = await db.from("styles")
    .select("id, default_quality, active").eq("id", style_id).single();
  if (!style || !style.active) return json({ error: "unknown_style" }, 400);

  // server-side input validation (format/size) via Storage metadata
  const { data: meta, error: metaErr } = await db.storage.from("inputs")
    .info(input_path).catch(() => ({ data: null, error: true } as any));
  if (metaErr || !meta) return json({ error: "input_not_found" }, 400);
  const okType = ["image/png", "image/jpeg"].includes(meta.contentType ?? "");
  const okSize = (meta.size ?? Infinity) <= 10 * 1024 * 1024; // 10 MB cap
  if (!okType || !okSize) return json({ error: "invalid_input" }, 400);

  // webhook backstop, then atomic deduction
  await db.rpc("lazy_weekly_reset", { p_uid: uid });
  const { data: bucket, error: deductErr } = await db.rpc("deduct_credit", { p_uid: uid });
  if (deductErr) {
    if (deductErr.message.includes("insufficient_credits"))
      return json({ error: "insufficient_credits" }, 402);
    return json({ error: "deduct_failed" }, 500);
  }

  const { data: gen, error: insErr } = await db.from("generations").insert({
    user_id: uid, style_id, status: "pending",
    charged_bucket: bucket, charged_amount: 25,
    input_path, quality: style.default_quality,
  }).select("id").single();
  if (insErr || !gen) {
    // compensate: nothing enqueued, give credit back by faking a pending->failed row? 
    // Simpler: refund directly since no row persisted — re-credit the charged bucket.
    await db.rpc("refund_credit_direct", { p_uid: uid, p_bucket: bucket, p_amount: 25 })
      .catch(() => {});
    return json({ error: "insert_failed" }, 500);
  }

  await db.rpc("pgmq_send", { queue_name: "generations", msg: { job_id: gen.id } })
    .catch(async () => {
      // fall back to direct SQL if RPC wrapper absent
      await db.schema("pgmq").rpc("send", { queue_name: "generations", msg: { job_id: gen.id } });
    });

  return json({ job_id: gen.id }, 202);
});
```

- [ ] **Step 2: Add the compensating refund + pgmq send helpers (migration)**

The submit path references `refund_credit_direct` and a `pgmq_send` wrapper. Add `supabase/migrations/000005_credit_rpcs.sql` additions (new file `000006b_helpers.sql` to keep ordering):

`supabase/migrations/000006b_helpers.sql`:
```sql
create or replace function public.refund_credit_direct(p_uid uuid, p_bucket text, p_amount int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_bucket = 'weekly' then
    update public.profiles set weekly_credits = weekly_credits + p_amount where id = p_uid;
  else
    update public.profiles set extra_credits = extra_credits + p_amount where id = p_uid;
  end if;
end; $$;

create or replace function public.pgmq_send(queue_name text, msg jsonb)
returns bigint language sql security definer set search_path = pgmq, public as $$
  select pgmq.send(queue_name, msg);
$$;

revoke all on function public.refund_credit_direct(uuid,text,int) from public, anon, authenticated;
revoke all on function public.pgmq_send(text,jsonb)              from public, anon, authenticated;
```

- [ ] **Step 3: Serve and integration-test the happy + 402 paths**

Run (in one terminal): `supabase functions serve --env-file supabase/.env.local`
Then create a signed-in test: obtain a user JWT from the local Auth (`supabase` test helper or a seeded session). Hit:
```bash
curl -i -X POST http://localhost:54321/functions/v1/submit-generation \
  -H "Authorization: Bearer $USER_JWT" -H "Content-Type: application/json" \
  -d '{"style_id":"s1","input_path":"'$USER_ID'/test.png"}'
```
Expected: `202 {"job_id":"..."}` when credits/input valid; `402 {"error":"insufficient_credits"}` after draining the account.

- [ ] **Step 4: Verify a job landed in the queue**

Run:
```bash
psql "$DB_URL" -c "select msg_id, message from pgmq.read('generations', 30, 5);"
```
Expected: a message containing the `job_id`.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/submit-generation/ supabase/migrations/000006b_helpers.sql
git commit -m "feat: add submit-generation endpoint with atomic deduction and enqueue"
```

---

## Task 8: process-queue worker

**Files:**
- Create: `supabase/functions/process-queue/index.ts`

**Interfaces:**
- Consumes: `serviceClient`, `runEdit`, `OpenAIError`; RPC `refund_credit`; pgmq `generations`; tables `styles`, `generations`, `daily_spend`.
- Produces: a worker that drains up to `MAX_BATCH` jobs per invocation, capped to OpenAI tier IPM, respecting the daily spend cap.

- [ ] **Step 1: Write the worker**

`supabase/functions/process-queue/index.ts`:
```ts
import { json } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { runEdit, OpenAIError } from "../_shared/openai.ts";

const VISIBILITY = 120;          // seconds a claimed job is hidden
const MAX_BATCH = Number(Deno.env.get("WORKER_MAX_BATCH") ?? "5");   // <= tier IPM
const DAILY_TOKEN_CAP = Number(Deno.env.get("DAILY_TOKEN_CAP") ?? "50000000");

Deno.serve(async () => {
  const db = serviceClient();

  // spend cap check
  const today = new Date().toISOString().slice(0, 10);
  const { data: spend } = await db.from("daily_spend").select("total_tokens").eq("day", today).maybeSingle();
  if ((spend?.total_tokens ?? 0) >= DAILY_TOKEN_CAP) return json({ skipped: "spend_cap" });

  const { data: msgs } = await db.schema("pgmq")
    .rpc("read", { queue_name: "generations", vt: VISIBILITY, qty: MAX_BATCH });
  if (!msgs?.length) return json({ processed: 0 });

  let processed = 0;
  for (const m of msgs) {
    const jobId = m.message.job_id as string;
    const msgId = m.msg_id as number;
    try {
      const { data: gen } = await db.from("generations")
        .select("id,user_id,style_id,input_path,quality,status").eq("id", jobId).single();
      if (!gen || gen.status !== "pending") { await archive(db, msgId); continue; }

      const { data: style } = await db.from("styles")
        .select("prompt_template,default_size").eq("id", gen.style_id).single();

      const { data: blob } = await db.storage.from("inputs").download(gen.input_path);
      const bytes = new Uint8Array(await blob!.arrayBuffer());

      const result = await runEdit({
        imageBytes: bytes, filename: "input.png",
        prompt: style!.prompt_template, size: style!.default_size, quality: gen.quality,
      });

      const outPath = `${gen.user_id}/${jobId}.png`;
      await db.storage.from("outputs").upload(outPath, decodeB64(result.b64), {
        contentType: "image/png", upsert: true,
      });

      await db.from("generations").update({
        status: "completed", output_path: outPath, size: result.size,
        input_tokens: result.inputTokens, output_tokens: result.outputTokens,
        completed_at: new Date().toISOString(),
      }).eq("id", jobId).eq("status", "pending");

      await bumpSpend(db, today, result.inputTokens + result.outputTokens);
      await archive(db, msgId);
      processed++;
    } catch (e) {
      if (e instanceof OpenAIError && e.retryable) {
        // leave message un-archived: visibility timeout returns it for retry.
        // mark failed + refund only after pgmq read_ct exceeds threshold:
        if ((m.read_ct ?? 1) >= 3) {
          await db.from("generations").update({ error_code: e.code }).eq("id", jobId);
          await db.rpc("refund_credit", { p_generation_id: jobId });
          await archive(db, msgId);
        }
        continue;
      }
      // non-retryable (incl. moderation_blocked): fail + always refund
      const code = e instanceof OpenAIError ? e.code : "worker_error";
      await db.from("generations").update({ error_code: code }).eq("id", jobId);
      await db.rpc("refund_credit", { p_generation_id: jobId });
      await archive(db, msgId);
    }
  }
  return json({ processed });
});

function decodeB64(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
async function archive(db: ReturnType<typeof serviceClient>, msgId: number) {
  await db.schema("pgmq").rpc("archive", { queue_name: "generations", msg_id: msgId });
}
async function bumpSpend(db: ReturnType<typeof serviceClient>, day: string, tokens: number) {
  await db.from("daily_spend").upsert(
    { day, total_tokens: tokens, est_cost_usd: 0 },
    { onConflict: "day", ignoreDuplicates: false },
  );
  await db.rpc("bump_daily_tokens", { p_day: day, p_tokens: tokens }).catch(() => {});
}
```

- [ ] **Step 2: Add the spend-increment RPC**

`supabase/migrations/000006c_spend.sql`:
```sql
create or replace function public.bump_daily_tokens(p_day date, p_tokens bigint)
returns void language sql security definer set search_path = public as $$
  insert into public.daily_spend (day, total_tokens, est_cost_usd)
  values (p_day, p_tokens, 0)
  on conflict (day) do update set total_tokens = public.daily_spend.total_tokens + p_tokens;
$$;
revoke all on function public.bump_daily_tokens(date,bigint) from public, anon, authenticated;
```
Remove the redundant `upsert` in `bumpSpend` (keep only the RPC call) so tokens accumulate rather than overwrite. Edit `process-queue/index.ts` `bumpSpend` to:
```ts
async function bumpSpend(db: ReturnType<typeof serviceClient>, day: string, tokens: number) {
  await db.rpc("bump_daily_tokens", { p_day: day, p_tokens: tokens });
}
```

- [ ] **Step 3: Integration test end-to-end (real OpenAI key)**

With a valid `OPENAI_API_KEY` in `.env.local`, enqueue a job (Task 7) then invoke:
```bash
curl -i -X POST http://localhost:54321/functions/v1/process-queue \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY"
psql "$DB_URL" -c "select status, output_path, input_tokens, output_tokens from generations order by created_at desc limit 1;"
```
Expected: row `status=completed`, non-null `output_path`, token counts populated; an object exists in the `outputs` bucket under `<uid>/<job_id>.png`.

- [ ] **Step 4: Verify moderation/non-retryable refund path**

Temporarily point a style's `prompt_template` at content that trips moderation (or stub `runEdit` to throw `new OpenAIError("moderation_blocked", false)`), enqueue, process, then:
```bash
psql "$DB_URL" -c "select status, error_code from generations order by created_at desc limit 1;"
psql "$DB_URL" -c "select weekly_credits, extra_credits from profiles where id='$USER_ID';"
```
Expected: `status=failed`, `error_code=moderation_blocked`, and the 25 credits restored to the original bucket.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/process-queue/ supabase/migrations/000006c_spend.sql
git commit -m "feat: add generation worker with retry, refund, and spend cap"
```

---

## Task 9: get-generation + list-generations

**Files:**
- Create: `supabase/functions/get-generation/index.ts`
- Create: `supabase/functions/list-generations/index.ts`

**Interfaces:**
- Consumes: `requireUser`, `userClient`, `json`, `handleOptions`.
- Produces:
  - `GET get-generation?id=<uuid>` → `{ status, output_path?, error_code? }` (RLS-scoped, 404 if not the user's).
  - `GET list-generations?cursor=<iso>&limit=<n>` → `{ items: [...], next_cursor? }` ordered by `created_at desc`.

- [ ] **Step 1: Write get-generation**

`supabase/functions/get-generation/index.ts`:
```ts
import { handleOptions, json } from "../_shared/cors.ts";
import { requireUser, userClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pre = handleOptions(req); if (pre) return pre;
  try { await requireUser(req); } catch { return json({ error: "unauthorized" }, 401); }

  const id = new URL(req.url).searchParams.get("id");
  if (!id) return json({ error: "bad_request" }, 400);

  const { data, error } = await userClient(req).from("generations")
    .select("status, output_path, error_code").eq("id", id).maybeSingle();
  if (error) return json({ error: "query_failed" }, 500);
  if (!data) return json({ error: "not_found" }, 404);  // RLS hides others' rows
  return json(data);
});
```

- [ ] **Step 2: Write list-generations**

`supabase/functions/list-generations/index.ts`:
```ts
import { handleOptions, json } from "../_shared/cors.ts";
import { requireUser, userClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pre = handleOptions(req); if (pre) return pre;
  try { await requireUser(req); } catch { return json({ error: "unauthorized" }, 401); }

  const url = new URL(req.url);
  const limit = Math.min(Number(url.searchParams.get("limit") ?? "20"), 50);
  const cursor = url.searchParams.get("cursor");

  let q = userClient(req).from("generations")
    .select("id, style_id, status, output_path, created_at")
    .order("created_at", { ascending: false })
    .limit(limit + 1);
  if (cursor) q = q.lt("created_at", cursor);

  const { data, error } = await q;
  if (error) return json({ error: "query_failed" }, 500);

  const items = (data ?? []).slice(0, limit);
  const next_cursor = (data ?? []).length > limit ? items[items.length - 1].created_at : undefined;
  return json({ items, next_cursor });
});
```

- [ ] **Step 3: Integration test both**

With a completed generation from Task 8:
```bash
curl -s "http://localhost:54321/functions/v1/get-generation?id=$JOB_ID" \
  -H "Authorization: Bearer $USER_JWT"
curl -s "http://localhost:54321/functions/v1/list-generations?limit=10" \
  -H "Authorization: Bearer $USER_JWT"
```
Expected: get returns `{"status":"completed","output_path":"..."}`; list returns `{ "items":[...], ... }`. Calling get with another user's JWT returns `404`.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/get-generation/ supabase/functions/list-generations/
git commit -m "feat: add poll and paginated collection endpoints"
```

---

## Task 10: Cron jobs (worker pump + reaper)

**Files:**
- Create: `supabase/migrations/000007_cron_jobs.sql`
- Test: `supabase/tests/040_reaper_test.sql`

**Interfaces:**
- Produces:
  - SQL function `public.reap_orphans()` → refunds + fails `pending` rows older than 5 minutes.
  - pg_cron schedules: invoke `process-queue` (worker pump) and run `reap_orphans` every minute.

- [ ] **Step 1: Write the failing reaper test**

`supabase/tests/040_reaper_test.sql`:
```sql
begin;
select plan(2);

insert into auth.users (id, email) values ('55555555-5555-5555-5555-555555555555','e@test.dev');
update public.profiles set extra_credits = 25 where id='55555555-5555-5555-5555-555555555555';
insert into public.styles (id, name, prompt_template) values ('s1','S1','x');
insert into public.generations
  (id, user_id, style_id, status, charged_bucket, charged_amount, input_path, quality, created_at)
  values ('cccccccc-0000-0000-0000-000000000001',
          '55555555-5555-5555-5555-555555555555','s1','pending','extra',25,'in/x.png','medium',
          now() - interval '6 minutes');

select public.reap_orphans();

select is((select status from public.generations where id='cccccccc-0000-0000-0000-000000000001'),
          'failed', 'reaper fails orphaned pending row');
select is((select extra_credits from public.profiles where id='55555555-5555-5555-5555-555555555555'),
          50, 'reaper refunds the charged bucket');

select * from finish();
rollback;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `supabase test db`
Expected: FAIL — `reap_orphans` undefined.

- [ ] **Step 3: Write the cron migration**

`supabase/migrations/000007_cron_jobs.sql`:
```sql
create or replace function public.reap_orphans()
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in
    select id from public.generations
    where status = 'pending' and created_at < now() - interval '5 minutes'
    for update skip locked
  loop
    update public.generations set error_code = coalesce(error_code,'timeout') where id = r.id;
    perform public.refund_credit(r.id);   -- flips pending->failed + refunds, idempotent
  end loop;
end; $$;
revoke all on function public.reap_orphans() from public, anon, authenticated;

-- reaper every minute
select cron.schedule('avora-reaper', '* * * * *', $$ select public.reap_orphans(); $$);

-- worker pump every minute (the function loops internally to beat the 1-min floor)
select cron.schedule(
  'avora-worker',
  '* * * * *',
  $$
  select net.http_post(
    url     := current_setting('app.functions_url') || '/process-queue',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.service_role_key'),
      'Content-Type', 'application/json'),
    body    := '{}'::jsonb
  );
  $$
);
```

> The worker pump uses `pg_net` to invoke the deployed `process-queue` function. Set `app.functions_url` and `app.service_role_key` via `alter database ... set ...` in the project (documented in Task 12 deploy notes). Locally, invoke `process-queue` manually instead.

- [ ] **Step 4: Run test to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: PASS — both reaper assertions ok.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/000007_cron_jobs.sql supabase/tests/040_reaper_test.sql
git commit -m "feat: add reaper and worker-pump cron jobs"
```

---

## Task 11: RevenueCat webhook

**Files:**
- Create: `supabase/functions/revenuecat-webhook/index.ts`

**Interfaces:**
- Consumes: `serviceClient`, `json`; tables `purchases`, `profiles`.
- Produces: `POST` verifying a shared bearer token; idempotent on `transaction_id`; applies grants:
  - `INITIAL_PURCHASE` / `RENEWAL` → `weekly_credits = 1000`, store `subscription_period_end`, `subscription_active = true`.
  - `NON_RENEWING_PURCHASE` → `extra_credits += 500`.
  - `CANCELLATION` / `EXPIRATION` → `subscription_active = false` (credits untouched until expiry handled by lazy reset).

- [ ] **Step 1: Write the webhook**

`supabase/functions/revenuecat-webhook/index.ts`:
```ts
import { json } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // shared-secret auth (configured in RevenueCat dashboard as Authorization header)
  const expected = `Bearer ${Deno.env.get("REVENUECAT_WEBHOOK_TOKEN")}`;
  if (req.headers.get("Authorization") !== expected) return json({ error: "unauthorized" }, 401);

  const body = await req.json().catch(() => null);
  const ev = body?.event;
  if (!ev) return json({ error: "bad_request" }, 400);

  const txId: string = ev.transaction_id ?? ev.id;
  const uid: string | undefined = ev.app_user_id;
  const type: string = ev.type;
  if (!txId || !uid) return json({ error: "bad_request" }, 400);

  const db = serviceClient();

  // idempotency: ledger insert; if it already exists, we've processed this event
  const kind = type === "NON_RENEWING_PURCHASE" ? "extra_pack"
             : type === "INITIAL_PURCHASE" ? "initial"
             : type === "RENEWAL" ? "renewal" : "other";
  if (kind !== "other") {
    const { error: dupe } = await db.from("purchases")
      .insert({ transaction_id: txId, user_id: uid, kind });
    if (dupe) return json({ ok: true, deduped: true });  // PK conflict => already done
  }

  if (type === "INITIAL_PURCHASE" || type === "RENEWAL") {
    const periodEnd = ev.expiration_at_ms ? new Date(ev.expiration_at_ms).toISOString() : null;
    await db.from("profiles").update({
      weekly_credits: 1000, subscription_period_end: periodEnd, subscription_active: true,
    }).eq("id", uid);
  } else if (type === "NON_RENEWING_PURCHASE") {
    await db.rpc("grant_extra", { p_uid: uid, p_amount: 500 });
  } else if (type === "CANCELLATION" || type === "EXPIRATION") {
    await db.from("profiles").update({ subscription_active: type !== "EXPIRATION" })
      .eq("id", uid);
  }

  return json({ ok: true });
});
```

- [ ] **Step 2: Add the grant_extra RPC**

`supabase/migrations/000008_grant_extra.sql`:
```sql
create or replace function public.grant_extra(p_uid uuid, p_amount int)
returns void language sql security definer set search_path = public as $$
  update public.profiles set extra_credits = extra_credits + p_amount where id = p_uid;
$$;
revoke all on function public.grant_extra(uuid,int) from public, anon, authenticated;
```

- [ ] **Step 3: Integration-test idempotency**

Serve functions, then replay the same RENEWAL twice and the same extra_pack twice:
```bash
RC='{"event":{"type":"RENEWAL","id":"tx_1","app_user_id":"'$USER_ID'","expiration_at_ms":1790000000000}}'
curl -s -X POST localhost:54321/functions/v1/revenuecat-webhook -H "Authorization: Bearer $RC_TOKEN" -d "$RC"
curl -s -X POST localhost:54321/functions/v1/revenuecat-webhook -H "Authorization: Bearer $RC_TOKEN" -d "$RC"
psql "$DB_URL" -c "select weekly_credits from profiles where id='$USER_ID';"

EP='{"event":{"type":"NON_RENEWING_PURCHASE","id":"tx_2","app_user_id":"'$USER_ID'"}}'
curl -s -X POST localhost:54321/functions/v1/revenuecat-webhook -H "Authorization: Bearer $RC_TOKEN" -d "$EP"
curl -s -X POST localhost:54321/functions/v1/revenuecat-webhook -H "Authorization: Bearer $RC_TOKEN" -d "$EP"
psql "$DB_URL" -c "select extra_credits from profiles where id='$USER_ID';"
```
Expected: `weekly_credits = 1000` (not 2000 — the replay deduped); `extra_credits` increased by exactly 500 (one grant), not 1000.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/revenuecat-webhook/ supabase/migrations/000008_grant_extra.sql
git commit -m "feat: add idempotent RevenueCat credit-granting webhook"
```

---

## Task 12: Seed styles + deploy notes

**Files:**
- Create: `supabase/migrations/000009_seed_styles.sql`
- Create: `supabase/DEPLOY.md`

**Interfaces:**
- Produces: 3 seeded active styles with verbose `prompt_template`s; deploy runbook for secrets + cron settings.

- [ ] **Step 1: Write the seed migration**

`supabase/migrations/000009_seed_styles.sql`:
```sql
insert into public.styles (id, name, prompt_template, sample_image_path) values
('ghibli','Studio Anime',
 'Restyle the entire photo as a hand-painted Japanese animation cel: soft cel shading, '
 'warm painterly lighting, gentle color grading, clean line art, preserve the subject''s '
 'pose and composition, no text, no watermark.', 'samples/ghibli.png'),
('oil','Oil Painting',
 'Repaint the whole image as a textured oil painting with visible brush strokes, rich impasto, '
 'classical warm palette, dramatic lighting, preserve composition and subject likeness, '
 'no text, no watermark.', 'samples/oil.png'),
('cyberpunk','Neon Cyberpunk',
 'Transform the scene into a neon-lit cyberpunk aesthetic: saturated magenta and cyan rim '
 'lighting, rain-slick reflections, futuristic signage bokeh, cinematic contrast, preserve '
 'subject pose and framing, no text, no watermark.', 'samples/cyberpunk.png')
on conflict (id) do nothing;
```

- [ ] **Step 2: Apply and verify clients see styles_public**

Run:
```bash
supabase db reset
psql "$DB_URL" -c "select id, name from public.styles_public order by id;"
```
Expected: three rows (cyberpunk, ghibli, oil); none expose `prompt_template`.

- [ ] **Step 3: Write deploy runbook**

`supabase/DEPLOY.md` — document, with exact commands:
```md
# Deploy

## Secrets (Edge Functions)
supabase secrets set OPENAI_API_KEY=sk-...
supabase secrets set REVENUECAT_WEBHOOK_TOKEN=...

## Database settings for cron worker pump (pg_net target)
alter database postgres set "app.functions_url"   = 'https://<ref>.supabase.co/functions/v1';
alter database postgres set "app.service_role_key" = '<service_role_key>';

## Deploy functions
supabase functions deploy submit-generation get-generation list-generations process-queue revenuecat-webhook

## Apply migrations
supabase db push

## RevenueCat dashboard
- Webhook URL: https://<ref>.supabase.co/functions/v1/revenuecat-webhook
- Authorization header: Bearer <REVENUECAT_WEBHOOK_TOKEN>

## Worker concurrency
- Set WORKER_MAX_BATCH <= current OpenAI tier IPM (Tier 1=5, Tier 3=50).
- Set DAILY_TOKEN_CAP to the daily spend ceiling in tokens.
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/000009_seed_styles.sql supabase/DEPLOY.md
git commit -m "feat: seed initial styles and add deploy runbook"
```

---

## Task 13: Full-suite verification + concurrency load test

**Files:**
- Create: `supabase/tests/run-load-test.sh`

**Interfaces:**
- Produces: a script proving atomic deduction under true parallel load (spec §14).

- [ ] **Step 1: Write the load test**

`supabase/tests/run-load-test.sh`:
```bash
#!/usr/bin/env bash
# Fire N parallel submits on an account with exactly 25 credits (1 generation).
# Expect exactly one 202 and the rest 402.
set -euo pipefail
JWT="$USER_JWT"; UID_PREFIX="$USER_ID"; URL="http://localhost:54321/functions/v1/submit-generation"
psql "$DB_URL" -c "update profiles set weekly_credits=0, extra_credits=25 where id='$UID_PREFIX';"
codes=$(for i in $(seq 1 10); do
  curl -s -o /dev/null -w "%{http_code}\n" -X POST "$URL" \
    -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
    -d "{\"style_id\":\"ghibli\",\"input_path\":\"$UID_PREFIX/test.png\"}" &
done; wait)
echo "$codes" | sort | uniq -c
echo "$codes" | grep -c 202   # must be 1
```

- [ ] **Step 2: Run the load test**

Run: `bash supabase/tests/run-load-test.sh`
Expected: exactly `1` line with `202`, the remaining `9` are `402`. (Requires a valid `test.png` uploaded under the user prefix.)

- [ ] **Step 3: Run the entire pgTAP suite**

Run: `supabase db reset && supabase test db`
Expected: all suites (`010`, `020`, `030`, `040`) PASS.

- [ ] **Step 4: Commit**

```bash
git add supabase/tests/run-load-test.sh
git commit -m "test: add parallel-submit concurrency load test"
```

---

## Self-Review (completed by plan author)

**Spec coverage:** §3 auth/security → Tasks 3,6,7,11 (JWT verify, RLS, service-role secrets). §4 data model → Task 2. §5 credit system → Tasks 5,7,10 (deduct/refund/lazy-reset/reaper). §6 pipeline → Tasks 7,8,9. §7 image config → Task 6 (`_shared/openai.ts`) + Task 12 prompts. §8 input handling → Task 7 server validation. §9 storage → Task 3 buckets/policies (account-deletion cascade handled in iOS plan's settings task + FK `on delete cascade` here). §10 RevenueCat → Task 11. §11 ops (rate limit/spend cap/idempotency/pagination) → Tasks 8,9,11,12. §14 checklist → Tasks 10,11,13.

**Placeholder scan:** no TBD/TODO; all code blocks complete.

**Type consistency:** `deduct_credit→text bucket`, `charged_amount=25`, `refund_credit(p_generation_id)`, `bump_daily_tokens(p_day,p_tokens)`, `grant_extra(p_uid,p_amount)` consistent across migrations and functions.

**Known follow-ups for execution:** local JWT acquisition for integration tests (use `supabase` auth admin API to mint a test user token); confirm `pgmq.read` return columns (`msg_id`, `read_ct`, `message`) against the installed pgmq version and adjust accessors if the version differs.
```
