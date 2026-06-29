# Credit Config Single Source of Truth — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a singleton Postgres `credit_config` table the single runtime source of truth for the four credit-economics values, read by all backend SQL/TS and by the mobile app.

**Architecture:** A new forward-only migration `000020` creates the table, seeds it, exposes it read-only to clients, and `create or replace`s the four credit functions to read from it. The RevenueCat webhook stops passing hardcoded amounts. Mobile gains a `CreditConfig` model fetched on launch with baked-in fallback defaults.

**Tech Stack:** Supabase (Postgres + pgTAP tests + Deno/TS edge functions), Swift / SwiftUI (supabase-swift PostgREST), XcodeBuildMCP for builds.

## Global Constraints

- **Forward-only migrations.** The schema is deployed to a linked remote via `supabase db push`. Do **not** edit `000002` / `000004` / `000005` / `000013`; supersede them in `000020`. (Convention already used by `000015`, `000019`.)
- **Seed values:** `weekly_amount=1000`, `signup_extra=50`, `generation_cost=20`, `extra_pack=500`. Note `generation_cost` changes from 25 → **20**.
- **No plan/finding references in code or migration names** — describe the *why*, not the origin.
- **pgTAP tests** live in `supabase/tests/NNN_*_test.sql` and run via `supabase test db` (a local Supabase stack must be running: `supabase start`).
- Each `generations` row stores its own `charged_amount`; refunds use that stored value, never the live config.

---

### Task 1: Create the `credit_config` table (schema + client read access)

**Files:**
- Create: `supabase/migrations/000020_credit_config.sql`
- Modify (test): `supabase/tests/010_schema_test.sql`

**Interfaces:**
- Produces: table `public.credit_config` with columns `weekly_amount int`, `signup_extra int`, `generation_cost int`, `extra_pack int`, singleton (`id boolean pk check (id)`), one seeded row `(1000, 50, 20, 500)`. Readable by `authenticated, anon`.

- [ ] **Step 1: Update the schema test to expect the new table and the changed default**

Replace the entire contents of `supabase/tests/010_schema_test.sql` with:

```sql
begin;
select plan(14);

select has_table('public', 'profiles', 'profiles exists');
select has_table('public', 'styles', 'styles exists');
select has_table('public', 'generations', 'generations exists');
select has_table('public', 'purchases', 'purchases exists');
select has_table('public', 'daily_spend', 'daily_spend exists');

select col_default_is('public', 'profiles', 'extra_credits', '50', 'starter extra default still 50 (changed in next task)');
select col_has_check('public', 'generations', 'status', 'status is constrained');
select has_column('public', 'generations', 'charged_amount', 'charged_amount column exists');
select col_is_pk('public', 'purchases', 'transaction_id', 'purchases pk is transaction_id');

-- new-user trigger grants 50 starter credits from config, exactly once
insert into auth.users (id, email)
  values ('33333333-3333-3333-3333-333333333333','c@test.dev');
select is(
  (select extra_credits from public.profiles
     where id = '33333333-3333-3333-3333-333333333333'),
  50, 'trigger creates profile with 50 starter credits from config');

-- credit_config is the singleton source of truth, readable by clients
select has_table('public', 'credit_config', 'credit_config exists');
select col_is_pk('public', 'credit_config', 'id', 'credit_config pk is id (singleton)');
select is((select count(*)::int from public.credit_config), 1, 'credit_config has exactly one row');
select table_privs_are('public', 'credit_config', 'anon', ARRAY['SELECT'], 'anon can read credit_config');

select * from finish();
rollback;
```

- [ ] **Step 2: Run the schema test to verify it fails**

Run: `supabase test db`
Expected: `010_schema_test` FAILs — `credit_config` does not exist yet and `extra_credits` default is still `50`.

- [ ] **Step 3: Create the migration with the table only**

Create `supabase/migrations/000020_credit_config.sql` with:

