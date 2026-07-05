# Unique Editable Usernames Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every user a unique username — auto-generated on signup, backfilled for existing users, and editable from the Settings screen.

**Architecture:** All username logic lives in Postgres (Supabase). A `username` column on `public.profiles` with a unique index + format CHECK is the source of truth. A `generate_username()` function produces word-based handles (`swiftpanda42`); the existing `handle_new_user()` trigger calls it for new users, and a one-time backfill covers existing rows. Because `profiles` has no client write policy, the iOS app changes usernames only through two `SECURITY DEFINER` RPCs (`is_username_available`, `set_username`) and reads its own username via the existing owner-select policy.

**Tech Stack:** Supabase Postgres (plpgsql, pgTAP tests via `supabase test db`), Swift / SwiftUI, `supabase-swift` SDK.

**Spec:** `docs/superpowers/specs/2026-07-05-unique-usernames-design.md`

## Global Constraints

- **Username format:** lowercase letters + digits + underscore only; regex `^[a-z0-9_]{3,20}$` AND must match `[a-z]` (at least one letter). Same rule enforced in the DB CHECK, both RPCs, and the client validator — copy it verbatim everywhere.
- **Uniqueness:** case-insensitive, satisfied trivially because only lowercase is allowed. No `citext`.
- **No client writes to `profiles`:** all username changes go through `set_username`. Never add a client UPDATE policy.
- **Migrations are append-only:** next numbers are `000033` and `000034`. Never edit an applied migration.
- **RPC grants:** `revoke all ... from public, anon;` then `grant execute ... to authenticated;` (mirror `mark_signup_bonus_seen` in `000029`).
- **DB tests:** pgTAP files in `supabase/tests/NNN_*.sql`, run with `supabase test db`. Next numbers: `070`, `071`.
- **No iOS unit-test target exists.** Client verification is: app compiles + manual check. Keep validation logic in a pure, standalone function.

---

### Task 1: DB — username column, generator, trigger, backfill

**Files:**
- Create: `supabase/migrations/000033_usernames.sql`
- Create: `supabase/tests/070_usernames_test.sql`

**Interfaces:**
- Produces:
  - `public.profiles.username text` (nullable in schema; every row populated), unique index `profiles_username_key`, CHECK `profiles_username_format`.
  - `public.generate_username() returns text` — returns a unique handle matching `^[a-z0-9_]{3,20}$` with ≥1 letter.
  - `public.handle_new_user()` now sets `username = public.generate_username()`.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/070_usernames_test.sql`:

```sql
begin;
select plan(8);

-- schema
select has_column('public', 'profiles', 'username', 'username column exists');
select col_type_is('public', 'profiles', 'username', 'text', 'username is text');
select has_index('public', 'profiles', 'profiles_username_key', 'username');

-- generator output is always valid
select matches(public.generate_username(),
  '^[a-z0-9_]{3,20}$', 'generate_username matches format');
select matches(public.generate_username(),
  '[a-z]', 'generate_username contains a letter');

-- new user gets a username from the trigger
insert into auth.users (id, email)
  values ('a1111111-1111-1111-1111-111111111111', 'u1@test.dev');
select isnt(
  (select username from public.profiles
     where id = 'a1111111-1111-1111-1111-111111111111'),
  null, 'trigger assigns a username to new users');

-- unique index blocks duplicates
insert into auth.users (id, email)
  values ('a2222222-2222-2222-2222-222222222222', 'u2@test.dev');
update public.profiles set username = 'takenname1'
  where id = 'a1111111-1111-1111-1111-111111111111';
select throws_ok(
  $$ update public.profiles set username = 'takenname1'
       where id = 'a2222222-2222-2222-2222-222222222222' $$,
  '23505', null, 'duplicate username is rejected');

-- format CHECK rejects invalid values (uppercase)
select throws_ok(
  $$ update public.profiles set username = 'BadName'
       where id = 'a2222222-2222-2222-2222-222222222222' $$,
  '23514', null, 'invalid format is rejected by CHECK');

