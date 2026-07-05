# Design: Unique, editable usernames

**Date:** 2026-07-05
**Status:** Approved — ready for implementation planning

## Goal

Every user has a unique username. New users get one automatically the moment they
sign up. Existing users are assigned a random one via a one-time backfill. Users
can change their username at any time from the Settings screen.

## Context

- **Auth:** OAuth-only (Apple + Google) via Supabase (`Avora/Services/AuthService.swift`).
  No passwords, no user-chosen handles today.
- **User model:** `public.profiles` (id → `auth.users`), created automatically by the
  `handle_new_user()` trigger on signup (`supabase/migrations/000004_new_user_trigger.sql`).
- **RLS:** `profiles` is **owner-read-only with no client write policy**
  (`supabase/migrations/000003_rls_policies.sql`). The client can read its own row but
  **cannot** UPDATE profiles directly — so username changes must go through a
  `SECURITY DEFINER` RPC. This is required, not merely cleaner.
- **Next migration number:** `000033` (highest existing is `000032`).

## Architecture

All username logic lives in the database (chosen over client-side generation or an
Edge Function). The profile is already created server-side in the trigger, RLS forces
a definer RPC for both availability checks and writes, and only the DB can guarantee
atomic uniqueness. The client just calls two RPCs and reads its own row.

## Username rules

- **Characters:** lowercase letters, digits, underscore (`a-z`, `0-9`, `_`)
- **Length:** 3–20 characters
- **Must contain at least one letter** (no pure-number ID-looking handles)
- **Uniqueness:** case-insensitive — trivially satisfied because only lowercase is
  allowed, so no `citext` needed
- **Availability:** live check as the user types (UX only) + authoritative atomic
  check on save (DB unique index is source of truth)

## 1. Data model

Add to `public.profiles`:

```sql
username text
```

- **Unique index:** `create unique index profiles_username_key on public.profiles (username);`
- **CHECK constraint:** `check (username ~ '^[a-z0-9_]{3,20}$' and username ~ '[a-z]')`
- Column is **nullable** in the schema (avoids fighting insert ordering inside the
  trigger). Every row gets a value via trigger (new users) or backfill (existing).

## 2. Auto-generation (word-based, e.g. `swiftpanda42`)

`public.generate_username() returns text`:

- Two curated arrays in the function body — ~30 **adjectives** (`swift`, `clever`,
  `brave`, `calm`, `bright`, …) and ~30 **nouns** (`panda`, `otter`, `fox`, `hawk`,
  `lion`, …). ~900 base combos × number suffix = large namespace.
- Builds `adjective + noun + (random 2–3 digit number)` → e.g. `swiftpanda42`.
- **Collision retry loop:** check the unique index; regenerate if taken. After ~10
  tries, fall back to appending more random digits so termination is **guaranteed**
  even as the space fills.
- Output satisfies the CHECK constraint by construction.

The existing `handle_new_user()` trigger gains one line: set
`username = generate_username()` when inserting the profile row. New users are named
the instant they sign up — zero client involvement.

## 3. Backfill for existing users

One-time migration step, after the column + function exist:

```sql
update public.profiles
set username = generate_username()
where username is null;
```

- Row-by-row; each call re-checks uniqueness against already-assigned rows, so no
  collisions within the backfill.
- **Not** adding `set not null` (YAGNI) — trigger + backfill already guarantee
  coverage, and NOT NULL adds a failure mode if the trigger ever ordering-conflicts.
  The unique index is the constraint that matters.

## 4. RPCs (the client's only write path)

Both `SECURITY DEFINER`, granted to `authenticated` only.

**`is_username_available(candidate text) returns boolean`**
- Validates format first (malformed → `false`).
- Checks the unique index, excluding the caller's own current username (so re-saving
  your own name isn't reported "taken").
- Used for the **live** availability check as the user types.

**`set_username(new_username text) returns text`**
- Scopes to `auth.uid()` — a user can only change their own username.
- Validates format → returns `invalid` on failure.
- Attempts the update; unique index makes it atomic. On `unique_violation` → `taken`.
- Returns a status string (`ok` / `taken` / `invalid`) the client maps to friendly
  copy. **Authoritative** — the live check is UX only; races are caught here.

## 5. Client (iOS / Settings)

- **Read:** app reads current `username` from its own `profiles` row (owner-select RLS
  policy), wired into `AppState`/profile load and displayed in `SettingsView`.
- **Edit UI:** a Settings row showing the current username; tapping opens an edit
  field (sheet or inline).
  - On type: client-side format validation (mirrors the rules for instant feedback) +
    debounced `is_username_available` → ✓ available / ✗ taken / invalid.
  - **Save** calls `set_username`; `ok` → update local state + dismiss; `taken`/
    `invalid` → inline error. Server result is authoritative even if the live check
    passed (race safety).
- A small `AvoraAPI` method wraps each RPC. No new screens beyond the Settings edit
  affordance.

## 6. Error handling & testing

- **DB tests** (following `supabase/tests/*.sql`):
  - Format CHECK rejects bad input (too short/long, uppercase, symbols, pure-number).
  - Unique index blocks duplicates.
  - `generate_username()` returns valid, unique names under contention.
  - `set_username` returns `ok` / `taken` / `invalid` correctly; cannot overwrite
    another user's row.
  - Backfill assigns all null rows.
- **Client:** validation logic unit-testable in isolation; manual verification of the
  Settings edit + availability flow.

## Scope boundaries

- Username is displayed and edited **only in Settings**. Nothing else consumes it yet
  (no social/sharing/leaderboard features).
- No reserved-name blocklist (`admin`, `avora`, …) — out of scope unless requested.
- No hyphens, no uppercase, no length changes from 3–20.
