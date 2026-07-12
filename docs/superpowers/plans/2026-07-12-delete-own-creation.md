# Delete Your Own Creation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user permanently delete one of their own creations (generation row + output image + input image) from the Creation detail screen.

**Architecture:** A new `delete-creation` Supabase Edge Function (service role) verifies ownership, deletes the `generations` row (FK cascade removes likes + drops it from the community feed), then best-effort removes the storage objects. The iOS client calls it from a trash button in the Creation detail toolbar behind a destructive confirmation, then removes the item from the Collection grid locally.

**Tech Stack:** Supabase Edge Functions (Deno/TypeScript), Postgres + pgTAP, SwiftUI, Swift `Supabase` SDK.

## Global Constraints

- Hard delete, no credit refund, no undo.
- Entry point is the Creation **detail view only** — no grid long-press, no Community deletion.
- Edge Function mirrors the existing `supabase/functions/delete-account/index.ts` conventions (shared `cors.ts` + `supabase.ts` helpers).
- Ownership gate lives in the Edge Function: `user_id !== uid` → `403`, not found → `404`.
- Delete the DB row **before** storage cleanup; ignore storage-remove errors.
- Swift files stay under 200 lines where practical; follow existing style in `CollectionView.swift` and `AvoraAPI.swift`.
- Do not run the app on the simulator — build to check compilation only; the user verifies UI manually.
- No plan/phase references in code comments, filenames, or test names.

---

## File Structure

- **Create:** `supabase/functions/delete-creation/index.ts` — the Edge Function.
- **Create:** `supabase/tests/090_delete_creation_test.sql` — pgTAP cascade test.
- **Modify:** `Avora/Services/AvoraAPI.swift` — add `deleteCreation(_:)`.
- **Modify:** `Avora/Views/Collection/CollectionView.swift` — trash button, confirmation, `delete()`, `onDelete` closure wiring.

---

## Task 1: pgTAP cascade test + Edge Function

**Files:**
- Create: `supabase/tests/090_delete_creation_test.sql`
- Create: `supabase/functions/delete-creation/index.ts`

**Interfaces:**
- Consumes: `handleOptions`, `json` from `../_shared/cors.ts`; `requireUser`, `serviceClient` from `../_shared/supabase.ts`.
- Produces: HTTP endpoint `POST /functions/v1/delete-creation` with body `{ "id": "<uuid>" }` returning `{ "ok": true }` on success; `400` invalid body, `401` unauthorized, `403` not owner, `404` not found.

- [ ] **Step 1: Write the failing pgTAP test**

The test locks in the invariant the Edge Function relies on: deleting a `generations` row cascades its `likes` and removes it from `community_feed`. Follow the `082_community_likes_test.sql` pattern (privileged `reset role` reads to avoid the local grant gap).

Create `supabase/tests/090_delete_creation_test.sql`:

```sql
begin;
select plan(3);

insert into auth.users (id, email) values
  ('d1111111-1111-1111-1111-111111111111', 'd1@test.dev'),
  ('d2222222-2222-2222-2222-222222222222', 'd2@test.dev');
insert into public.styles (id, name, prompt_template) values ('ds1','Style 1','SECRET');

-- user D1 owns a shared creation; user D2 has liked it
insert into public.generations
  (id, user_id, style_id, charged_bucket, charged_amount, input_path, quality,
   output_path, status, shared_at, like_count)
values
  ('daaaaaaa-0000-0000-0000-000000000001',
   'd1111111-1111-1111-1111-111111111111','ds1','extra',25,'in/a.png','medium',
   'out/a.png','completed', now(), 1);
insert into public.likes (user_id, generation_id) values
  ('d2222222-2222-2222-2222-222222222222',
   'daaaaaaa-0000-0000-0000-000000000001');

-- act as owner and delete the row (mirrors what the Edge Function does with
-- service role: a plain delete on generations)
delete from public.generations
  where id = 'daaaaaaa-0000-0000-0000-000000000001';

select is(
  (select count(*)::int from public.generations
     where id = 'daaaaaaa-0000-0000-0000-000000000001'),
  0, 'generation row is gone');
select is(
  (select count(*)::int from public.likes
     where generation_id = 'daaaaaaa-0000-0000-0000-000000000001'),
  0, 'likes cascade-deleted with the generation');
select is(
  (select count(*)::int from public.community_feed
     where id = 'daaaaaaa-0000-0000-0000-000000000001'),
  0, 'creation no longer appears in the community feed');

select * from finish();
rollback;
```

