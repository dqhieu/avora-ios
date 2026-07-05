# Community Tab — Design Spec

**Date:** 2026-07-05
**Status:** Approved, ready for planning

## Summary

A new **Community** tab (third tab, between Create and Collection) showing a 2-column
grid of creations users have shared publicly. The feed can be sorted by **Latest**
(shared date) or **Most liked**. Users can **like** any creation (toggleable, one per
user), open a **full-screen detail**, and **Create with this style** from any item —
including custom-prompt items, whose prompt is reused. Sharing is initiated from a
user's own Collection and is reversible; likes persist across unshare/re-share.

Image access is granted via a single added RLS policy on the private `outputs`
bucket (no storage duplication), and the feed is exposed through a security-definer
view that crosses the owner-only RLS on `generations`.

## Decisions (from brainstorming)

- **"Latest" sort orders by shared date**, not original created date. A creation only
  enters the feed when shared, so its newness in Community = when it was shared.
- **Unshare is allowed**: it removes the item from the feed (hidden), but **likes are
  kept**, so re-sharing restores the item with its like count intact.
- **Item actions:** full-screen detail + "Create with this style" on every item.
  No Save-to-Photos and no Report/flag in v1.
- **Custom-prompt reuse:** "Create with this style" works on custom-prompt items by
  exposing the prompt text publicly and pre-filling it (visible/editable) in
  `CreateView`. The sharer is warned on first share that the prompt becomes visible.
- **Likes use a dedicated `likes` table** (not a bare counter) to get per-user filled-
  heart state, toggle/unlike, and dedup/anti-inflation.

## Backend

### `likes` table (new)

```sql
create table public.likes (
  user_id       uuid references auth.users(id) on delete cascade,
  generation_id uuid references public.generations(id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (user_id, generation_id)
);
```

Likes are keyed to the generation and independent of share state, so they persist
across unshare/re-share for free.

RLS: users may select/insert/delete only their own like rows. (Writes actually flow
through the definer RPCs below, which keep `like_count` consistent; a direct client
policy is optional.)

### `generations` — new columns

- `shared_at timestamptz` — `null` = not in feed; set = shared. Ordering key for
  "Latest". Cleared on unshare.
- `like_count int not null default 0` — denormalized counter maintained atomically by
  the like/unlike RPCs, so "Most liked" can be indexed and sorted without a per-row
  aggregate. Survives unshare (matches "keep the likes").

Indexes:
- `create index generations_shared_at_idx on public.generations (shared_at desc) where shared_at is not null;`
- `create index generations_like_count_idx on public.generations (like_count desc, shared_at desc) where shared_at is not null;`

### Image visibility — one RLS policy (no duplication)

The `outputs` bucket is private; today only the owner can mint a signed URL
(`outputs_read_own`). Add a second policy so any authenticated user can read a
**shared** output:

```sql
create policy outputs_read_shared on storage.objects
  for select to authenticated
  using (bucket_id = 'outputs'
    and exists (select 1 from public.generations g
                where g.output_path = name and g.shared_at is not null));
```

The existing `RemoteImage` signed-URL flow then works unchanged for feed images.
Unshare (`shared_at → null`) immediately revokes the ability to mint new URLs.

### Feed exposure — security-definer view

Mirrors the `styles_public` pattern, but uses `security_invoker = false` so it can
cross the owner-only RLS on `generations` and return other users' shared rows:

```sql
create view public.community_feed with (security_invoker = false) as
  select g.id, g.output_path, g.style_id, g.custom_prompt,
         g.like_count, g.shared_at, p.username,
         exists(select 1 from public.likes l
                where l.generation_id = g.id and l.user_id = auth.uid()) as liked_by_me
  from public.generations g
  join public.profiles p on p.id = g.user_id
  where g.shared_at is not null;

grant select on public.community_feed to authenticated;
```

Exposes only shared rows and only safe columns (incl. `custom_prompt` per the reuse
decision, and author `username`). `auth.uid()` still resolves to the caller inside a
definer view, so `liked_by_me` is per-user correct.

### RPCs (security definer, ownership-checked)

Keeps the existing "no direct client writes to generations" invariant.

