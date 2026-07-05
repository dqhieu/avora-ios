# Community Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Community tab where users browse a 2-column grid of publicly shared creations, sort by Latest or Most liked, like creations, and reuse their style/prompt — with sharing toggled from a user's own Collection.

**Architecture:** A security-definer Postgres view (`community_feed`) crosses the owner-only RLS on `generations` to expose shared rows; a single added storage RLS policy lets any authenticated user mint signed URLs for shared outputs (no image duplication); definer RPCs handle share/unshare/like/unlike. The iOS client adds a third tab mirroring the existing Collection grid, reading from the view and calling the RPCs.

**Tech Stack:** Supabase (Postgres + pgTAP tests via `supabase test db`, storage RLS), SwiftUI (iOS 17+, `@Observable` AppState, supabase-swift), Xcode target `Avora`.

## Global Constraints

- **Migrations are additive and sequentially numbered.** Next free numbers: `000035`, `000036`, `000037`. Never edit an already-shipped migration.
- **`generations` and `profiles` have no client write policy** — all writes go through `security definer` RPCs with `set search_path = public`. Preserve this: no new client-facing table write policy on `generations`.
- **RPCs follow the repo pattern**: `security definer set search_path = public`, then `revoke all ... from public, anon` and `grant execute ... to authenticated`.
- **pgTAP tests** live in `supabase/tests/NNN_name_test.sql`, wrapped in `begin; select plan(N); ... select * from finish(); rollback;`. Set role via `set local role authenticated;` + `set local request.jwt.claims = '{"sub":"<uuid>","role":"authenticated"}';`. Run all tests with `supabase test db`.
- **No Swift test target exists.** Client tasks are verified by a successful build (`XcodeBuildMCP build_sim` on scheme `Avora`, or `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' build`) plus the described manual simulator check. Do not add an XCTest target.
- **Community images live in the private `outputs` bucket** and load via `RemoteImage(path:, source: .output)` (the default), which resolves short-lived signed URLs. Do not copy images to a public bucket.
- **Style vs. custom XOR**: a generation has either `style_id` (preset) or `custom_prompt` (custom), never both. Client models must treat both as optional.
- **No plan/phase references in code comments, migration filenames, or test names** — explain the *why*, not the origin.

---

### Task 1: Community schema migration (likes, columns, indexes, storage policy)

Creates the `likes` table, adds `shared_at` + `like_count` to `generations`, indexes for both sort orders, RLS for `likes`, and the storage policy that makes shared outputs readable by any authenticated user.

**Files:**
- Create: `supabase/migrations/000035_community.sql`
- Create: `supabase/tests/080_community_schema_test.sql`

**Interfaces:**
- Produces (relied on by Tasks 2, 3, 4, 7):
  - Table `public.likes(user_id uuid, generation_id uuid, created_at timestamptz, primary key(user_id, generation_id))`.
  - Columns `public.generations.shared_at timestamptz` (null = not shared) and `public.generations.like_count int not null default 0`.
  - Storage policy `outputs_read_shared` on `storage.objects`.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/000035_community.sql`:

```sql
-- Community feature storage layer. Likes are keyed to the generation and are
-- independent of share state, so they survive unshare/re-share. like_count is a
-- denormalized counter maintained by the like/unlike RPCs so "most liked" can be
-- indexed and sorted without a per-row aggregate. shared_at null means the
-- creation is private; a timestamp means it is in the community feed.

create table public.likes (
  user_id       uuid not null references auth.users(id) on delete cascade,
  generation_id uuid not null references public.generations(id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (user_id, generation_id)
);

alter table public.generations add column shared_at  timestamptz;
alter table public.generations add column like_count int not null default 0;

create index generations_shared_at_idx
  on public.generations (shared_at desc) where shared_at is not null;
create index generations_like_count_idx
  on public.generations (like_count desc, shared_at desc) where shared_at is not null;
create index likes_generation_idx on public.likes (generation_id);

-- likes: a user reads and manages only their own like rows. (The like/unlike
-- RPCs run as definer and keep like_count consistent; these policies let the
-- client read its own liked state directly if ever needed and enforce ownership.)
alter table public.likes enable row level security;

create policy likes_select_own on public.likes
  for select to authenticated using (user_id = auth.uid());
create policy likes_insert_own on public.likes
  for insert to authenticated with check (user_id = auth.uid());
create policy likes_delete_own on public.likes
  for delete to authenticated using (user_id = auth.uid());

-- Image visibility: the outputs bucket is private (owner-only reads via
-- outputs_read_own). This second policy lets ANY authenticated user mint a
-- signed URL for an output whose generation is currently shared. Unshare
-- (shared_at -> null) immediately revokes the ability to mint new URLs.
create policy outputs_read_shared on storage.objects
  for select to authenticated
  using (
    bucket_id = 'outputs'
    and exists (
      select 1 from public.generations g
      where g.output_path = name and g.shared_at is not null
    )
  );
```

- [ ] **Step 2: Write the failing test**

Create `supabase/tests/080_community_schema_test.sql`:

```sql
begin;
select plan(5);

-- Schema existence — checked as the privileged role, so no RLS/grant is involved.
select has_table('public','likes','likes table exists');
select has_column('public','generations','shared_at','generations has shared_at');
select has_column('public','generations','like_count','generations has like_count');

-- Storage policy: a non-owner can read a SHARED output but not a private one.
-- NOTE: this reads storage.objects under the authenticated role. If it errors
-- with "permission denied" in the LOCAL shadow db, that is the same missing-
-- baseline-grant gap that makes 020_rls_test fail locally — it passes against the
-- deployed DB / CI. Do NOT "fix" it by granting; verify remotely.
insert into auth.users (id, email) values
  ('c1111111-1111-1111-1111-111111111111', 'c1@test.dev'),
  ('c2222222-2222-2222-2222-222222222222', 'c2@test.dev');
insert into public.styles (id, name, prompt_template) values ('cs1','Style 1','SECRET');
insert into public.generations
  (id, user_id, style_id, charged_bucket, charged_amount, input_path, quality,
   output_path, status, shared_at)
values
  ('caaaaaaa-0000-0000-0000-000000000001',
   'c1111111-1111-1111-1111-111111111111','cs1','extra',25,'in/a.png','medium',
   'c1111111-1111-1111-1111-111111111111/shared.png','completed', now()),
  ('caaaaaaa-0000-0000-0000-000000000002',
   'c1111111-1111-1111-1111-111111111111','cs1','extra',25,'in/b.png','medium',
   'c1111111-1111-1111-1111-111111111111/private.png','completed', null);
insert into storage.objects (bucket_id, name, owner) values
  ('outputs','c1111111-1111-1111-1111-111111111111/shared.png',
   'c1111111-1111-1111-1111-111111111111'),
  ('outputs','c1111111-1111-1111-1111-111111111111/private.png',
   'c1111111-1111-1111-1111-111111111111');

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"c2222222-2222-2222-2222-222222222222","role":"authenticated"}';

