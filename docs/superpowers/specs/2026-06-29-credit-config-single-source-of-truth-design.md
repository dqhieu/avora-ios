# Credit config as a single source of truth

**Date:** 2026-06-29
**Status:** Approved, pending implementation plan

## Problem

The credit economics values are hardcoded in multiple places across the backend
(Postgres migrations + Deno/TS edge function) and the mobile app (Swift). The same
number lives in more than one file (e.g. the weekly amount `1000` appears in both a
SQL function and the webhook), so they drift apart silently.

The four values:

| Value | Meaning | Hardcoded today |
|---|---|---|
| `weekly_amount` | weekly bucket granted on subscription/renewal | `lazy_weekly_reset` (000005) + `revenuecat-webhook` `p_weekly_set` |
| `signup_extra` | free extra credits granted at signup | `extra_credits int default 50` (000002) |
| `generation_cost` | credits deducted per generation | `deduct_credit` `v_cost := 25` (000005) + `Profile.totalGenerations` (Swift) |
| `extra_pack` | credits added per extra-pack purchase | `revenuecat-webhook` `p_extra_delta` |

## Goal

A single runtime source of truth that both backend and mobile read from. Changing a
value should require neither a migration nor an App Store release.

## Decision: runtime-editable Postgres table

A singleton `credit_config` table is the source of truth. SQL functions read it
directly; mobile fetches it on launch (with baked-in fallback defaults). Editing a
value is one `update` in the Supabase dashboard.

### Seed values (note: generation_cost changes 25 → 20)

| column | value |
|---|---|
| `weekly_amount` | 1000 |
| `signup_extra` | 50 |
| `generation_cost` | **20** (was 25) |
| `extra_pack` | 500 |

`generation_cost` is only the cost of *new* generations. Each `generations` row stores
its own `charged_amount`, and `refund_credit` refunds that stored amount — so
in-flight generations charged at 25 still refund 25 correctly.

## Design

### 1. The table (new migration `000020_credit_config.sql`)

```sql
create table public.credit_config (
  id              boolean primary key default true check (id),  -- singleton: only one row
  weekly_amount   int not null,
  signup_extra    int not null,
  generation_cost int not null,
  extra_pack      int not null
);
insert into public.credit_config (weekly_amount, signup_extra, generation_cost, extra_pack)
  values (1000, 50, 20, 500);

-- read-only client exposure (these are user-facing economics)
alter table public.credit_config enable row level security;
create policy credit_config_read on public.credit_config
  for select to authenticated, anon using (true);
grant select on public.credit_config to authenticated, anon;
```

The `id boolean primary key check (id)` enforces a single row.

### 2. Backend rewiring (forward-only, all in `000020`)

The schema is deployed to a linked remote via `supabase db push`, and this repo
already follows a forward-only convention (see `000015`, `000019`: new
`alter`/`create or replace` migrations rather than editing applied files). So the
rewiring lives entirely in `000020` — the original `000002/000004/000005/000013`
files are **not edited**; `000020` supersedes their definitions with
`create or replace` / `alter table`.

All four SQL/TS hardcodes read the table instead:

- **`deduct_credit`** — `v_cost int := 25` → `select generation_cost into v_cost from public.credit_config;`
- **`lazy_weekly_reset`** — `set weekly_credits = 1000` → `= (select weekly_amount from public.credit_config)`
- **`handle_new_user`** — insert `extra_credits` explicitly from `signup_extra`:
  ```sql
  insert into public.profiles (id, extra_credits)
    values (new.id, (select signup_extra from public.credit_config))
    on conflict (id) do nothing;
  ```
  and change the column default from `50` to `0` so the value lives in exactly one place.
- **`apply_purchase`** — move the amounts into the function and drop the
  `p_weekly_set` / `p_extra_delta` params:
  - `initial`/`renewal`: `set weekly_credits = (select weekly_amount from public.credit_config)`
  - `extra_pack`: `set extra_credits = extra_credits + (select extra_pack from public.credit_config)`
  - update the `revoke` to match the new signature.
- **`revenuecat-webhook/index.ts`** — stop passing `p_weekly_set` / `p_extra_delta`;
  call `apply_purchase` with only `p_tx`, `p_uid`, `p_kind`, `p_period_end`. After this
  there are **zero hardcoded credit numbers in TypeScript**. (The `EXPIRATION` →
  `weekly_credits: 0` path stays — zero is a reset, not a config value.)

`deduct_credit`, `lazy_weekly_reset`, `apply_purchase`, and `handle_new_user` are all
`security definer`, so they read `credit_config` regardless of RLS.

### 3. Mobile consumption (full wiring)

- **`CreditConfig: Codable`** model with baked-in fallback defaults
  (`weekly_amount 1000, signup_extra 50, generation_cost 20, extra_pack 500`) so the
  app works offline / before the first fetch.
- **`AvoraAPI.fetchCreditConfig()`** — one `.from("credit_config").select(...).single()`,
  same shape as `fetchProfile()`.
- **`AppState`** gains `var config: CreditConfig` (seeded with the fallback), loaded in
  `bootstrap()` alongside the profile.
- **`Profile.totalGenerations`** (the hardcoded `/ 25`) is removed from `Profile` and
  replaced by a config-aware helper on `AppState`, e.g.
  `func generations(for credits: Int) -> Int { credits / config.generationCost }`,
  since `Profile` alone cannot see the config.

## Out of scope

- Per-product extra-pack sizes (today the extra pack is a flat amount regardless of
  which non-renewing product was bought — unchanged).
- Caching/refresh strategy beyond fetch-on-launch with fallback defaults.
- Admin UI for editing the values (use the Supabase dashboard).

## Files touched

**Backend** (forward-only — only one new SQL file + the edge function)
- `supabase/migrations/000020_credit_config.sql` (new): create table + RLS/grant,
  `create or replace` of `deduct_credit` / `lazy_weekly_reset` / `handle_new_user` /
  `apply_purchase`, and `alter table public.profiles alter column extra_credits set default 0`
- `supabase/functions/revenuecat-webhook/index.ts` (stop passing amounts)
- `000002` / `000004` / `000005` / `000013` are **not edited** (superseded by `000020`)

**Mobile**
- `Avora/Models/CreditConfig.swift` (new)
- `Avora/Models/Profile.swift` (remove `totalGenerations`)
- `Avora/Services/AvoraAPI.swift` (add `fetchCreditConfig`)
- `Avora/State/AppState.swift` (add `config`, load in `bootstrap`, add `generations(for:)`)

## Resolved decisions

- **Migration strategy:** forward-only in a single `000020` migration (the schema is
  deployed to a linked remote via `supabase db push`; existing files are not edited).
- **Generation cost:** seed at 20 (was 25); per-row `charged_amount` keeps old refunds correct.
- **Mobile:** fully wired now (fetch + fallback defaults + `AppState.generations(for:)`).