```sql
-- Single source of truth for credit economics. One row; all backend credit
-- math reads from it, and the mobile app fetches it (with baked-in fallbacks).

create table public.credit_config (
  id              boolean primary key default true check (id),  -- singleton row
  weekly_amount   int not null,   -- weekly bucket granted on subscription/renewal
  signup_extra    int not null,   -- free extra credits granted at signup
  generation_cost int not null,   -- credits deducted per generation
  extra_pack      int not null    -- credits added per extra-pack purchase
);

insert into public.credit_config (weekly_amount, signup_extra, generation_cost, extra_pack)
  values (1000, 50, 20, 500);

-- These four numbers are user-facing economics, so clients may read them.
-- Revoke the broad default grants first so clients get SELECT only (writes are
-- also blocked by RLS having no write policy).
alter table public.credit_config enable row level security;
revoke all on public.credit_config from authenticated, anon;
create policy credit_config_read on public.credit_config
  for select to authenticated, anon using (true);
grant select on public.credit_config to authenticated, anon;
```

The column default change and the function rewires land in Task 2 — Task 1 adds only the table, so it stays independently green.

- [ ] **Step 4: Run the schema test to verify it passes**

Run: `supabase test db`
Expected: `010_schema_test` PASSes all 14; full suite green.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/000020_credit_config.sql supabase/tests/010_schema_test.sql
git commit -m "feat: add credit_config singleton table with client read access"
```

---

### Task 2: Rewire the credit functions to read from config

**Files:**
- Modify: `supabase/migrations/000020_credit_config.sql` (append function definitions + column default)
- Modify (test): `supabase/tests/030_credit_rpcs_test.sql`
- Modify (test): `supabase/tests/010_schema_test.sql` (flip the `extra_credits` default assertion)

**Interfaces:**
- Consumes: `public.credit_config` (Task 1).
- Produces: `extra_credits` column default → 0; `handle_new_user()` grants `signup_extra` from config; `deduct_credit(uuid)` charges `generation_cost` from config; `lazy_weekly_reset(uuid)` sets weekly to `weekly_amount` from config. Function signatures unchanged.

- [ ] **Step 1: Flip the `extra_credits` default assertion in the schema test**

In `supabase/tests/010_schema_test.sql`, change the `col_default_is` line to expect `0`:

```sql
select col_default_is('public', 'profiles', 'extra_credits', '0', 'starter extra default is now 0 (config-driven)');
```

- [ ] **Step 2: Update the credit-rpc test for cost = 20 and config-driven behavior**

Replace the entire contents of `supabase/tests/030_credit_rpcs_test.sql` with:

```sql
begin;
select plan(10);

insert into auth.users (id, email) values ('44444444-4444-4444-4444-444444444444','d@test.dev');
-- profile auto-created with extra=50 (from config), weekly=0
update public.profiles set weekly_credits = 20
  where id = '44444444-4444-4444-4444-444444444444';
insert into public.styles (id, name, prompt_template) values ('s1','S1','x');

-- weekly is spent first; cost is 20 (read from credit_config)
select is(deduct_credit('44444444-4444-4444-4444-444444444444'), 'weekly', 'charges weekly first');
select is((select weekly_credits from public.profiles where id='44444444-4444-4444-4444-444444444444'),
          0, 'weekly now 0');

-- next charge falls to extra
select is(deduct_credit('44444444-4444-4444-4444-444444444444'), 'extra', 'falls back to extra');
select is((select extra_credits from public.profiles where id='44444444-4444-4444-4444-444444444444'),
          30, 'extra now 30 (was 50, charged 20)');

-- refund is idempotent and returns the stored charged_amount to the charged bucket
insert into public.generations (id, user_id, style_id, status, charged_bucket, charged_amount, input_path, quality)
  values ('bbbbbbbb-0000-0000-0000-000000000001',
          '44444444-4444-4444-4444-444444444444','s1','pending','extra',20,'in/x.png','medium');
