# Styles & Collection Snapshot Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On cold launch, paint the last-seen styles and the first page of the collection instantly from an on-disk snapshot, then silently refresh from the network.

**Architecture:** A small `SnapshotStore` service writes the two lists to Codable JSON blobs in the app's Caches directory. `AppState` seeds `styles` from the snapshot at init and persists after each fetch; `CollectionView` seeds `items` from the snapshot on appear and persists the first page after each refresh. The snapshot is a rebuildable optimization — never authoritative, all I/O best-effort.

**Tech Stack:** Swift, SwiftUI, `@Observable`, `Foundation` (`JSONEncoder`/`JSONDecoder`, `FileManager`). Backend is Supabase (unchanged). No new third-party dependency.

## Global Constraints

- iOS deployment target of the `Avora` app target — no new third-party dependencies.
- The `Style` and `Generation` models are already `Codable`; reuse them directly, no DTO/mapping layer.
- The snapshot is never authoritative: every read and write is best-effort (`try?`) and must never throw to a caller or block a network fetch.
- Snapshot lives in the **Caches** directory (rebuildable; OS may purge it → app falls back to blank-then-load).
- Collection snapshot holds the **first page only** (whatever `listGenerations(cursor: nil)` returns, ≤20 rows). Pagination past page 1 is not persisted.
- The collection snapshot is cleared on sign-out; styles are global and are not cleared.
- No unit-test target exists in this project. Each task is verified by a **build** (compile check); the final task verifies runtime behavior by **running the app in the simulator**.

**Build command** (used as the per-task verification):

