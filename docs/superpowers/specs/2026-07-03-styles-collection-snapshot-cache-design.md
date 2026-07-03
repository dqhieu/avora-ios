# Styles & Collection Snapshot Cache — Design

**Date:** 2026-07-03
**Status:** Approved design, pending implementation plan

## Problem

On cold launch the app shows nothing until network fetches return. The styles
grid and the collection both start empty and paint only after a round-trip to
Supabase. Images already survive launches (`ImageStore` disk-caches them by
stable storage path), but the **list metadata** — which styles exist, which
generations the user has — is held only in memory and is lost on every launch.

Goal: on open, paint the last-seen styles and the first page of the collection
**immediately** from a local snapshot, then silently refresh from the network.

## Scope

- **In:** persist a snapshot of the styles list and the first page (~20) of the
  collection; seed the UI from it on launch; refresh and overwrite from network.
- **Out:** offline pagination beyond the first page, a queryable local store,
  offline mutation/sync, caching anything other than these two lists.
- **Explicitly rejected:** SQLite.swift (adds a dependency and hand-written
  schema for flat, already-`Codable` data), SwiftData (real local-first store —
  more than this "instant paint then refresh" goal needs).

## Approach

Snapshot-and-refresh. A small service writes the two lists to Codable JSON blobs
on disk. On launch the UI seeds synchronously from those blobs, then runs its
existing network fetch, which reconciles and overwrites the snapshot. The
snapshot is a pure, server-rebuildable optimization and is never authoritative.

## Components

### 1. `SnapshotStore` (new — `Avora/Services/SnapshotStore.swift`)

```swift
enum SnapshotStore {
    static func loadStyles() -> [Style]?
    static func saveStyles(_ styles: [Style])
    static func loadCollection() -> [Generation]?
    static func saveCollection(_ items: [Generation])
    static func clearCollection()
}
```

- **Format:** `JSONEncoder` / `JSONDecoder` over the existing `Style` and
  `Generation` structs. They are already `Codable`, so there is no mapping layer.
- **Location:** the app's Caches directory under `snapshots/`, alongside
  `ImageStore`'s cache. This is rebuildable data — if the OS purges it under
  storage pressure, the app falls back to today's blank-then-load behavior.
- **Reads are synchronous.** Decoding ~20 small rows is microseconds, so the
  first frame can paint from the snapshot without an await.
- **Writes** are invoked from the existing async fetch paths, already off the
  main thread. Every read and write is best-effort (`try?`); a failure never
  surfaces to the user and never blocks a network fetch.
- **Testability:** the base directory is injectable (default = Caches) so unit
  tests can point at a temp directory.

### 2. Styles wiring (`Avora/State/AppState.swift`)

- Seed `styles` from `SnapshotStore.loadStyles()` in `init`, so the styles grid's
  first frame already has data.
- Replace the `if !force, !styles.isEmpty { return }` guard in `loadStyles` with
  a `didFetchStyles` flag. A snapshot-seeded list is non-empty but has **not**
  been fetched this session; the flag ensures it still refreshes once (the old
  emptiness check would suppress the network fetch).
- On a successful `fetchStyles()`, call `SnapshotStore.saveStyles(styles)`.
- In `signOut()`, call `SnapshotStore.clearCollection()`.

### 3. Collection wiring (`Avora/Views/Collection/CollectionView.swift`)

- Add a `hasLoaded` `@State` flag. Replace the current
  `.task { if items.isEmpty { await loadMore() } }` with:
  1. If `items` is empty, seed it from `SnapshotStore.loadCollection()` — instant
     paint.
  2. If `!hasLoaded`, set it and run `refresh()` once. `refresh()` fetches page 1
     and replaces `items` (`items = page`), which reconciles any stale snapshot
     rows — e.g. a generation that was `pending` in the snapshot but is now
     `completed`.
- On a successful `refresh()`, call `SnapshotStore.saveCollection(page)`.
- `refresh()` already leaves the existing list untouched on failure (its comment
  notes this), so **offline the user keeps seeing their snapshot**.
- `loadMore()` (pagination past page 1) is unchanged and is not persisted.

## Data flow

```
Cold launch
  AppState.init  ── seed styles ◄── SnapshotStore.loadStyles()
  StylesGridView.task ── loadStyles() ── fetchStyles() ──► saveStyles()
  CollectionView.task
      seed items ◄── SnapshotStore.loadCollection()      (instant paint)
      refresh()  ── listGenerations(nil) ── items = page ──► saveCollection()

Sign out
  AppState.signOut() ──► SnapshotStore.clearCollection()
```

## Per-user isolation

The collection is per-user private data (styles are global and shared, so they
need no isolation). The single account-switch path in the app is
`AppState.signOut()`, so clearing the collection snapshot there prevents a
previous user's generations from flashing on the next user's cold launch.

**Assumption this rests on:** every account switch goes through `signOut()`.
True today. If the app ever gains multi-account switching that bypasses it, the
snapshot would need to be keyed by user id instead — deferred until then.

## Error handling

- Missing or corrupt snapshot file → `nil` → today's loading/empty behavior.
- Failed network refresh → seeded snapshot stays on screen (offline-friendly).
- All snapshot I/O is best-effort; nothing user-facing depends on it succeeding.

## Testing

- `SnapshotStore` round-trip: `saveStyles`/`saveCollection` then load returns an
  equal array.
- `clearCollection` removes the collection snapshot; a subsequent
  `loadCollection()` returns `nil`.
- Corrupt/absent file → `loadStyles()` / `loadCollection()` return `nil` rather
  than throwing.
- Tests use an injected temp directory.

## Footprint

One new file (`SnapshotStore.swift`) plus small edits to `AppState.swift` and
`CollectionView.swift`. No new third-party dependency.