select refund_credit('bbbbbbbb-0000-0000-0000-000000000001');
select is((select extra_credits from public.profiles where id='44444444-4444-4444-4444-444444444444'),
          50, 'refund returns 20 to extra');
select refund_credit('bbbbbbbb-0000-0000-0000-000000000001'); -- second call: no-op
select is((select extra_credits from public.profiles where id='44444444-4444-4444-4444-444444444444'),
          50, 'refund is idempotent (still 50)');

-- insufficient credits raises
update public.profiles set weekly_credits = 0, extra_credits = 0
  where id = '44444444-4444-4444-4444-444444444444';
select throws_ok(
  $$ select deduct_credit('44444444-4444-4444-4444-444444444444') $$,
  'P0001', 'insufficient_credits', 'raises when no bucket has >= 20');

-- exactly-one semantics: with weekly=20, two deducts -> one ok, one raises
update public.profiles set weekly_credits = 20, extra_credits = 0
  where id = '44444444-4444-4444-4444-444444444444';
select lives_ok($$ select deduct_credit('44444444-4444-4444-4444-444444444444') $$,
  'first deduct succeeds');
select throws_ok($$ select deduct_credit('44444444-4444-4444-4444-444444444444') $$,
  'P0001', 'insufficient_credits', 'second deduct on drained account raises');

-- cost is read live from config: change it and the next deduct uses the new value
update public.credit_config set generation_cost = 10;
update public.profiles set weekly_credits = 10, extra_credits = 0
  where id = '44444444-4444-4444-4444-444444444444';
select is(deduct_credit('44444444-4444-4444-4444-444444444444'), 'weekly',
  'deduct uses the updated config cost (10)');

select * from finish();
rollback;
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `supabase test db`
Expected: `010_schema_test` FAILs (default still 50) and `030_credit_rpcs_test` FAILs (`deduct_credit` still charges 25, so `extra now 30` and the config-change assertions fail).

- [ ] **Step 4: Append the column default + rewired functions to the migration**

Append to `supabase/migrations/000020_credit_config.sql`:

```sql
-- Starter grant now comes from config; the column default is no longer the source.
alter table public.profiles alter column extra_credits set default 0;

-- New users get their starter extra credits from config.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, extra_credits)
    values (new.id, (select signup_extra from public.credit_config))
    on conflict (id) do nothing;
  return new;
end;
$$;

-- Per-generation cost read from config.
create or replace function public.deduct_credit(p_uid uuid)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  v_cost int;
  v_bucket text;
begin
  select generation_cost into v_cost from public.credit_config;

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

-- Weekly reset amount read from config.
create or replace function public.lazy_weekly_reset(p_uid uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.profiles
    set weekly_credits = (select weekly_amount from public.credit_config)
    where id = p_uid
      and subscription_active = true
      and subscription_period_end is not null
      and now() > subscription_period_end;
end;
$$;
```

- [ ] **Step 5: Run the suite to verify it passes**

Run: `supabase test db`
Expected: all of `010`, `020`, `030`, `040` PASS (no regressions in RLS/reaper tests).

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/000020_credit_config.sql supabase/tests/010_schema_test.sql supabase/tests/030_credit_rpcs_test.sql
git commit -m "feat: read generation/weekly/signup amounts from credit_config"
```

---

### Task 3: Move purchase grant amounts into `apply_purchase`; simplify the webhook

**Files:**
- Modify: `supabase/migrations/000020_credit_config.sql` (append)
- Create (test): `supabase/tests/050_apply_purchase_test.sql`
- Modify: `supabase/functions/revenuecat-webhook/index.ts`

**Interfaces:**
- Consumes: `public.credit_config` (Task 1).
- Produces: new overload `apply_purchase(p_tx text, p_uid uuid, p_kind text, p_period_end timestamptz) returns text`. The old 6-arg overload is dropped. `renewal`/`initial` set `weekly_credits = weekly_amount` from config; `extra_pack` adds `extra_pack` from config.

- [ ] **Step 1: Write the apply_purchase pgTAP test**

Create `supabase/tests/050_apply_purchase_test.sql` with:

```sql
begin;
select plan(6);