select is(
  (select count(*)::int from storage.objects
     where name = 'c1111111-1111-1111-1111-111111111111/shared.png'),
  1, 'non-owner can read a shared output object');

select is(
  (select count(*)::int from storage.objects
     where name = 'c1111111-1111-1111-1111-111111111111/private.png'),
  0, 'non-owner cannot read a private (unshared) output object');

select * from finish();
rollback;
```

The likes-RLS ownership behavior (self-only reads, can't insert another user's like) is exercised via the definer RPCs in Task 3's test instead, which is robust against the local grant gap. Here we only assert the table/columns exist plus the storage policy.

- [ ] **Step 3: Run the test to verify it fails**

Run: `supabase test db`
Expected: `080_community_schema_test` fails — the migration is not written yet, so `likes`, `shared_at`, `like_count`, and `outputs_read_shared` don't exist (errors like `relation "public.likes" does not exist`).

- [ ] **Step 4: Confirm the migration file from Step 1 is in place, then re-run**

Run: `supabase test db`
Expected: all 5 assertions in `080_community_schema_test` PASS (existing test files still pass too).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/000035_community.sql supabase/tests/080_community_schema_test.sql
git commit -m "feat: community schema — likes table, share/like columns, storage policy"
```

---

### Task 2: Community feed view + share/unshare RPCs

Exposes shared creations (with author username, like count, and per-caller liked state) through a definer view, and adds owner-checked share/unshare RPCs.

**Files:**
- Create: `supabase/migrations/000036_community_feed.sql`
- Create: `supabase/tests/081_community_feed_test.sql`

**Interfaces:**
- Consumes (from Task 1): `public.likes`, `generations.shared_at`, `generations.like_count`.
- Produces (relied on by Task 4):
  - View `public.community_feed(id uuid, output_path text, style_id text, custom_prompt text, like_count int, shared_at timestamptz, username text, liked_by_me boolean)` — only rows where `shared_at is not null`.
  - `public.share_creation(gen_id uuid) returns void`.
  - `public.unshare_creation(gen_id uuid) returns void`.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/000036_community_feed.sql`:

```sql
-- The community feed. generations is owner-read-only under RLS, so a plain
-- (security_invoker) view could not return other users' rows. This definer view
-- runs with owner privileges to cross that RLS, but exposes ONLY shared rows and
-- ONLY safe columns (incl. custom_prompt, which becomes public on share, per the
-- reuse decision, and the author's username). auth.uid() still resolves to the
-- caller inside a definer view, so liked_by_me is correct per-user.

create view public.community_feed with (security_invoker = false) as
  select g.id,
         g.output_path,
         g.style_id,
         g.custom_prompt,
         g.like_count,
         g.shared_at,
         p.username,
         exists (
           select 1 from public.likes l
           where l.generation_id = g.id and l.user_id = auth.uid()
         ) as liked_by_me
  from public.generations g
  join public.profiles p on p.id = g.user_id
  where g.shared_at is not null;

revoke all on public.community_feed from public, anon;
grant select on public.community_feed to authenticated;

-- Share / unshare toggle. Owner-checked; sets or clears shared_at. Keeps the
-- "no client writes to generations" invariant. like_count is left untouched, so
-- likes persist across unshare and are restored on re-share.
create or replace function public.share_creation(gen_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.generations
    set shared_at = now()
    where id = gen_id and user_id = auth.uid();
end;
$$;

create or replace function public.unshare_creation(gen_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update public.generations
    set shared_at = null
    where id = gen_id and user_id = auth.uid();
end;
$$;

revoke all on function public.share_creation(uuid)   from public, anon;
revoke all on function public.unshare_creation(uuid) from public, anon;
grant execute on function public.share_creation(uuid)   to authenticated;
grant execute on function public.unshare_creation(uuid) to authenticated;
```

- [ ] **Step 2: Write the failing test**

Create `supabase/tests/081_community_feed_test.sql`:

```sql
begin;
select plan(7);

insert into auth.users (id, email) values
  ('d1111111-1111-1111-1111-111111111111', 'd1@test.dev'),
  ('d2222222-2222-2222-2222-222222222222', 'd2@test.dev');
insert into public.styles (id, name, prompt_template) values ('ds1','Style 1','SECRET');
update public.profiles set username = 'authorone'
  where id = 'd1111111-1111-1111-1111-111111111111';

-- user A: one shared, one private generation
insert into public.generations
  (id, user_id, style_id, charged_bucket, charged_amount, input_path, quality,
   output_path, status, shared_at, like_count)
values
  ('daaaaaaa-0000-0000-0000-000000000001',
   'd1111111-1111-1111-1111-111111111111','ds1','extra',25,'in/a.png','medium',
   'out/a.png','completed', now(), 3),
  ('daaaaaaa-0000-0000-0000-000000000002',
   'd1111111-1111-1111-1111-111111111111','ds1','extra',25,'in/b.png','medium',
   'out/b.png','completed', null, 0);

-- user B likes A's shared creation (seed via privileged role)
insert into public.likes (user_id, generation_id) values
  ('d2222222-2222-2222-2222-222222222222','daaaaaaa-0000-0000-0000-000000000001');

-- act as user B. Feed reads go through the definer view, which is explicitly
-- granted to authenticated and reads its base tables as the view owner, so it is
-- robust against the local baseline-grant gap. Verification reads on generations
-- use `reset role` (privileged), following the 071_username_rpcs_test pattern.
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"d2222222-2222-2222-2222-222222222222","role":"authenticated"}';

select is(
  (select count(*)::int from public.community_feed), 1,
  'feed shows only shared rows');
select is(
  (select username from public.community_feed
     where id = 'daaaaaaa-0000-0000-0000-000000000001'),
  'authorone', 'feed exposes the author username');
select is(
  (select liked_by_me from public.community_feed
     where id = 'daaaaaaa-0000-0000-0000-000000000001'),
  true, 'liked_by_me is true for a creation user B liked');

-- user B cannot share a creation they do not own (no-op update)
select public.share_creation('daaaaaaa-0000-0000-0000-000000000002');
reset role;
select is(
  (select shared_at from public.generations
     where id = 'daaaaaaa-0000-0000-0000-000000000002'),
  null, 'share_creation is a no-op for a non-owner');

-- owner shares that creation
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"d1111111-1111-1111-1111-111111111111","role":"authenticated"}';
select public.share_creation('daaaaaaa-0000-0000-0000-000000000002');
reset role;
select isnt(
  (select shared_at from public.generations
     where id = 'daaaaaaa-0000-0000-0000-000000000002'),
  null, 'owner can share their own creation');

-- owner unshares the first creation; likes are preserved
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"d1111111-1111-1111-1111-111111111111","role":"authenticated"}';
select public.unshare_creation('daaaaaaa-0000-0000-0000-000000000001');
reset role;
select is(
  (select shared_at from public.generations
     where id = 'daaaaaaa-0000-0000-0000-000000000001'),
  null, 'owner can unshare their own creation');