select * from finish();
rollback;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `supabase test db`
Expected: `070_usernames_test.sql` FAILS — `generate_username` and the `username` column don't exist yet.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/000033_usernames.sql`:

```sql
-- Unique, editable usernames. profiles has no client write policy (owner
-- read-only), so writes happen here (trigger/backfill) and via definer RPCs
-- (migration 000034). Only lowercase is allowed, so uniqueness is naturally
-- case-insensitive without citext.

alter table public.profiles add column username text;

create unique index profiles_username_key on public.profiles (username);

alter table public.profiles add constraint profiles_username_format
  check (username ~ '^[a-z0-9_]{3,20}$' and username ~ '[a-z]');

-- Word-based handle, e.g. "swiftpanda42". Retries on collision; after 10 tries
-- it widens the numeric suffix so the result stays <= 20 chars and terminates.
create or replace function public.generate_username()
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  adjectives text[] := array[
    'swift','clever','brave','calm','bright','bold','cosmic','crimson','dapper','eager',
    'fuzzy','gentle','happy','jolly','keen','lucky','mellow','nimble','plucky','quiet',
    'rapid','shiny','sunny','tidy','vivid','witty','zesty','amber','breezy','curious'];
  nouns text[] := array[
    'panda','otter','fox','hawk','lion','koala','tiger','falcon','badger','beaver',
    'cheetah','dolphin','eagle','gecko','heron','ibis','jaguar','lynx','marmot','newt',
    'osprey','puffin','quokka','raven','seal','toucan','urchin','viper','walrus','yak'];
  base text;
  candidate text;
  tries int := 0;
begin
  loop
    tries := tries + 1;
    base := adjectives[1 + floor(random() * array_length(adjectives, 1))::int]
         || nouns[1 + floor(random() * array_length(nouns, 1))::int];
    if tries < 10 then
      candidate := base || (10 + floor(random() * 90))::int::text;      -- 2 digits
    else
      candidate := base || (1000 + floor(random() * 9000))::int::text;  -- 4 digits, len <= 18
    end if;
    exit when not exists (select 1 from public.profiles where username = candidate);
  end loop;
  return candidate;
end;
$$;

-- New users are named the moment they sign up. Idempotent insert preserved.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username)
    values (new.id, public.generate_username())
    on conflict (id) do nothing;
  return new;
end;
$$;

-- One-time backfill for existing accounts. Each call re-checks uniqueness
-- against rows already assigned in this same statement, so no collisions.
update public.profiles set username = public.generate_username()
  where username is null;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `supabase test db`
Expected: `070_usernames_test.sql` PASSES (8/8).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/000033_usernames.sql supabase/tests/070_usernames_test.sql
git commit -m "feat: add username column, generator, trigger, and backfill"
```

---

### Task 2: DB — availability + set-username RPCs

**Files:**
- Create: `supabase/migrations/000034_username_rpcs.sql`
- Create: `supabase/tests/071_username_rpcs_test.sql`

**Interfaces:**
- Consumes: `public.profiles.username`, `profiles_username_key`, `profiles_username_format` from Task 1.
- Produces:
  - `public.is_username_available(candidate text) returns boolean` — `false` for malformed input or a name taken by another user; `true` otherwise (a user's own current name counts as available).
  - `public.set_username(new_username text) returns text` — returns `'ok'`, `'taken'`, or `'invalid'`. Only mutates the caller's own row.
  - Both `SECURITY DEFINER`, granted to `authenticated` only.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/071_username_rpcs_test.sql`:

```sql
begin;
select plan(7);

-- two users; profiles auto-created by trigger with generated usernames
insert into auth.users (id, email) values
  ('b1111111-1111-1111-1111-111111111111', 'r1@test.dev'),
  ('b2222222-2222-2222-2222-222222222222', 'r2@test.dev');

-- give user B a known username to collide against
update public.profiles set username = 'usertwo1'
  where id = 'b2222222-2222-2222-2222-222222222222';

-- act as user A
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"b1111111-1111-1111-1111-111111111111","role":"authenticated"}';