insert into auth.users (id, email) values ('66666666-6666-6666-6666-666666666666','f@test.dev');
-- profile auto-created: extra=50 (config signup_extra), weekly=0

-- initial purchase sets weekly to config weekly_amount (1000) and activates
select is(apply_purchase('tx1','66666666-6666-6666-6666-666666666666','initial', now() + interval '7 days'),
          'applied', 'initial purchase applied');
select is((select weekly_credits from public.profiles where id='66666666-6666-6666-6666-666666666666'),
          1000, 'weekly set to config weekly_amount (1000)');
select is((select subscription_active from public.profiles where id='66666666-6666-6666-6666-666666666666'),
          true, 'subscription activated');

-- duplicate transaction is deduped (idempotent)
select is(apply_purchase('tx1','66666666-6666-6666-6666-666666666666','renewal', now() + interval '7 days'),
          'deduped', 'duplicate transaction id is deduped');

-- extra_pack adds config extra_pack (500) to extra_credits (was 50)
select is(apply_purchase('tx2','66666666-6666-6666-6666-666666666666','extra_pack', null),
          'applied', 'extra_pack applied');
select is((select extra_credits from public.profiles where id='66666666-6666-6666-6666-666666666666'),
          550, 'extra increased by config extra_pack (50 + 500)');

select * from finish();
rollback;
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `supabase test db`
Expected: `050_apply_purchase_test` FAILs — the 4-arg `apply_purchase` overload does not exist (only the old 6-arg one does).

- [ ] **Step 3: Append the dropped-old / new apply_purchase to the migration**

Append to `supabase/migrations/000020_credit_config.sql`:

```sql
-- apply_purchase now reads grant amounts from config; the webhook no longer
-- passes them. Drop the old wider signature first (create-or-replace cannot
-- change a function's parameter list).
drop function if exists public.apply_purchase(text, uuid, text, int, int, timestamptz);

create or replace function public.apply_purchase(
  p_tx         text,
  p_uid        uuid,
  p_kind       text,         -- 'initial' | 'renewal' | 'extra_pack'
  p_period_end timestamptz   -- subscription_period_end for renewal/initial (ignored for extra_pack)
)
returns text                 -- 'applied' | 'deduped'
language plpgsql
security definer set search_path = public
as $$
declare
  v_inserted boolean := false;
begin
  insert into public.purchases(transaction_id, user_id, kind)
    values (p_tx, p_uid, p_kind)
    on conflict (transaction_id) do nothing;

  get diagnostics v_inserted = row_count;

  if not v_inserted then
    return 'deduped';
  end if;

  if p_kind in ('renewal', 'initial') then
    update public.profiles
      set weekly_credits          = (select weekly_amount from public.credit_config),
          subscription_period_end = p_period_end,
          subscription_active     = true
      where id = p_uid;
  elsif p_kind = 'extra_pack' then
    update public.profiles
      set extra_credits = extra_credits + (select extra_pack from public.credit_config)
      where id = p_uid;
  end if;

  return 'applied';
end;
$$;

revoke all on function public.apply_purchase(text, uuid, text, timestamptz)
  from public, anon, authenticated;
-- Only the service role (used by the RevenueCat webhook) may call this.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `supabase test db`
Expected: `050_apply_purchase_test` PASSes all 6; full suite green.

- [ ] **Step 5: Update the webhook to stop passing amounts**

In `supabase/functions/revenuecat-webhook/index.ts`, replace the `INITIAL_PURCHASE`/`RENEWAL` rpc call (currently passing `p_weekly_set`/`p_extra_delta`):

```ts
    const { data: result, error: rpcErr } = await db.rpc("apply_purchase", {
      p_tx:          txId,
      p_uid:         uid,
      p_kind:        kind,
      p_period_end:  periodEnd,
    });
