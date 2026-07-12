# Delete Your Own Creation — Design

**Date:** 2026-07-12
**Status:** Approved (design)

## Goal

Let a user permanently delete one of their own creations from the Creation detail
screen. A "creation" is a `generations` row plus its output image (`outputs`
bucket) and input image (`inputs` bucket).

## Decisions

| Question | Decision |
|----------|----------|
| Delete semantics | **Hard delete, no refund.** Permanently remove row + output + input. Credits already spent are not returned. No undo. |
| Entry point | **Detail view only** — a trash button in the Creation detail toolbar. |
| Backend | **Edge Function** (`delete-creation`), mirroring the existing `delete-account` function. |

## Architecture context

- `public.generations` is **owner-read-only** under RLS. All writes go through
  `SECURITY DEFINER` RPCs or the service role — there are no client write policies.
- `likes.generation_id` has `on delete cascade`, so deleting a generation row
  auto-removes its likes and drops it from the `community_feed` view (the view
  filters `shared_at is not null` joined to `generations`).
- The `outputs` bucket has **no client delete policy** (only `outputs_read_own`),
  so removing an output image requires the service role via an Edge Function.
- The `inputs` bucket already has `inputs_own` (for all ops under the user's uid
  prefix), but for consistency and atomicity the same Edge Function removes both.

## Components

### 1. Edge Function — `supabase/functions/delete-creation/index.ts`

Mirrors `delete-account/index.ts`.

- `POST` only; `handleOptions` for preflight.
- `requireUser(req)` → `uid`; `401` on failure.
- Parse JSON body `{ id: string }` (generation id). Missing/invalid → `400`.
- `serviceClient()`:
  1. Look up the generation:
     `select input_path, output_path, user_id from generations where id = :id`.
     - Not found → `404`.
     - `user_id !== uid` → `403`. **This is the ownership gate.**
  2. Delete the row: `delete from generations where id = :id`.
     FK `on delete cascade` removes `likes` and removes it from `community_feed`.
  3. Best-effort storage cleanup (after the row delete, so a storage hiccup can't
     leave a visible broken row):
     - `outputs.remove([output_path])` — skip if `output_path` is null.
     - `inputs.remove([input_path])`.
     Ignore storage errors; a leftover object is invisible and is swept by
     account deletion.
- Return `{ ok: true }`.

Rationale for row-first ordering: the row is the user-facing source of truth. An
orphaned storage object is harmless; a row pointing at a missing image would show
a broken thumbnail.

### 2. Client API — `AvoraAPI.deleteCreation(_ id: UUID)`

In `Avora/Services/AvoraAPI.swift`, next to `deleteAccount()`:

```swift
func deleteCreation(_ id: UUID) async throws {
    struct Body: Encodable { let id: String }
    let _: [String: Bool] = try await db.functions.invoke(
        "delete-creation",
        options: .init(method: .post, body: Body(id: id.uuidString)))
}
```

### 3. UI — `CreationDetailView` (in `Avora/Views/Collection/CollectionView.swift`)

- Add state: `@State private var showDeleteConfirm = false`,
  `@State private var deleting = false`.
- Accept a new closure: `let onDelete: (UUID) -> Void`.
- Toolbar: add a trash button (`topBarTrailing`, alongside Save/Share) that sets
  `showDeleteConfirm = true`; `.disabled(deleting)`.
- Destructive `confirmationDialog` titled **"Delete creation?"**:
  - **Delete** (`role: .destructive`) → `Task { await delete() }`
  - **Cancel** (`role: .cancel`)
  - Message: *"This permanently removes it. This can't be undone."*
- `delete()`:
  1. `deleting = true` (defer reset).
  2. `try await AvoraAPI.shared.deleteCreation(generation.id)`.
  3. On success:
     - If `generation.sharedAt != nil` → `SnapshotStore.clearCommunity()`.
     - `onDelete(generation.id)`.
     - `dismiss()` (pop to Collection).
     - Toast **"Deleted"**.
  4. On failure: toast **"Couldn't delete"**, stay on screen.

Use `@Environment(\.dismiss)` to pop.

### 4. Collection refresh — `CollectionView`

Thread the `onDelete` closure through the navigation destination so the grid
updates instantly on pop without a network round-trip:

```swift
.navigationDestination(for: Generation.self) { gen in
    CreationDetailView(generation: gen, onDelete: { deletedId in
        items.removeAll { $0.id == deletedId }
        SnapshotStore.saveCollection(items)
    })
}
```

## Error handling

- Delete failure (network/server) → toast, remain on detail, button re-enabled.
- Only completed creations with an `output_path` are reachable in detail (the grid
  filters `status == .completed && outputPath != nil`), but the function handles a
  null `output_path` gracefully regardless.

## Testing

- pgTAP test in `supabase/tests`: deleting a `generations` row cascades its `likes`
  and removes it from `community_feed`.
- Ownership check (TS) verified via code review.
- Build compiles (no simulator run); UI verified manually by the user.

## Out of scope

- No credit refund, no undo / "recently deleted".
- No deletion from the Community feed or the Collection grid (long-press) — detail
  view only.
- No bulk delete.