-- availability
select is(public.is_username_available('freshname1'), true,
  'unused valid name is available');
select is(public.is_username_available('usertwo1'), false,
  'name taken by another user is unavailable');
select is(public.is_username_available('AB'), false,
  'malformed candidate is unavailable');

-- set_username happy path
select is(public.set_username('userone1'), 'ok', 'valid change returns ok');
select is(
  (select username from public.profiles
     where id = 'b1111111-1111-1111-1111-111111111111'),
  'userone1', 'username was updated for the caller');

-- set_username collision + invalid
select is(public.set_username('usertwo1'), 'taken',
  'name taken by another user returns taken');
select is(public.set_username('no'), 'invalid',
  'too-short name returns invalid');

select * from finish();
rollback;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `supabase test db`
Expected: `071_username_rpcs_test.sql` FAILS — the RPCs don't exist yet.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/000034_username_rpcs.sql`:

```sql
-- Client-facing username RPCs. profiles is owner-read-only with no client write
-- policy, so the app changes its username only through set_username, and can
-- only check availability of others' names through is_username_available.

create or replace function public.is_username_available(candidate text)
returns boolean
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if candidate !~ '^[a-z0-9_]{3,20}$' or candidate !~ '[a-z]' then
    return false;
  end if;
  return not exists (
    select 1 from public.profiles
      where username = candidate and id is distinct from v_uid
  );
end;
$$;

create or replace function public.set_username(new_username text)
returns text
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return 'invalid';
  end if;
  if new_username !~ '^[a-z0-9_]{3,20}$' or new_username !~ '[a-z]' then
    return 'invalid';
  end if;
  update public.profiles set username = new_username where id = v_uid;
  return 'ok';
exception
  when unique_violation then
    return 'taken';
end;
$$;

revoke all on function public.is_username_available(text) from public, anon;
revoke all on function public.set_username(text)          from public, anon;
grant execute on function public.is_username_available(text) to authenticated;
grant execute on function public.set_username(text)          to authenticated;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `supabase test db`
Expected: `071_username_rpcs_test.sql` PASSES (7/7). Also re-run confirms `070` still passes.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/000034_username_rpcs.sql supabase/tests/071_username_rpcs_test.sql
git commit -m "feat: add username availability and set-username RPCs"
```

---

### Task 3: Client — model, API, and state wiring

**Files:**
- Modify: `Avora/Models/Profile.swift`
- Modify: `Avora/Services/AvoraAPI.swift`
- Modify: `Avora/State/AppState.swift`
- Create: `Avora/Models/UsernameValidator.swift`

**Interfaces:**
- Consumes: `is_username_available(candidate text)`, `set_username(new_username text)` RPCs from Task 2.
- Produces:
  - `Profile.username: String?` (decoded from `profiles.username`).
  - `enum UsernameValidator { static func isValid(_:) -> Bool }` — mirrors the DB format rule.
  - `AvoraAPI.isUsernameAvailable(_:) async throws -> Bool`
  - `AvoraAPI.setUsername(_:) async throws -> SetUsernameResult` where `enum SetUsernameResult: String { case ok, taken, invalid }`.
  - `AppState.updateUsername(_:) async -> SetUsernameResult` — calls the RPC and, on `.ok`, updates `profile?.username` locally.

- [ ] **Step 1: Add `username` to the Profile model and its query**

In `Avora/Models/Profile.swift`, add the stored property and coding key:

