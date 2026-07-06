# "More from @username" in CommunityDetailView — Design

**Date:** 2026-07-06
**Status:** Approved, ready for planning

## Goal

On the community creation detail screen (`CommunityDetailView`), show a section with
the author's **other publicly shared creations**, so viewers can discover more from a
user they like without going back to the feed.

Scope is limited to *shared* creations, because the app can only read other users'
rows through the `community_feed` definer view (which exposes only `shared_at is not
null` rows). Private creations of another user are neither accessible under RLS nor in
scope.

## User-facing behavior

- Below the existing "Create with this style" button, a **"More from @username"**
  section appears.
- It shows up to **12** of the author's most recently shared creations (newest first),
  **excluding the creation currently open**.
- Layout: the whole detail screen becomes vertically scrollable; the section is a
  2-column `LazyVGrid` of square image thumbnails.
- Tapping a thumbnail **pushes a new `CommunityDetailView`** for that creation (recursive
  navigation via the existing stack destination). Each pushed screen runs its own fetch.
- If the author has **no other shared creations**, the section is **hidden entirely** —
  no header, no placeholder. The screen looks exactly as it does today.
- No pagination and no like affordance inside the thumbnails (teaser, not a full feed).

## Data layer — `AvoraAPI`

Add one method:

```swift
func communityByUser(_ username: String, excluding id: UUID, limit: Int = 12) async throws -> [CommunityItem]
```

- Queries `community_feed`:
  - `.eq("username", username)`
  - `.neq("id", id.uuidString)` — excludes the current item server-side
  - `.order("shared_at", ascending: false)`
  - `.limit(limit)`
- Reuses the existing select column list
  (`id,output_path,style_id,custom_prompt,like_count,username,liked_by_me,shared_at`)
  and decodes into the existing `CommunityItem` model.
- **No schema/migration change.** `username` is unique (`profiles_username_key`), so
  filtering by it correctly scopes to one author.
- Returns `[]` when the user has no other shared creations.

## View layer — `CommunityDetailView`

- Wrap the current body content in a `ScrollView` so the full screen scrolls. The hero
  image, author/like row, and "Create with this style" button stay at the top, unchanged.
- Add `@State private var more: [CommunityItem] = []`.
- Add a `@ViewBuilder moreSection` rendered below the Create button:
  - Renders **only when `!more.isEmpty`**.
  - Left-aligned header: `More from @username`.
  - `LazyVGrid` with 2 columns using the feed's `GridItem(.flexible(), spacing: 8)` pattern.
  - Each cell is a `NavigationLink(value: otherItem)` wrapping a square
    `RoundedRectangle(cornerRadius: Radius.md)` + `RemoteImage(path:, contentMode: .fill)` —
    the same tile visual as `CommunityCard`, without the caption/like row. A small inline
    thumbnail subview may be extracted for clarity.
- Fetch inside the existing `.task`: after `resolveStyle()`, if `item.username` is non-nil,
  call `communityByUser(username, excluding: item.id)` and assign to `more`. Errors are
  swallowed (section stays hidden), matching the feed's silent-failure convention.

## Untouched

- Like toggle logic, style resolution, Create routing, navigation title.
- No new files; `CommunityDetailView.swift` grows from ~100 to ~130 lines (still under the
  200-line guideline).
- The parent stack already registers `navigationDestination(for: CommunityItem.self)` and
  `navigationDestination(for: CreateRoute.self)`, so recursive push and Create routing keep
  working without changes.

## Edge cases

- **Current item excluded** via `.neq` server-side.
- **Only creation:** empty result → section hidden.
- **Username changes:** filtering is by the username present on the item at read time;
  acceptable for a discovery teaser.
- **Recursive navigation:** pushing another detail re-runs the fetch for the new author;
  no shared mutable state between pushed screens.

## Explicitly out of scope

- Pagination / load-more in the section.
- Showing private (unshared) creations.
- Empty-state placeholder UI.
- Any backend/migration change.