select is(
  (select like_count from public.generations
     where id = 'daaaaaaa-0000-0000-0000-000000000001'),
  3, 'unshare preserves like_count');

select * from finish();
rollback;
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `supabase test db`
Expected: `081_community_feed_test` fails — `community_feed`, `share_creation`, `unshare_creation` do not exist yet.

- [ ] **Step 4: Confirm the migration from Step 1 is in place, then re-run**

Run: `supabase test db`
Expected: all 7 assertions PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/000036_community_feed.sql supabase/tests/081_community_feed_test.sql
git commit -m "feat: community_feed view and share/unshare RPCs"
```

---

### Task 3: Like / unlike RPCs

Adds the toggle RPCs that maintain `like_count` atomically and are idempotent.

**Files:**
- Create: `supabase/migrations/000037_community_likes_rpcs.sql`
- Create: `supabase/tests/082_community_likes_test.sql`

**Interfaces:**
- Consumes (from Tasks 1–2): `public.likes`, `generations.like_count`, `share_creation`, `unshare_creation`.
- Produces (relied on by Task 4):
  - `public.like_creation(gen_id uuid) returns int` — inserts a like if absent, returns the new `like_count`.
  - `public.unlike_creation(gen_id uuid) returns int` — removes the like if present, returns the new `like_count` (floored at 0).

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/000037_community_likes_rpcs.sql`:

```sql
-- Like / unlike toggle. Definer so the client never writes like_count directly.
-- The likes primary key makes a duplicate like a no-op (on conflict do nothing),
-- and FOUND tells us whether the row actually changed, so like_count only moves
-- when the caller's like state actually flips. Returns the resulting count so the
-- client can reconcile its optimistic update with the truth.

create or replace function public.like_creation(gen_id uuid)
returns int
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_count int;
begin
  insert into public.likes (user_id, generation_id)
    values (v_uid, gen_id)
    on conflict (user_id, generation_id) do nothing;

  if found then
    update public.generations
      set like_count = like_count + 1
      where id = gen_id
      returning like_count into v_count;
  else
    select like_count into v_count from public.generations where id = gen_id;
  end if;

  return coalesce(v_count, 0);
end;
$$;

create or replace function public.unlike_creation(gen_id uuid)
returns int
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_count int;
begin
  delete from public.likes
    where user_id = v_uid and generation_id = gen_id;

  if found then
    update public.generations
      set like_count = greatest(like_count - 1, 0)
      where id = gen_id
      returning like_count into v_count;
  else
    select like_count into v_count from public.generations where id = gen_id;
  end if;

  return coalesce(v_count, 0);
end;
$$;

revoke all on function public.like_creation(uuid)   from public, anon;
revoke all on function public.unlike_creation(uuid) from public, anon;
grant execute on function public.like_creation(uuid)   to authenticated;
grant execute on function public.unlike_creation(uuid) to authenticated;
```

- [ ] **Step 2: Write the failing test**

Create `supabase/tests/082_community_likes_test.sql`:

```sql
begin;
select plan(7);

insert into auth.users (id, email) values
  ('e1111111-1111-1111-1111-111111111111', 'e1@test.dev'),
  ('e2222222-2222-2222-2222-222222222222', 'e2@test.dev');
insert into public.styles (id, name, prompt_template) values ('es1','Style 1','SECRET');

-- user A owns a shared creation with 0 likes
insert into public.generations
  (id, user_id, style_id, charged_bucket, charged_amount, input_path, quality,
   output_path, status, shared_at, like_count)
values
  ('eaaaaaaa-0000-0000-0000-000000000001',
   'e1111111-1111-1111-1111-111111111111','es1','extra',25,'in/a.png','medium',
   'out/a.png','completed', now(), 0);

-- act as user B. RPCs are definer and return the resulting count, so those
-- assertions are robust. Table verification reads use `reset role` (privileged),
-- following the 071_username_rpcs_test pattern, to avoid the local grant gap.
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"e2222222-2222-2222-2222-222222222222","role":"authenticated"}';

select is(public.like_creation('eaaaaaaa-0000-0000-0000-000000000001'), 1,
  'first like returns count 1');
select is(public.like_creation('eaaaaaaa-0000-0000-0000-000000000001'), 1,
  'liking again is idempotent — count stays 1');

reset role;
select is(
  (select count(*)::int from public.likes
     where generation_id = 'eaaaaaaa-0000-0000-0000-000000000001'
       and user_id = 'e2222222-2222-2222-2222-222222222222'),
  1, 'exactly one like row exists for the user');

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"e2222222-2222-2222-2222-222222222222","role":"authenticated"}';
select is(public.unlike_creation('eaaaaaaa-0000-0000-0000-000000000001'), 0,
  'unlike returns count 0');
select is(public.unlike_creation('eaaaaaaa-0000-0000-0000-000000000001'), 0,
  'unliking again is idempotent and floored at 0');

-- likes persist across unshare/re-share: like (B), unshare + re-share (A)
select public.like_creation('eaaaaaaa-0000-0000-0000-000000000001');
set local request.jwt.claims =
  '{"sub":"e1111111-1111-1111-1111-111111111111","role":"authenticated"}';
select public.unshare_creation('eaaaaaaa-0000-0000-0000-000000000001');
select public.share_creation('eaaaaaaa-0000-0000-0000-000000000001');
reset role;
select is(
  (select like_count from public.generations
     where id = 'eaaaaaaa-0000-0000-0000-000000000001'),
  1, 'like_count survives unshare then re-share');
select is(
  (select count(*)::int from public.likes
     where generation_id = 'eaaaaaaa-0000-0000-0000-000000000001'),
  1, 'like row survives unshare then re-share');

select * from finish();
rollback;
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `supabase test db`
Expected: `082_community_likes_test` fails — `like_creation` / `unlike_creation` do not exist yet.

- [ ] **Step 4: Confirm the migration from Step 1 is in place, then re-run**

Run: `supabase test db`
Expected: all 7 assertions PASS. Run the full suite once more to confirm no regressions across `010`–`082`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/000037_community_likes_rpcs.sql supabase/tests/082_community_likes_test.sql
git commit -m "feat: like/unlike RPCs with idempotent like_count"
```

---

### Task 4: Client data layer — CommunityItem model + API methods + Generation.sharedAt

Adds the Swift model for a feed row, the API methods that read the feed and call the four RPCs, the community snapshot cache, and `shared_at` on `Generation` (needed for the Collection "Shared" badge in Task 7).

**Files:**
- Create: `Avora/Models/CommunityItem.swift`
- Modify: `Avora/Models/Generation.swift`
- Modify: `Avora/Services/AvoraAPI.swift`
- Modify: `Avora/Services/SnapshotStore.swift`

**Interfaces:**
- Consumes (from Tasks 1–3): view `community_feed`, RPCs `share_creation`, `unshare_creation`, `like_creation`, `unlike_creation`.
- Produces (relied on by Tasks 5, 6, 7):
  - `enum CommunitySort: String { case latest, mostLiked }`
  - `struct CommunityItem: Codable, Identifiable, Hashable` with fields `id: UUID, outputPath: String?, styleId: String?, customPrompt: String?, likeCount: Int, username: String?, likedByMe: Bool`.
  - `AvoraAPI.communityLatest(before: Date?) async throws -> (items: [CommunityItem], next: Date?)`
  - `AvoraAPI.communityMostLiked(offset: Int) async throws -> (items: [CommunityItem], next: Int?)`
  - `AvoraAPI.shareCreation(_ id: UUID) async throws`, `unshareCreation(_ id: UUID) async throws`
  - `AvoraAPI.likeCreation(_ id: UUID) async throws -> Int`, `unlikeCreation(_ id: UUID) async throws -> Int`
  - `Generation.sharedAt: Date?`
  - `SnapshotStore.loadCommunity(_:) / saveCommunity(_:_:)` keyed by sort.

- [ ] **Step 1: Create the CommunityItem model**

Create `Avora/Models/CommunityItem.swift`:

```swift
import Foundation

/// How the community feed is ordered. `latest` paginates by `shared_at` (keyset);
/// `mostLiked` paginates by offset because the like count is mutable.
enum CommunitySort: String, CaseIterable, Hashable {
    case latest
    case mostLiked

    var label: String {
        switch self {
        case .latest: return "Latest"
        case .mostLiked: return "Most liked"
        }
    }
}

/// One row of the `community_feed` view: a publicly shared creation with its
/// author, like count, and whether the current user has liked it. A creation is
/// either style-based (`styleId`) or custom (`customPrompt`), never both.
struct CommunityItem: Codable, Identifiable, Hashable {
    let id: UUID
    let outputPath: String?
    let styleId: String?
    let customPrompt: String?
    var likeCount: Int
    let username: String?
    var likedByMe: Bool
    var sharedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, username
        case outputPath = "output_path"
        case styleId = "style_id"
        case customPrompt = "custom_prompt"
        case likeCount = "like_count"
        case likedByMe = "liked_by_me"
        case sharedAt = "shared_at"
    }
}
```