- `share_creation(gen_id uuid)` — set `shared_at = now()` where owned by caller.
- `unshare_creation(gen_id uuid)` — set `shared_at = null` where owned by caller.
- `like_creation(gen_id uuid)` — insert into `likes` and `like_count = like_count + 1`
  atomically; "already liked" is a no-op success.
- `unlike_creation(gen_id uuid)` — delete the like and `like_count = like_count - 1`
  (floored at 0); "not liked" is a no-op success.

## Client

### Tab

Add a third tab to `RootTabView` between Create and Collection:

```
Create  |  Community  |  Collection
wand    |  person.2   |  square.grid.2x2
```

A `CommunityTab` with its own `NavigationStack` + `path.isEmpty` tab-bar binding,
identical in structure to the existing two.

### `CommunityView`

Mirrors `CollectionView`: 2-col `LazyVGrid`, snapshot cache for instant paint,
pull-to-refresh. Differences:

- Reads from the `community_feed` view instead of `generations`.
- A **sort control** in the toolbar (segmented `Latest` / `Most liked`). Changing sort
  clears the list and re-queries from scratch (page 0 / cursor reset).
- Each tile is a `CommunityCard` (below).
- `navigationDestination` to `CommunityDetailView` and to `CreateRoute`.

### `CommunityCard`

Same square image tile as `StyleCard`, but the caption row shows **username + like
affordance** instead of a style name:

```
┌─────────────┐
│    image    │
├─────────────┤
│ @swiftpanda42   ♥ 12 │
└─────────────┘
```

The heart is filled when `liked_by_me`, tappable to toggle with **optimistic update**
(flip heart + adjust count immediately; revert on RPC failure).

### `CommunityDetailView`

Full-screen; reuses the Collection detail layout: large fitted image, author
`@username` + heart/count, and a **"Create with this style"** button:

- Style-based item → `CreateRoute(style:)`.
- Custom-prompt item → `CreateRoute(style: .custom, customPrompt:)`, prompt pre-filled
  and visible/editable.

No Save-to-Photos, no Report in v1.

### Sharing entry point

In the user's own Collection detail (`CreationDetailView`), add a share toggle in the
toolbar next to Save: "Share to Community" / "Shared ✓" (calls `share_creation` /
`unshare_creation`). On the **first share of a custom-prompt creation**, show a one-line
confirmation that the prompt will be visible to others. Own shared items also get a
small "Shared" badge in the Collection grid.

### Feed scope

Includes the current user's own shared creations mixed in (standard; lets users see
their work in context and its likes). Self-like is allowed.

## Sorting & pagination

- **Latest** — keyset on `shared_at` (same shape as the existing `listGenerations`
  cursor): `.order("shared_at", desc).lt("shared_at", cursor).limit(21)`; last row's
  `shared_at` is the next cursor.
- **Most liked** — offset/range: `.order("like_count", desc).order("shared_at", desc)
  .range(offset, offset+19)`. Keyset on a mutable count is fragile between pages;
  offset is fine for a browse feed. Switching sort resets to page 0 and clears the list.

## Edge cases

- **Unshared mid-scroll / stale snapshot** — signed-URL fetch 404s; `RemoteImage`
  already handles a failed load and shows its placeholder. Pull-to-refresh drops it.
- **Optimistic like revert** — on RPC failure, revert heart + count.
- **Double-like race** — `likes` PK makes duplicate insert a no-op; RPC treats "already
  liked" as success, so the count never double-counts.
- **Deleted account** — `on delete cascade` removes the user's generations and likes;
  the feed view stops returning them.
- **Empty feed** — `ContentUnavailableView` ("No creations shared yet").

## Testing (pgTAP, extends `supabase/tests/`)

- RLS: a non-owner can select a **shared** row via `community_feed` but not an unshared
  one; can mint a signed URL for a shared output but not a private one.
- `like`/`unlike` adjust `like_count` correctly; double-like is idempotent.
- Unshare preserves `like_count`; re-share restores the item with its likes intact.
- `share`/`unshare` are owner-only (another user's call is rejected).

## Out of scope (v1)

- Save-to-Photos from the feed.
- Report / flag + moderation queue.
- Comments, follows, notifications.
- "Trending" time-windowed sort (Most liked is all-time).