```swift
struct Profile: Codable {
    let weeklyCredits: Int
    let extraCredits: Int
    let subscriptionActive: Bool
    let subscriptionPeriodEnd: Date?
    var signupBonusSeen: Bool
    var username: String?
    var totalCredits: Int { weeklyCredits + extraCredits }

    enum CodingKeys: String, CodingKey {
        case weeklyCredits = "weekly_credits"
        case extraCredits = "extra_credits"
        case subscriptionActive = "subscription_active"
        case subscriptionPeriodEnd = "subscription_period_end"
        case signupBonusSeen = "signup_bonus_seen"
        case username
    }
}
```

In `Avora/Services/AvoraAPI.swift`, add `username` to the `fetchProfile` select:

```swift
        return try await db.from("profiles")
            .select("weekly_credits,extra_credits,subscription_active,subscription_period_end,signup_bonus_seen,username")
            .eq("id", value: uid.uuidString)
            .single()
            .execute()
            .value
```

- [ ] **Step 2: Create the pure validator**

Create `Avora/Models/UsernameValidator.swift`:

```swift
import Foundation

/// Mirrors the database CHECK constraint (`^[a-z0-9_]{3,20}$` + at least one
/// letter) so the UI can give instant feedback. The server is authoritative.
enum UsernameValidator {
    static func isValid(_ username: String) -> Bool {
        let formatOK = username.range(
            of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil
        let hasLetter = username.range(
            of: "[a-z]", options: .regularExpression) != nil
        return formatOK && hasLetter
    }
}
```

- [ ] **Step 3: Add the RPC methods to AvoraAPI**

In `Avora/Services/AvoraAPI.swift`, add near `markSignupBonusSeen()`:

```swift
    enum SetUsernameResult: String, Decodable { case ok, taken, invalid }

    func isUsernameAvailable(_ candidate: String) async throws -> Bool {
        try await db.rpc("is_username_available", params: ["candidate": candidate])
            .execute()
            .value
    }

    func setUsername(_ newUsername: String) async throws -> SetUsernameResult {
        let raw: String = try await db.rpc(
            "set_username", params: ["new_username": newUsername])
            .execute()
            .value
        return SetUsernameResult(rawValue: raw) ?? .invalid
    }
```

- [ ] **Step 4: Wire the update into AppState**

In `Avora/State/AppState.swift`, add after `markSignupBonusSeen()`:

```swift
    /// Changes the username via the authoritative RPC. On success, updates the
    /// local profile so Settings reflects the new name without a refetch.
    func updateUsername(_ newUsername: String) async -> AvoraAPI.SetUsernameResult {
        let result = (try? await AvoraAPI.shared.setUsername(newUsername)) ?? .invalid
        if result == .ok {
            profile?.username = newUsername
        }
        return result
    }
```

- [ ] **Step 5: Build to verify it compiles**

Run the simulator build (XcodeBuildMCP `build_sim`, or `xcodebuild -scheme Avora -destination 'generic/platform=iOS Simulator' build`).
Expected: BUILD SUCCEEDED, no errors in the four changed/created files.

- [ ] **Step 6: Commit**

```bash
git add Avora/Models/Profile.swift Avora/Models/UsernameValidator.swift Avora/Services/AvoraAPI.swift Avora/State/AppState.swift
git commit -m "feat: add username to profile model, API, and app state"
```

---

### Task 4: Client — Settings display + edit sheet

**Files:**
- Create: `Avora/Views/Settings/EditUsernameSheet.swift`
- Modify: `Avora/Views/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `app.profile?.username`, `AvoraAPI.shared.isUsernameAvailable(_:)`, `app.updateUsername(_:)`, `UsernameValidator.isValid(_:)` from Task 3.
- Produces: an "Account → Username" row in Settings that presents `EditUsernameSheet`.

- [ ] **Step 1: Create the edit sheet**

Create `Avora/Views/Settings/EditUsernameSheet.swift`:

```swift
import SwiftUI