- [ ] **Step 2: Add `sharedAt` to Generation**

In `Avora/Models/Generation.swift`, add the field and coding key (leave everything else untouched):

```swift
struct Generation: Codable, Identifiable, Hashable {
    let id: UUID
    let styleId: String?
    let customPrompt: String?
    let status: GenStatus
    let outputPath: String?
    let createdAt: Date?
    let sharedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case styleId = "style_id"
        case customPrompt = "custom_prompt"
        case outputPath = "output_path"
        case createdAt = "created_at"
        case sharedAt = "shared_at"
    }
}
```

- [ ] **Step 3: Select `shared_at` in `listGenerations`**

In `Avora/Services/AvoraAPI.swift`, update the `listGenerations` select string to include `shared_at`:

```swift
        let baseQuery = db.from("generations")
            .select("id,style_id,custom_prompt,status,output_path,created_at,shared_at")
```

- [ ] **Step 4: Add the community API methods**

In `Avora/Services/AvoraAPI.swift`, add these methods inside `struct AvoraAPI` (after `listGenerations`):

```swift
    private static let communityPageSize = 20

    func communityLatest(before cursor: Date?) async throws
        -> (items: [CommunityItem], next: Date?) {
        let base = db.from("community_feed")
            .select("id,output_path,style_id,custom_prompt,like_count,username,liked_by_me,shared_at")
        let filtered = cursor.map { c in
            base.lt("shared_at", value: AvoraAPI.iso8601.string(from: c))
        } ?? base
        let all: [CommunityItem] = try await filtered
            .order("shared_at", ascending: false)
            .limit(AvoraAPI.communityPageSize + 1)
            .execute()
            .value
        let items = Array(all.prefix(AvoraAPI.communityPageSize))
        let next = all.count > AvoraAPI.communityPageSize ? items.last?.sharedAt : nil
        return (items, next)
    }

    func communityMostLiked(offset: Int) async throws
        -> (items: [CommunityItem], next: Int?) {
        let size = AvoraAPI.communityPageSize
        let all: [CommunityItem] = try await db.from("community_feed")
            .select("id,output_path,style_id,custom_prompt,like_count,username,liked_by_me,shared_at")
            .order("like_count", ascending: false)
            .order("shared_at", ascending: false)
            .range(from: offset, to: offset + size)   // inclusive; fetches size+1
            .execute()
            .value
        let items = Array(all.prefix(size))
        let next = all.count > size ? offset + size : nil
        return (items, next)
    }

    func shareCreation(_ id: UUID) async throws {
        try await db.rpc("share_creation", params: ["gen_id": id.uuidString]).execute()
    }

    func unshareCreation(_ id: UUID) async throws {
        try await db.rpc("unshare_creation", params: ["gen_id": id.uuidString]).execute()
    }

    func likeCreation(_ id: UUID) async throws -> Int {
        try await db.rpc("like_creation", params: ["gen_id": id.uuidString])
            .execute().value
    }

    func unlikeCreation(_ id: UUID) async throws -> Int {
        try await db.rpc("unlike_creation", params: ["gen_id": id.uuidString])
            .execute().value
    }
```

- [ ] **Step 5: Add a community snapshot to SnapshotStore**

In `Avora/Services/SnapshotStore.swift`, add snapshot support keyed by sort (mirrors the collection snapshot). Add after the `collectionURL` definitions:

```swift
    private static func communityURL(_ sort: CommunitySort) -> URL {
        directory.appendingPathComponent("community-\(sort.rawValue).json")
    }

    static func loadCommunity(_ sort: CommunitySort) -> [CommunityItem]? {
        load([CommunityItem].self, from: communityURL(sort))
    }
    static func saveCommunity(_ sort: CommunitySort, _ items: [CommunityItem]) {
        save(items, to: communityURL(sort))
    }
    static func clearCommunity() {
        for sort in CommunitySort.allCases {
            try? FileManager.default.removeItem(at: communityURL(sort))
        }
    }
```

Then, in `AppState.signOut()` (`Avora/State/AppState.swift`), add `SnapshotStore.clearCommunity()` next to the existing `SnapshotStore.clearCollection()` so a signed-out user's feed cache is dropped.

- [ ] **Step 6: Build to verify it compiles**

Run: `XcodeBuildMCP build_sim` (scheme `Avora`) — or
`xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Avora/Models/CommunityItem.swift Avora/Models/Generation.swift \
        Avora/Services/AvoraAPI.swift Avora/Services/SnapshotStore.swift \
        Avora/State/AppState.swift
git commit -m "feat: community data layer — model, API methods, snapshot"
```

---

### Task 5: Community tab, feed view, card, and sort control

Adds the third tab and the `CommunityView` grid (mirroring `CollectionView`) with the `Latest`/`Most liked` sort control and the `CommunityCard` tile.

**Files:**
- Modify: `Avora/RootTabView.swift`
- Create: `Avora/Views/Community/CommunityView.swift`
- Create: `Avora/Views/Community/CommunityCard.swift`

**Interfaces:**
- Consumes (from Task 4): `CommunityItem`, `CommunitySort`, `AvoraAPI.communityLatest/communityMostLiked`, `SnapshotStore.loadCommunity/saveCommunity`.
- Produces (relied on by Task 6): navigation value `CommunityItem` handled by a `navigationDestination` (the destination view itself is added in Task 6); `CommunityCard(item:onToggleLike:)`.