- [ ] **Step 2: Run the test to verify it passes**

The cascade is enforced by the existing FK (`likes.generation_id ... on delete cascade`) and the `community_feed` view definition, so this test documents current behavior and should pass immediately.

Run: `supabase test db`
Expected: `090_delete_creation_test.sql .. ok` (all 3 assertions pass).

> Note (from project memory): the local `supabase test db` baseline has a known pre-existing failure in `020_rls_test.sql` due to a grant gap. That is unrelated to this task — confirm `090` itself reports `ok`.

- [ ] **Step 3: Write the Edge Function**

Create `supabase/functions/delete-creation/index.ts`:

```typescript
import { handleOptions, json } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let uid: string;
  try {
    uid = await requireUser(req);
  } catch {
    return json({ error: "unauthorized" }, 401);
  }

  let id: string;
  try {
    const body = await req.json();
    id = body?.id;
    if (typeof id !== "string" || id.length === 0) throw new Error("bad id");
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const db = serviceClient();

  const { data: gen } = await db
    .from("generations")
    .select("user_id, input_path, output_path")
    .eq("id", id)
    .maybeSingle();

  if (!gen) return json({ error: "not_found" }, 404);
  if (gen.user_id !== uid) return json({ error: "forbidden" }, 403);

  // Delete the row first (user-facing source of truth); FK cascade removes the
  // likes and drops it from the community feed. A leftover storage object is
  // invisible and gets swept by account deletion, so storage cleanup is
  // best-effort and its errors are ignored.
  const { error: delErr } = await db.from("generations").delete().eq("id", id);
  if (delErr) return json({ error: "delete_failed" }, 500);

  if (gen.output_path) {
    await db.storage.from("outputs").remove([gen.output_path]);
  }
  await db.storage.from("inputs").remove([gen.input_path]);

  return json({ ok: true });
});
```

- [ ] **Step 4: Type-check the function**

Run: `deno check supabase/functions/delete-creation/index.ts`
Expected: no errors. (If `deno` is unavailable locally, skip — the shared imports match `delete-account/index.ts` exactly, which already type-checks in CI.)

- [ ] **Step 5: Commit**

```bash
git add supabase/tests/090_delete_creation_test.sql supabase/functions/delete-creation/index.ts
git commit -m "feat: add delete-creation edge function and cascade test"
```

---

## Task 2: Client API method

**Files:**
- Modify: `Avora/Services/AvoraAPI.swift` (add method next to `deleteAccount()` at the end of the struct, around line 220-223)

**Interfaces:**
- Consumes: `POST /functions/v1/delete-creation` from Task 1.
- Produces: `func deleteCreation(_ id: UUID) async throws` on `AvoraAPI`.

- [ ] **Step 1: Add the `deleteCreation` method**

In `Avora/Services/AvoraAPI.swift`, add immediately after the `deleteAccount()` method (before the closing `}` of the struct):

```swift
    func deleteCreation(_ id: UUID) async throws {
        struct Body: Encodable { let id: String }
        let _: [String: Bool] = try await db.functions.invoke(
            "delete-creation",
            options: .init(method: .post, body: Body(id: id.uuidString)))
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`. (Do not launch the app.)

- [ ] **Step 3: Commit**

```bash
git add Avora/Services/AvoraAPI.swift
git commit -m "feat: add deleteCreation client API method"
```

---

## Task 3: Delete UI in Creation detail + Collection wiring

**Files:**
- Modify: `Avora/Views/Collection/CollectionView.swift`
  - `navigationDestination(for: Generation.self)` at line 31
  - `CreationDetailView` struct starting at line 117 (add `onDelete`, state, toolbar button, confirmation, `delete()`)

**Interfaces:**
- Consumes: `AvoraAPI.shared.deleteCreation(_:)` from Task 2; `SnapshotStore.clearCommunity()` and `SnapshotStore.saveCollection(_:)` (existing); `ToastWindowManager.shared.show(title:)` (existing); `Haptics` (existing).
- Produces: `CreationDetailView(generation:onDelete:)` initializer taking `onDelete: @escaping (UUID) -> Void`.

- [ ] **Step 1: Pass an `onDelete` closure from the Collection grid**

In `CollectionView.body`, replace the navigation destination at line 31:

```swift
        .navigationDestination(for: Generation.self) { CreationDetailView(generation: $0) }
```

with:

```swift
        .navigationDestination(for: Generation.self) { gen in
            CreationDetailView(generation: gen, onDelete: { deletedId in
                items.removeAll { $0.id == deletedId }
                SnapshotStore.saveCollection(items)
            })
        }
```

- [ ] **Step 2: Add `onDelete`, dismiss, and delete state to `CreationDetailView`**

In `CreationDetailView`, update the stored properties and initializer. Replace:

```swift
private struct CreationDetailView: View {
    let generation: Generation
    init(generation: Generation) {
        self.generation = generation
        _shared = State(initialValue: generation.sharedAt != nil)
    }
    @Environment(AppState.self) private var app
    @State private var style: Style?
    @State private var shared: Bool
    @State private var showShareConfirm = false
    @State private var sharing = false
```

with:

```swift
private struct CreationDetailView: View {
    let generation: Generation
    let onDelete: (UUID) -> Void
    init(generation: Generation, onDelete: @escaping (UUID) -> Void) {
        self.generation = generation
        self.onDelete = onDelete
        _shared = State(initialValue: generation.sharedAt != nil)
    }
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var style: Style?
    @State private var shared: Bool
    @State private var showShareConfirm = false
    @State private var sharing = false
    @State private var showDeleteConfirm = false
    @State private var deleting = false
```

- [ ] **Step 3: Add the trash toolbar button**

In the `.toolbar { ... }` block of `CreationDetailView`, add a third `ToolbarItem` after the share button's `ToolbarItem` (which ends at line 189 with `.disabled(sharing)` then `}`):

```swift
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.warning()
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .disabled(deleting)
            }
```

> Icon note: there is no custom `ActionDelete` raster asset (the `ThiingIcon`
> Save/Share buttons use assets like `ActionSave`/`ActionShare`, which don't
> include a trash glyph). The app already uses SF Symbols via
> `Image(systemName:)` elsewhere (e.g. `CreateView.swift`), so a red `trash`
> SF Symbol is the correct, asset-free choice for this destructive action.

- [ ] **Step 4: Add the destructive confirmation dialog**

Attach a second `.confirmationDialog` right after the existing "Share to Community?" dialog (which ends around line 199 with its closing `}`):

```swift
        .confirmationDialog(
            "Delete creation?", isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Haptics.warning(); Task { await delete() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes it. This can't be undone.")
        }
```

- [ ] **Step 5: Add the `delete()` method**

Add this method inside `CreationDetailView`, next to `setShared(_:)`:

```swift
    private func delete() async {
        deleting = true
        defer { deleting = false }
        do {
            try await AvoraAPI.shared.deleteCreation(generation.id)
            if generation.sharedAt != nil { SnapshotStore.clearCommunity() }
            onDelete(generation.id)
            dismiss()
            ToastWindowManager.shared.show(title: "Deleted")
        } catch {
            ToastWindowManager.shared.show(title: "Couldn't delete")
        }
    }
```

- [ ] **Step 6: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`. (Do not launch the app.)

- [ ] **Step 7: Commit**

```bash
git add Avora/Views/Collection/CollectionView.swift
git commit -m "feat: add delete button to creation detail view"
```

---

## Self-Review Notes

**Spec coverage:**
- Edge Function (spec §1) → Task 1. Ownership gate, row-first delete, best-effort storage, cascade → all present.
- Client API (spec §2) → Task 2 (signature matches `deleteCreation(_ id: UUID)`).
- UI trash button + confirmation + delete flow (spec §3) → Task 3 steps 2-5.
- Collection refresh via `onDelete` closure (spec §4) → Task 3 step 1.
- pgTAP cascade test (spec §5) → Task 1 step 1.
- Out-of-scope items (refund, undo, grid/community deletion, bulk) → none added. ✓

**Type consistency:** `deleteCreation(_ id: UUID)` defined in Task 2, consumed in Task 3 step 5. `CreationDetailView(generation:onDelete:)` defined in Task 3 step 2, consumed in Task 3 step 1. `onDelete: (UUID) -> Void` consistent throughout. ✓

**Icon resolved:** No custom trash asset exists; Task 3 step 3 uses a red `trash` SF Symbol (consistent with existing `Image(systemName:)` usage). `Haptics.warning()` and `Haptics.tap()` both exist (`Avora/DesignSystem/Haptics.swift`).