struct EditUsernameSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var status: Status = .idle
    @State private var checkTask: Task<Void, Never>?

    enum Status: Equatable {
        case idle, checking, available, taken, invalid, saving
    }

    init(current: String) {
        _text = State(initialValue: current)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("username", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: text) { _, _ in scheduleCheck() }
                } footer: {
                    footerLabel
                }
            }
            .navigationTitle("Username")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(status != .available)
                }
            }
        }
    }

    @ViewBuilder private var footerLabel: some View {
        switch status {
        case .idle:      Text("3–20 characters: lowercase letters, numbers, underscore.")
        case .checking:  Text("Checking availability…")
        case .available: Text("Available").foregroundStyle(.green)
        case .taken:     Text("That username is taken.").foregroundStyle(.red)
        case .invalid:   Text("Use 3–20 lowercase letters, numbers, or underscore (at least one letter).").foregroundStyle(.red)
        case .saving:    Text("Saving…")
        }
    }

    private func scheduleCheck() {
        checkTask?.cancel()
        let candidate = text
        if candidate == (app.profile?.username ?? "") {
            status = .idle
            return
        }
        guard UsernameValidator.isValid(candidate) else {
            status = .invalid
            return
        }
        status = .checking
        checkTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            let available = (try? await AvoraAPI.shared.isUsernameAvailable(candidate)) ?? false
            if Task.isCancelled || candidate != text { return }
            status = available ? .available : .taken
        }
    }

    private func save() {
        status = .saving
        Task {
            let result = await app.updateUsername(text)
            switch result {
            case .ok:      dismiss()
            case .taken:   status = .taken
            case .invalid: status = .invalid
            }
        }
    }
}
```

- [ ] **Step 2: Add the Username row to Settings**

In `Avora/Views/Settings/SettingsView.swift`, add sheet state and a row inside the existing `Account` section. Replace the `Account` section block with:

```swift
            Section("Account") {
                if let username = app.profile?.username {
                    Button {
                        editingUsername = true
                    } label: {
                        LabeledContent("Username", value: username)
                    }
                    .tint(.primary)
                }
                if let email = app.userEmail {
                    LabeledContent("Email", value: email)
                }
            }
```

Add the state property near the other `@State`s:

```swift
    @State private var editingUsername = false
```

Add the sheet modifier alongside the existing `.alert`/`.confirmationDialog` modifiers on the `List`:

```swift
        .sheet(isPresented: $editingUsername) {
            EditUsernameSheet(current: app.profile?.username ?? "")
        }
```

- [ ] **Step 3: Build to verify it compiles**

Run the simulator build (XcodeBuildMCP `build_sim` or `xcodebuild ... build`).
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual verification**

Run the app in the simulator against the local/staging backend, then:
1. Open Settings → confirm the current username shows under Account.
2. Tap it → the edit sheet opens with the current name.
3. Type an invalid name (e.g. `AB`) → footer shows the invalid message, Save disabled.
4. Type a valid, unused name → "Available" appears, Save enabled.
5. Save → sheet dismisses, Settings shows the new username.
6. Reopen and try a name already taken by another account → "taken", Save stays disabled/errors.

- [ ] **Step 5: Commit**

```bash
git add Avora/Views/Settings/EditUsernameSheet.swift Avora/Views/Settings/SettingsView.swift
git commit -m "feat: username display and edit sheet in Settings"
```

---

## Self-Review Notes

- **Spec coverage:** data model (Task 1), auto-generation + trigger (Task 1), backfill (Task 1), both RPCs (Task 2), client read + edit + live availability (Tasks 3–4), DB tests (Tasks 1–2). Client testing is build + manual because the repo has no iOS test target — noted in Global Constraints.
- **Format rule** is identical across the DB CHECK, both RPCs, and `UsernameValidator`.
- **Generator length** is bounded ≤ 18 chars (max base 14 + 4 digits), always within the 20-char CHECK, so `generate_username()` can never produce a value the constraint rejects.
- **Type consistency:** `SetUsernameResult` (`ok`/`taken`/`invalid`) is defined in Task 3 and consumed in Task 4; `Profile.username` and `updateUsername(_:)` names match across tasks.