- [ ] **Step 1: Add the Community tab to RootTabView**

In `Avora/RootTabView.swift`, add the tab between the two existing ones and a matching `CommunityTab`:

```swift
struct RootTabView: View {
    var body: some View {
        TabView {
            StylesTab()
                .tabItem { Label("Create", systemImage: "wand.and.stars") }
            CommunityTab()
                .tabItem { Label("Community", systemImage: "person.2") }
            CollectionTab()
                .tabItem { Label("Collection", systemImage: "square.grid.2x2") }
        }
    }
}

private struct CommunityTab: View {
    @State private var path = NavigationPath()
    var body: some View {
        NavigationStack(path: $path) { CommunityView() }
            .toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
    }
}
```

(Leave `StylesTab` and `CollectionTab` unchanged.)

- [ ] **Step 2: Create CommunityCard**

Create `Avora/Views/Community/CommunityCard.swift`:

```swift
import SwiftUI

/// A single community feed tile: the shared image with a caption row showing the
/// author's username and a tappable like affordance. Liking is optimistic — the
/// parent flips `likedByMe`/`likeCount` immediately and reverts on failure.
struct CommunityCard: View {
    let item: CommunityItem
    let onToggleLike: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            tile
            HStack {
                Text(item.username.map { "@\($0)" } ?? "@unknown")
                    .font(.avoraSubheadline)
                    .foregroundStyle(Color.avoraTextSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                likeButton
            }
            .padding(.horizontal, 2)
        }
        .padding(.bottom, Spacing.xs)
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(Color.avoraSurface)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let path = item.outputPath {
                    RemoteImage(path: path, contentMode: .fill)
                }
            }
            .clipShape(.rect(cornerRadius: Radius.md, style: .continuous))
    }

    private var likeButton: some View {
        Button(action: onToggleLike) {
            HStack(spacing: 3) {
                Image(systemName: item.likedByMe ? "heart.fill" : "heart")
                    .foregroundStyle(item.likedByMe ? Color.avoraAccent : Color.avoraTextSecondary)
                Text("\(item.likeCount)")
                    .font(.avoraSubheadline)
                    .foregroundStyle(Color.avoraTextSecondary)
                    .contentTransition(.numericText())
            }
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: Create CommunityView**

Create `Avora/Views/Community/CommunityView.swift`:

```swift
import SwiftUI

struct CommunityView: View {
    @Environment(AppState.self) private var app
    @State private var items: [CommunityItem] = []
    @State private var sort: CommunitySort = .latest
    @State private var nextCursor: Date?      // latest
    @State private var nextOffset: Int?       // most liked
    @State private var loading = false
    @State private var reloadToken = 0
    @State private var hasLoaded = false
    private let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: Spacing.sm) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        CommunityCard(item: item) { toggleLike(item) }
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if item.id == items.last?.id { Task { await loadMore() } }
                    }
                }
            }
            .padding(Spacing.sm)
        }
        .navigationTitle("Community")
        .navigationDestination(for: CommunityItem.self) { CommunityDetailView(item: $0) }
        .navigationDestination(for: CreateRoute.self) { CreateView(route: $0) }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Sort", selection: $sort) {
                    ForEach(CommunitySort.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .overlay {
            if items.isEmpty && hasLoaded {
                ContentUnavailableView(
                    "No creations shared yet",
                    systemImage: "person.2",
                    description: Text("Shared creations from the community will appear here.")
                )
            }
        }
        .task(id: sort) {
            items = SnapshotStore.loadCommunity(sort) ?? []
            await refresh()
            hasLoaded = true
        }
        .refreshable { await refresh() }
    }

    private func toggleLike(_ item: CommunityItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let wasLiked = items[idx].likedByMe
        // optimistic flip
        items[idx].likedByMe.toggle()
        items[idx].likeCount += wasLiked ? -1 : 1
        let id = item.id
        Task {
            do {
                let count = wasLiked
                    ? try await AvoraAPI.shared.unlikeCreation(id)
                    : try await AvoraAPI.shared.likeCreation(id)
                if let i = items.firstIndex(where: { $0.id == id }) {
                    items[i].likeCount = count
                }
            } catch {
                if let i = items.firstIndex(where: { $0.id == id }) {
                    items[i].likedByMe = wasLiked
                    items[i].likeCount += wasLiked ? 1 : -1
                }
            }
        }
    }

    private func refresh() async {
        reloadToken += 1
        let token = reloadToken
        do {
            switch sort {
            case .latest:
                let (page, next) = try await AvoraAPI.shared.communityLatest(before: nil)
                guard token == reloadToken else { return }
                items = page
                nextCursor = next
                nextOffset = nil
            case .mostLiked:
                let (page, next) = try await AvoraAPI.shared.communityMostLiked(offset: 0)
                guard token == reloadToken else { return }
                items = page
                nextOffset = next
                nextCursor = nil
            }
            SnapshotStore.saveCommunity(sort, items)
        } catch {
            // keep whatever is on screen (snapshot or prior page)
        }
    }

    private func loadMore() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let token = reloadToken
        do {
            let page: [CommunityItem]
            switch sort {
            case .latest:
                guard let cursor = nextCursor else { return }
                let (p, next) = try await AvoraAPI.shared.communityLatest(before: cursor)
                guard token == reloadToken else { return }
                page = p; nextCursor = next
            case .mostLiked:
                guard let offset = nextOffset else { return }
                let (p, next) = try await AvoraAPI.shared.communityMostLiked(offset: offset)
                guard token == reloadToken else { return }
                page = p; nextOffset = next
            }
            let seen = Set(items.map(\.id))
            items += page.filter { !seen.contains($0.id) }
        } catch { }
    }
}
```

- [ ] **Step 4: Build to verify it compiles**

Run: `XcodeBuildMCP build_sim` (scheme `Avora`).
Expected: BUILD SUCCEEDED. (`CommunityDetailView` is referenced but not yet defined — **if the build fails only on that symbol**, temporarily comment out the `.navigationDestination(for: CommunityItem.self)` line, verify the rest builds, and restore it in Task 6. Prefer to implement Task 6 next so the reference resolves.)

- [ ] **Step 5: Commit**

```bash
git add Avora/RootTabView.swift Avora/Views/Community/
git commit -m "feat: community tab, feed grid, card, and sort control"
```

---

### Task 6: Community detail view (full-screen, like, create-with-style)

Adds the full-screen detail reached by tapping a feed tile: large image, author, like toggle, and a "Create with this style" button that reuses the style or the custom prompt.

**Files:**
- Create: `Avora/Views/Community/CommunityDetailView.swift`

**Interfaces:**
- Consumes: `CommunityItem`, `AppState.loadStyles()/style(id:)`, `AvoraAPI.likeCreation/unlikeCreation`, `CreateRoute`, `RemoteImageRef`, `Style.custom`.
- Produces: view resolved by `CommunityView`'s `navigationDestination(for: CommunityItem.self)`.

- [ ] **Step 1: Create CommunityDetailView**

Create `Avora/Views/Community/CommunityDetailView.swift`:

```swift
import SwiftUI