Preferred — XcodeBuildMCP: call `build_sim` for scheme `Avora` (run `session_show_defaults` first; if project/scheme/simulator aren't set, `discover_projs` then set them).

Fallback — shell:
```bash
xcodebuild -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```
Expected: `** BUILD SUCCEEDED **`.

---

### Task 1: `SnapshotStore` service

**Files:**
- Create: `Avora/Services/SnapshotStore.swift`

**Interfaces:**
- Consumes: `Style` (`Avora/Models/Style.swift`), `Generation` (`Avora/Models/Generation.swift`) — both already `Codable`.
- Produces:
  - `SnapshotStore.loadStyles() -> [Style]?`
  - `SnapshotStore.saveStyles(_ styles: [Style])`
  - `SnapshotStore.loadCollection() -> [Generation]?`
  - `SnapshotStore.saveCollection(_ items: [Generation])`
  - `SnapshotStore.clearCollection()`
  - All are synchronous `static` functions on an `enum SnapshotStore`.

- [ ] **Step 1: Create the file with the full implementation**

Create `Avora/Services/SnapshotStore.swift`:

```swift
import Foundation

/// Persists small snapshots of list metadata (styles, first page of the
/// collection) so the UI can paint instantly on cold launch, before the network
/// refresh returns. Rebuildable optimization: every read and write is
/// best-effort and the snapshot is never authoritative.
enum SnapshotStore {
    /// Base directory for snapshot files (Caches/snapshots). Rebuildable data,
    /// so the OS may purge it — callers fall back to a normal network load.
    private static let directory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var stylesURL: URL { directory.appendingPathComponent("styles.json") }
    private static var collectionURL: URL { directory.appendingPathComponent("collection.json") }

    static func loadStyles() -> [Style]? { load([Style].self, from: stylesURL) }
    static func saveStyles(_ styles: [Style]) { save(styles, to: stylesURL) }

    static func loadCollection() -> [Generation]? { load([Generation].self, from: collectionURL) }
    static func saveCollection(_ items: [Generation]) { save(items, to: collectionURL) }

    static func clearCollection() { try? FileManager.default.removeItem(at: collectionURL) }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 2: Add the file to the Xcode target**

The `Avora` project uses a synchronized folder group, so files under `Avora/` are picked up automatically. Confirm the build sees it in the next step; if not, add `SnapshotStore.swift` to the `Avora` target membership in Xcode.

- [ ] **Step 3: Build to verify it compiles**

Run the Global-Constraints build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Avora/Services/SnapshotStore.swift
git commit -m "feat: add SnapshotStore for on-disk list snapshots"
```

---

### Task 2: Seed & persist styles, clear collection on sign-out (`AppState`)

**Files:**
- Modify: `Avora/State/AppState.swift`

**Interfaces:**
- Consumes: `SnapshotStore.loadStyles()`, `SnapshotStore.saveStyles(_:)`, `SnapshotStore.clearCollection()` (Task 1).
- Produces: unchanged public API — `styles: [Style]`, `loadStyles(force:)`, `signOut()`. `StylesGridView` needs no changes (it already reads `app.styles` and calls `app.loadStyles(force:)`).

- [ ] **Step 1: Seed `styles` from the snapshot and add a fetch flag**

In `Avora/State/AppState.swift`, change the `styles` property (currently `var styles: [Style] = []`) and add a private flag beneath it:

```swift
    // Seeded synchronously from the last on-disk snapshot so the styles grid's
    // first frame already has data; refreshed once per session on first view.
    var styles: [Style] = SnapshotStore.loadStyles() ?? []
    private var didFetchStyles = false
```

- [ ] **Step 2: Refresh once per session and persist on success**

Replace the existing `loadStyles(force:)` method:

```swift
    func loadStyles(force: Bool = false) async throws {
        if !force, didFetchStyles { return }
        styles = try await AvoraAPI.shared.fetchStyles()
        didFetchStyles = true
        SnapshotStore.saveStyles(styles)
    }
```

The guard now keys on `didFetchStyles` rather than `!styles.isEmpty`: a snapshot-seeded list is non-empty but not yet fetched this session, and must still refresh once (the old emptiness check would suppress that fetch).

- [ ] **Step 3: Clear the collection snapshot on sign-out**

In `signOut()`, add the clear call after `profile = nil`:

```swift
    func signOut() async {
        try? await SupabaseClientProvider.client.auth.signOut()
        isAuthenticated = false
        profile = nil
        SnapshotStore.clearCollection()
    }
```

- [ ] **Step 4: Build to verify it compiles**

Run the Global-Constraints build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Avora/State/AppState.swift
git commit -m "feat: seed styles from snapshot and clear collection on sign-out"
```

---

### Task 3: Seed & persist the collection first page (`CollectionView`)

**Files:**
- Modify: `Avora/Views/Collection/CollectionView.swift`

**Interfaces:**
- Consumes: `SnapshotStore.loadCollection()`, `SnapshotStore.saveCollection(_:)` (Task 1); existing `AvoraAPI.shared.listGenerations(cursor:)`.
- Produces: no new external interface — internal view wiring only.

- [ ] **Step 1: Add a `hasLoaded` state flag**

In `CollectionView`, add beside the other `@State` properties (after `@State private var reloadToken = 0`):

```swift
    @State private var hasLoaded = false
```

- [ ] **Step 2: Seed from the snapshot, then refresh once**

Replace the existing task modifier `.task { if items.isEmpty { await loadMore() } }` with:

```swift
        .task {
            // Paint instantly from the last snapshot, then reconcile once from
            // the network. hasLoaded is flipped after the refresh so the empty
            // state can't flash during a first-ever load with no snapshot.
            if items.isEmpty { items = SnapshotStore.loadCollection() ?? [] }
            guard !hasLoaded else { return }
            await refresh()
            hasLoaded = true
        }
```

- [ ] **Step 3: Gate the empty state on `hasLoaded` instead of `loading`**

`refresh()` does not touch `loading`, so the empty-state overlay must key on `hasLoaded` (set only after the first refresh completes) to avoid flashing "No creations yet" during the initial load. In the `.overlay { ... }`, change the condition:

```swift
        .overlay {
            if items.isEmpty && hasLoaded {
                ContentUnavailableView(
                    "No creations yet",
                    systemImage: "square.grid.2x2",
                    description: Text("Generated images will appear here.")
                )
            }
        }
```

- [ ] **Step 4: Persist the first page after a successful refresh**

Replace the `refresh()` method:

```swift
    // Load the first page into place without blanking the list first, so a failed
    // or in-flight-superseded refresh can't leave the collection stuck empty.
    private func refresh() async {
        reloadToken += 1
        if let (page, next) = try? await AvoraAPI.shared.listGenerations(cursor: nil) {
            items = page
            nextCursor = next
            SnapshotStore.saveCollection(page)
        }
    }
```

`loadMore()` is unchanged — pagination past page 1 is not persisted.

- [ ] **Step 5: Build to verify it compiles**

Run the Global-Constraints build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Avora/Views/Collection/CollectionView.swift
git commit -m "feat: seed collection from snapshot and persist first page"
```

---

### Task 4: Runtime verification in the simulator

**Files:** none (manual verification of the integrated feature).

**Interfaces:** exercises Tasks 1–3 end to end.

- [ ] **Step 1: Build and run on a simulator**

Preferred — XcodeBuildMCP `build_run_sim` (scheme `Avora`). Fallback — build with the Global-Constraints command, then `install_app_sim` + `launch_app_sim`, or run from Xcode.
Sign in with a test account that has at least one completed generation.

- [ ] **Step 2: Verify instant paint on cold launch**

Open the Styles tab and the Collection tab so both fetch at least once (this writes the snapshots). Fully terminate the app (swipe it away in the app switcher / `stop_app_sim` then relaunch). Relaunch.
Expected: the styles grid and the first screen of the collection appear **immediately** on launch, before any spinner — populated from the snapshot, then quietly refreshed.

- [ ] **Step 3: Verify offline fallback**

With snapshots written (Step 2), turn on Airplane Mode (or disable the simulator's network) and cold-launch the app.
Expected: styles and the first page of the collection still render from the snapshot; no blank screen and no "No creations yet" flash. (New below-the-fold scrolling won't load — expected.)

- [ ] **Step 4: Verify sign-out clears the collection**

Re-enable the network. Sign out, then sign in as a **different** account (or the same account after confirming). Cold-launch if needed.
Expected: the previous account's generations do **not** appear on the collection's first frame. A brand-new/empty account shows "No creations yet" only after the refresh completes (no stale flash).

- [ ] **Step 5: Confirm the working tree is clean**

```bash
git status
```
Expected: clean (all changes already committed in Tasks 1–3). No commit needed for this task.

---

## Self-Review

**Spec coverage:**
- `SnapshotStore` component with the five-function API + Caches location + best-effort I/O → Task 1. ✓
- Styles wiring: seed in init, `didFetchStyles` flag replacing the emptiness guard, save on fetch, `clearCollection()` in `signOut()` → Task 2. ✓
- Collection wiring: `hasLoaded` flag, seed-then-`refresh()`-once, `saveCollection` on success, `loadMore` unchanged, offline keeps snapshot → Task 3. ✓
- First-page-only, per-user isolation via clear-on-sign-out, error handling (best-effort, failed refresh keeps seed) → Global Constraints + Tasks 2–3, verified in Task 4. ✓
- Testing: spec's unit tests replaced by build + runtime verification per the agreed no-test-target decision → per-task build + Task 4. ✓ (Deviation from spec's "Testing" section, agreed with user.)

**Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to Task N". All code shown in full. ✓

**Type consistency:** `loadStyles()`/`saveStyles(_:)`/`loadCollection()`/`saveCollection(_:)`/`clearCollection()` names identical across Task 1 (definition) and Tasks 2–3 (calls). `hasLoaded`, `refresh()`, `loadMore()`, `items`, `nextCursor`, `reloadToken` match `CollectionView`'s existing members. `didFetchStyles`, `styles`, `loadStyles(force:)`, `signOut()` match `AppState`. ✓