```

and replace the `NON_RENEWING_PURCHASE` rpc call:

```ts
    const { data: result, error: rpcErr } = await db.rpc("apply_purchase", {
      p_tx:          txId,
      p_uid:         uid,
      p_kind:        "extra_pack",
      p_period_end:  null,
    });
```

Leave the `EXPIRATION` branch (`weekly_credits: 0`) and everything else unchanged.

- [ ] **Step 6: Type-check the edge function**

Run: `deno check supabase/functions/revenuecat-webhook/index.ts`
Expected: no errors. (If `deno` is unavailable locally, confirm there are no remaining references to `p_weekly_set` or `p_extra_delta`: `grep -n "p_weekly_set\|p_extra_delta" supabase/functions/revenuecat-webhook/index.ts` returns nothing.)

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/000020_credit_config.sql supabase/tests/050_apply_purchase_test.sql supabase/functions/revenuecat-webhook/index.ts
git commit -m "feat: read purchase grant amounts from credit_config; drop hardcoded webhook amounts"
```

---

### Task 4: Wire the mobile app to `credit_config`

**Files:**
- Create: `Avora/Models/CreditConfig.swift`
- Modify: `Avora/Models/Profile.swift`
- Modify: `Avora/Services/AvoraAPI.swift`
- Modify: `Avora/State/AppState.swift`

**Interfaces:**
- Consumes: `public.credit_config` view via PostgREST (`weekly_amount,signup_extra,generation_cost,extra_pack`).
- Produces: `CreditConfig` model (`.fallback` static), `AvoraAPI.fetchCreditConfig() async throws -> CreditConfig`, `AppState.config: CreditConfig`, `AppState.generations(for credits: Int) -> Int`. Removes `Profile.totalGenerations`.

> No XCTest target exists in this project, so verification is a clean simulator build via XcodeBuildMCP plus a grep confirming the old hardcoded `/ 25` is gone.

- [ ] **Step 1: Create the CreditConfig model with fallback defaults**

Create `Avora/Models/CreditConfig.swift`:

```swift
import Foundation

struct CreditConfig: Codable {
    let weeklyAmount: Int
    let signupExtra: Int
    let generationCost: Int
    let extraPack: Int

    enum CodingKeys: String, CodingKey {
        case weeklyAmount = "weekly_amount"
        case signupExtra = "signup_extra"
        case generationCost = "generation_cost"
        case extraPack = "extra_pack"
    }

    /// Baked-in defaults so the app works offline and before the first fetch.
    /// Must mirror the seed row in migration 000020_credit_config.sql.
    static let fallback = CreditConfig(
        weeklyAmount: 1000, signupExtra: 50, generationCost: 20, extraPack: 500
    )
}
```

- [ ] **Step 2: Remove the hardcoded generation cost from Profile**

In `Avora/Models/Profile.swift`, delete the `totalGenerations` computed property (line 7):

```swift
    var totalGenerations: Int { totalCredits / 25 }
```

So the struct becomes:

```swift
import Foundation

struct Profile: Codable {
    let weeklyCredits: Int
    let extraCredits: Int
    var totalCredits: Int { weeklyCredits + extraCredits }

    enum CodingKeys: String, CodingKey {
        case weeklyCredits = "weekly_credits"
        case extraCredits = "extra_credits"
    }
}
```

- [ ] **Step 3: Add the fetch method to AvoraAPI**

In `Avora/Services/AvoraAPI.swift`, add after `fetchProfile()` (after line 34):

```swift
    func fetchCreditConfig() async throws -> CreditConfig {
        try await db.from("credit_config")
            .select("weekly_amount,signup_extra,generation_cost,extra_pack")
            .single()
            .execute()
            .value
    }
```

- [ ] **Step 4: Add config state and the generations helper to AppState**

In `Avora/State/AppState.swift`:

Add the stored property after `var styles: [Style] = []` (line 13):