/// Full-screen view of one shared creation: large image, author, like toggle, and
/// a button that routes into CreateView reusing the creation's style (preset) or
/// its custom prompt. Like state is local and optimistic, seeded from the item.
struct CommunityDetailView: View {
    let item: CommunityItem
    @Environment(AppState.self) private var app
    @State private var style: Style?
    @State private var liked: Bool
    @State private var likeCount: Int

    init(item: CommunityItem) {
        self.item = item
        _liked = State(initialValue: item.likedByMe)
        _likeCount = State(initialValue: item.likeCount)
    }

    /// The shared output image, reused as the CreateView placeholder.
    private var placeholder: RemoteImageRef? {
        item.outputPath.map { RemoteImageRef(path: $0, source: .output) }
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: 4)
            if let path = item.outputPath {
                RemoteImage(path: path, contentMode: .fit)
            }
            HStack {
                Text(item.username.map { "@\($0)" } ?? "@unknown")
                    .font(.avoraHeadline)
                    .foregroundStyle(Color.avoraTextSecondary)
                Spacer()
                likeButton
            }
            .padding(.horizontal, Spacing.lg)
            Spacer(minLength: 4)
            createButton
        }
        .padding(.vertical, Spacing.lg)
        .frame(maxHeight: .infinity)
        .navigationTitle(style?.name ?? "Creation")
        .navigationBarTitleDisplayMode(.inline)
        .task { await resolveStyle() }
    }

    @ViewBuilder
    private var createButton: some View {
        if let style {
            NavigationLink(value: CreateRoute(style: style, placeholder: placeholder)) {
                Label("Create with this style", systemImage: "wand.and.stars")
            }
            .buttonStyle(AvoraPrimaryButtonStyle())
            .padding(.horizontal, Spacing.lg)
        } else if let prompt = item.customPrompt {
            NavigationLink(value: CreateRoute(style: .custom, placeholder: placeholder,
                                              customPrompt: prompt)) {
                Label("Create with this style", systemImage: "wand.and.stars")
            }
            .buttonStyle(AvoraPrimaryButtonStyle())
            .padding(.horizontal, Spacing.lg)
        }
    }

    private var likeButton: some View {
        Button {
            let wasLiked = liked
            liked.toggle()
            likeCount += wasLiked ? -1 : 1
            Task {
                do {
                    let count = wasLiked
                        ? try await AvoraAPI.shared.unlikeCreation(item.id)
                        : try await AvoraAPI.shared.likeCreation(item.id)
                    likeCount = count
                } catch {
                    liked = wasLiked
                    likeCount += wasLiked ? 1 : -1
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .foregroundStyle(liked ? Color.avoraAccent : Color.avoraTextSecondary)
                Text("\(likeCount)")
                    .foregroundStyle(Color.avoraTextSecondary)
                    .contentTransition(.numericText())
            }
            .font(.avoraHeadline)
        }
        .buttonStyle(.plain)
    }

    private func resolveStyle() async {
        guard let styleId = item.styleId else { return }
        try? await app.loadStyles()
        style = app.style(id: styleId)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `XcodeBuildMCP build_sim` (scheme `Avora`).
Expected: BUILD SUCCEEDED, with the `navigationDestination(for: CommunityItem.self)` from Task 5 now resolving.

- [ ] **Step 3: Manual verification in the simulator**

Run the app (`XcodeBuildMCP build_run_sim`). Because there is no seeded shared data yet, verify what you can without it:
- The **Community** tab appears between Create and Collection with the `person.2` icon.
- Tapping it shows the segmented `Latest` / `Most liked` control and the empty state "No creations shared yet".
- Switching the segment does not crash and keeps the empty state.
(The full grid/detail/like loop is exercised end-to-end after Task 7 lets you share an item.)

- [ ] **Step 4: Commit**

```bash
git add Avora/Views/Community/CommunityDetailView.swift
git commit -m "feat: community detail view with like and create-with-style"
```

---

### Task 7: Share from Collection (toggle, custom-prompt confirmation, Shared badge)

Lets a user share/unshare their own creation from the Collection detail, warns before exposing a custom prompt, and marks shared items in the Collection grid.

**Files:**
- Modify: `Avora/Views/Collection/CollectionView.swift`

**Interfaces:**
- Consumes (from Tasks 2, 4): `AvoraAPI.shareCreation/unshareCreation`, `Generation.sharedAt`.
- Produces: end-to-end shareable data for the Community feed.

- [ ] **Step 1: Add a "Shared" badge to the Collection grid tile**

In `Avora/Views/Collection/CollectionView.swift`, the grid maps each `gen` to `Thumb(path:)`. Pass the shared state down and overlay a badge. Replace the `Thumb` usage and struct:

Change the `ForEach` body's thumbnail call:

```swift
                    NavigationLink(value: gen) {
                        Thumb(path: gen.outputPath!, shared: gen.sharedAt != nil)
                    }.buttonStyle(.plain)
```

Replace the `Thumb` struct:

```swift
private struct Thumb: View {
    let path: String
    var shared: Bool = false
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(Color.avoraSurface)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                RemoteImage(path: path, contentMode: .fill)
            }
            .clipShape(.rect(cornerRadius: Radius.sm, style: .continuous))
            .overlay(alignment: .topLeading) {
                if shared {
                    Label("Shared", systemImage: "person.2.fill")
                        .font(.avoraCaption2)
                        .labelStyle(.iconOnly)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                }
            }
    }
}
```

- [ ] **Step 2: Add the share toggle to the Collection detail toolbar**

In the same file, in `CreationDetailView`, add share state and a toolbar button next to the existing Save button. Add these `@State` properties:

```swift
    @State private var shared: Bool
    @State private var showShareConfirm = false
    @State private var sharing = false
```

Update the `init` — `CreationDetailView` currently has no explicit init, so add one that seeds `shared` from the generation (place it right after the stored `generation` property):

```swift
    init(generation: Generation) {
        self.generation = generation
        _shared = State(initialValue: generation.sharedAt != nil)
    }
```

Add a second toolbar item after the existing Save `ToolbarItem`:

```swift
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if shared {
                        Task { await setShared(false) }
                    } else if generation.customPrompt != nil {
                        showShareConfirm = true      // warn: prompt becomes public
                    } else {
                        Task { await setShared(true) }
                    }
                } label: {
                    Image(systemName: shared ? "person.2.fill" : "person.2")
                }
                .disabled(sharing)
            }
```

Add the confirmation dialog and the share action. Attach the dialog after the existing `.task { await resolveStyle() }`:

```swift
        .confirmationDialog(
            "Share to Community?", isPresented: $showShareConfirm, titleVisibility: .visible
        ) {
            Button("Share") { Task { await setShared(true) } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your prompt will be visible to others so they can create with it.")
        }
```

Add the action method inside `CreationDetailView`:

```swift
    private func setShared(_ newValue: Bool) async {
        sharing = true
        defer { sharing = false }
        do {
            if newValue {
                try await AvoraAPI.shared.shareCreation(generation.id)
            } else {
                try await AvoraAPI.shared.unshareCreation(generation.id)
            }
            shared = newValue
            SnapshotStore.clearCommunity()   // force the feed to refetch on next view
        } catch { }
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `XcodeBuildMCP build_sim` (scheme `Avora`).
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual end-to-end verification in the simulator**

Run the app (`XcodeBuildMCP build_run_sim`) with a signed-in account that has at least one completed creation:
1. Open **Collection** → tap a creation → tap the `person.2` toolbar button. For a custom-prompt creation, confirm the "Your prompt will be visible" dialog appears; tap **Share**. The icon fills (`person.2.fill`).
2. Back in the Collection grid, that tile shows the small "Shared" badge.
3. Open the **Community** tab → the shared creation appears with your `@username` and a heart.
4. Tap the heart on the card → it fills and the count increments; tap again → it clears. Force-quit and reopen: the liked state persists (served by `liked_by_me`).
5. Tap the tile → full-screen detail shows the large image, author, like control, and **Create with this style**; tapping it opens CreateView pre-filled (prompt visible for custom items).
6. Return to Collection detail → tap `person.2.fill` to unshare → the item leaves the Community feed on refresh.

- [ ] **Step 5: Commit**

```bash
git add Avora/Views/Collection/CollectionView.swift
git commit -m "feat: share creations to community from collection"
```

---

## Self-Review Notes

- **Spec coverage:** Latest/Most-liked sort (Tasks 4–5), shared-date ordering (Task 1 index + Task 2 view + Task 4 keyset), like toggle with persistence (Tasks 1/3/5/6), unshare keeps likes (Task 2/3 tests), full-screen detail (Task 6), create-with-style incl. custom prompt (Task 6), sharing from Collection with custom-prompt warning + Shared badge (Task 7), image visibility via one RLS policy (Task 1), definer feed view (Task 2), owner-only share RPCs (Task 2). All covered.
- **Out of scope confirmed absent:** no Save-to-Photos on feed, no Report/flag, no comments/follows, Most-liked is all-time.
- **Type consistency:** `CommunityItem` fields and `CommunitySort` cases are defined in Task 4 and used unchanged in Tasks 5–6; RPC names (`share_creation`, `unshare_creation`, `like_creation`, `unlike_creation`) and the `gen_id` param match between Tasks 2/3 (SQL) and Task 4 (client). `Generation.sharedAt` defined in Task 4, consumed in Task 7.
- **Known ordering dependency:** Task 5 references `CommunityDetailView` (Task 6). Implement Task 6 immediately after Task 5, or apply the temporary comment-out noted in Task 5 Step 4.
```