```swift
    // Credit economics fetched from the backend; seeded with fallback defaults
    // so the first frame and offline sessions still work.
    var config: CreditConfig = .fallback
```

In `bootstrap()`, load the config alongside the profile — change the `if session != nil` block:

```swift
        if session != nil {
            isAuthenticated = true
            await configureRevenueCat()
            await refreshProfile()
            await loadConfig()
        } else if SupabaseClientProvider.client.auth.currentSession == nil {
```

Add the loader and helper after `refreshProfile()` (after line 34):

```swift
    func loadConfig() async {
        if let fetched = try? await AvoraAPI.shared.fetchCreditConfig() {
            config = fetched
        }
    }

    /// Number of generations buyable with `credits`, using the live config cost.
    func generations(for credits: Int) -> Int {
        credits / config.generationCost
    }
```

- [ ] **Step 5: Confirm the old hardcoded cost is gone**

Run: `grep -rn "/ 25\|totalGenerations" Avora --include="*.swift"`
Expected: no output.

- [ ] **Step 6: Build the app for the simulator**

Use XcodeBuildMCP: call `session_show_defaults` to confirm project/scheme/simulator, then `build_sim`.
Expected: BUILD SUCCEEDED. (`CreditConfig.swift` is in a synchronized folder group, so Xcode picks it up automatically — no project.pbxproj edit needed.)

- [ ] **Step 7: Commit**

```bash
git add Avora/Models/CreditConfig.swift Avora/Models/Profile.swift Avora/Services/AvoraAPI.swift Avora/State/AppState.swift
git commit -m "feat: fetch credit config on launch with fallback defaults"
```

---

### Task 5: Deploy

**Files:** none (deploy commands only).

> Run only after Tasks 1–4 are merged. Requires the Supabase CLI linked to the project (`supabase/.temp/linked-project.json` → ref `dqdsuzmqlnheiokfboyv`).

- [ ] **Step 1: Apply the migration to the remote**

Run: `supabase db push`
Expected: `000020_credit_config.sql` applied; no errors.

- [ ] **Step 2: Deploy the updated webhook**

Run: `supabase functions deploy revenuecat-webhook`
Expected: deploy succeeds.

- [ ] **Step 3: Sanity-check the live config row**

Verify via the Supabase SQL editor (or `psql`): `select * from public.credit_config;`
Expected: one row `(t, 1000, 50, 20, 500)`.

---

## Self-Review

**Spec coverage:**
- Singleton `credit_config` table + seed + RLS/grant → Task 1. ✅
- `deduct_credit` reads config → Task 2. ✅
- `lazy_weekly_reset` reads config → Task 2. ✅
- `handle_new_user` reads config + column default → 0 → Task 2 (paired). ✅
- `apply_purchase` reads config, params dropped → Task 3. ✅
- Webhook stops passing amounts → Task 3. ✅
- `generation_cost` 25 → 20 → Task 1 seed + Task 2/3 tests. ✅
- Mobile `CreditConfig` model + fallback → Task 4. ✅
- `fetchCreditConfig` → Task 4. ✅
- `AppState.config` loaded in bootstrap + `generations(for:)` → Task 4. ✅
- Remove `Profile.totalGenerations` → Task 4. ✅
- Existing pgTAP tests updated for new values → Tasks 1 (010) + 2 (030). ✅
- Forward-only single migration → Global Constraints + all backend tasks. ✅

**Placeholder scan:** No TBD/TODO/"add error handling" — every code step shows complete code. ✅

**Type consistency:** `CreditConfig` property names (`weeklyAmount`, `signupExtra`, `generationCost`, `extraPack`) and CodingKeys match across Task 4 steps; `apply_purchase(text, uuid, text, timestamptz)` signature consistent between Task 3 migration, test, revoke, and webhook call. ✅

**Note on ordering:** The `extra_credits` column default → 0 change is paired with the `handle_new_user` rewrite in **Task 2** (not split across tasks), so new users never get 0 starter credits in any intermediate state. Each task is independently green and committable.
