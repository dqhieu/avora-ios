# Multi-photo Sticker Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Sticker Lab process up to 16 photos at once, showing each as an independent sticker in a grid with bulk "Save All" and per-sticker tap-to-save.

**Architecture:** Rewrite `StickerLabView` around a per-photo `StickerItem` model and a `LazyVGrid`. Photos are loaded from a multi-select `PhotosPicker`, then run through the existing `StickerProcessor.makeSticker` with bounded concurrency (3 in flight) via a `TaskGroup`. Each item tracks its own processing/done/failed and saved state, so failures and slow photos stay isolated. `StickerProcessor` is unchanged.

**Tech Stack:** SwiftUI, PhotosUI (`PhotosPicker`), Swift Concurrency (`TaskGroup`), existing design tokens (`Spacing`, `Radius`, `Color.avora*`, fonts), `AvoraPrimaryButton`, `Haptics`, `ToastWindowManager`.

## Global Constraints

- Only `Avora/Views/Create/StickerLabView.swift` changes. `Avora/Services/StickerProcessor.swift` is **not** modified.
- Fully on-device: no upload, no credits, no Collection/Community.
- Max selection: **16** photos. Grid: **3 columns**. Processing concurrency: **at most 3** in flight.
- Verification is **compile-only** — build the `Avora` scheme. Do not run the app on the simulator; the user verifies UI manually. There is no unit-test harness for SwiftUI views in this project.
- Keep the existing `Checkerboard` private view.
- Match existing style: design tokens, `@ViewBuilder` computed subviews, `nonisolated`/main-actor boundaries as in the current file.

**Build/verify command (used as the "test" in every task):**

```
build_sim({ projectPath: "/Users/hieudinh/Projects/avora-ios/Avora.xcodeproj", scheme: "Avora", simulatorName: "iPhone 17" })
```
Expected: `BUILD SUCCEEDED`.

---

### Task 1: Item model + multi-select state + empty/grid scaffold

Replace the single-photo state with the per-item model and a multi-select picker. This task ends with the view compiling: an empty prompt, a `LazyVGrid` that renders one cell per picked photo (source image only, no processing yet), and a disabled Save All button.

**Files:**
- Modify: `Avora/Views/Create/StickerLabView.swift` (rewrite the `StickerLabView` struct; keep `Checkerboard` at the bottom unchanged).

**Interfaces:**
- Consumes: `StickerProcessor.makeSticker(from:) async -> UIImage?` (existing, unchanged), `Checkerboard` (existing), `Spacing`, `Radius`, `Color.avora*`, `.avoraLargeTitle`/`.avoraFootnote`, `AvoraPrimaryButton`, `Haptics`, `ToastWindowManager`.
- Produces: `StickerItem` struct and the `items`/`pickerSelection` state used by Tasks 2–3.

- [ ] **Step 1: Rewrite the view's state and top-level body**

Replace the entire `StickerLabView` struct (lines 9–111 of the current file) with the code below. Leave the `Checkerboard` struct (from `/// Light/dark checkerboard…` to end of file) exactly as-is.

```swift
struct StickerLabView: View {
    /// One picked photo and its independent sticker lifecycle.
    struct StickerItem: Identifiable {
        let id = UUID()
        let source: UIImage
        var result: UIImage?
        var status: Status = .processing
        var saved = false

        enum Status { case processing, done, failed }
    }

    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var items: [StickerItem] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 3)

    private var isProcessing: Bool { items.contains { $0.status == .processing } }
    private var hasUnsaved: Bool { items.contains { $0.status == .done && !$0.saved } }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            content
            if !items.isEmpty {
                controls
                    .padding(.horizontal, Spacing.lg)
            }
        }
        .padding(.vertical, Spacing.lg)
        .navigationTitle("Sticker Lab")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $pickerSelection, maxSelectionCount: 16, matching: .images) {
                        Text("Pick photos")
                    }
                    .disabled(isProcessing)
                }
            }
        }
        .onChange(of: pickerSelection) { _, selection in
            guard !selection.isEmpty else { return }
            Task { await load(selection) }
        }
    }

    @ViewBuilder private var content: some View {
        if items.isEmpty {
            emptyPrompt
        } else {
            grid
        }
    }

    private var emptyPrompt: some View {
        PhotosPicker(selection: $pickerSelection, maxSelectionCount: 16, matching: .images) {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.avoraLargeTitle)
                Text("Pick photos to make stickers")
                    .font(.avoraFootnote)
                    .foregroundStyle(Color.avoraTextTertiary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.sm) {
                ForEach($items) { $item in
                    StickerCell(item: item) { save(item) }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
        }
    }

    @ViewBuilder private var controls: some View {
        AvoraPrimaryButton { Haptics.tap(); saveAll() } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "square.and.arrow.down")
                Text("Save All to Photos")
            }
        }
        .disabled(isProcessing || !hasUnsaved)
    }

    // Implemented in later tasks.
    private func load(_ selection: [PhotosPickerItem]) async {}
    private func save(_ item: StickerItem) {}
    private func saveAll() {}
}
```

Note: `StickerCell` is added in Task 2. To keep this task compiling on its own, add a minimal placeholder cell now (it will be fleshed out in Task 2):

```swift
private struct StickerCell: View {
    let item: StickerLabView.StickerItem
    let onSave: () -> Void
    var body: some View {
        Image(uiImage: item.source)
            .resizable().scaledToFit()
    }
}
```

Place `StickerCell` between `StickerLabView` and `Checkerboard`.

- [ ] **Step 2: Verify it compiles**

Run the build/verify command. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Avora/Views/Create/StickerLabView.swift
git commit -m "feat: multi-select state and grid scaffold for sticker lab"
```

---

### Task 2: Load photos, process with bounded concurrency, render cell states

Load each picked photo into a `StickerItem`, run all through `StickerProcessor` at most 3 at a time, and render each cell's processing / done / failed state over the checkerboard.

**Files:**
- Modify: `Avora/Views/Create/StickerLabView.swift` (`load` method and `StickerCell`).

**Interfaces:**
- Consumes: `StickerItem`, `items` (from Task 1); `StickerProcessor.makeSticker(from:)`; `Checkerboard`.
- Produces: fully populated `items` with `.done`/`.failed` statuses that Task 3's save logic reads.

- [ ] **Step 1: Implement `load` with bounded concurrency**

Replace the placeholder `load` from Task 1 with:

```swift
/// Loads each picked photo, then runs stickers at most 3 at a time so 16
/// simultaneous Vision + Core Image passes don't spike memory. Selection order
/// is preserved for display.
private func load(_ selection: [PhotosPickerItem]) async {
    var loaded: [StickerItem] = []
    for pick in selection {
        if let data = try? await pick.loadTransferable(type: Data.self),
           let img = UIImage(data: data) {
            loaded.append(StickerItem(source: img))
        }
    }
    items = loaded
    pickerSelection = []

    var firstSuccess = true
    await withTaskGroup(of: (UUID, UIImage?).self) { group in
        var next = 0
        let maxInFlight = 3

        func addTask(_ index: Int) {
            let item = loaded[index]
            group.addTask { (item.id, await StickerProcessor.makeSticker(from: item.source)) }
        }

        while next < loaded.count && next < maxInFlight {
            addTask(next); next += 1
        }
        for await (id, sticker) in group {
            if let idx = items.firstIndex(where: { $0.id == id }) {
                if let sticker {
                    items[idx].result = sticker
                    items[idx].status = .done
                    if firstSuccess { Haptics.success(); firstSuccess = false }
                } else {
                    items[idx].status = .failed
                }
            }
            if next < loaded.count { addTask(next); next += 1 }
        }
    }
}
```

- [ ] **Step 2: Flesh out `StickerCell` with the three states**

Replace the placeholder `StickerCell` from Task 1 with:

```swift
/// One grid cell: sticker over checkerboard when done, source + spinner while
/// processing, or an inline mark when no subject was found. Tapping a done cell saves it.
private struct StickerCell: View {
    let item: StickerLabView.StickerItem
    let onSave: () -> Void

    var body: some View {
        ZStack {
            Checkerboard()
            switch item.status {
            case .processing:
                Image(uiImage: item.source)
                    .resizable().scaledToFit()
                    .opacity(0.4)
                    .overlay { ProgressView() }
            case .done:
                if let result = item.result {
                    Image(uiImage: result)
                        .resizable().scaledToFit()
                        .padding(Spacing.xs)
                }
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .font(.avoraFootnote)
                    .foregroundStyle(Color.avoraError)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if item.saved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.avoraSuccess)
                    .padding(Spacing.xs)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if item.status == .done && !item.saved { onSave() } }
    }
}
```

Note: confirm `Color.avoraSuccess` exists; if the codebase uses a different success token, substitute the matching one. Check with:

```bash
grep -rn "avoraSuccess\|avoraError" Avora/ | head
```
If `avoraSuccess` is absent, use `Color.green` or the nearest existing positive token found by the grep.

- [ ] **Step 3: Verify it compiles**

Run the build/verify command. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Avora/Views/Create/StickerLabView.swift
git commit -m "feat: load and process sticker photos with bounded concurrency"
```

---

### Task 3: Save (per-item + Save All) with toast

Implement single-sticker save and bulk save, marking items `saved` and reporting a count via toast.

**Files:**
- Modify: `Avora/Views/Create/StickerLabView.swift` (`save` and `saveAll` methods).

**Interfaces:**
- Consumes: `items`, `StickerItem` (Tasks 1–2); `ToastWindowManager.shared.show(title:)`; `Haptics`.
- Produces: final behavior; no downstream consumers.

- [ ] **Step 1: Implement `save` (single) and `saveAll`**

Replace the placeholder `save`/`saveAll` from Task 1 with:

```swift
/// Saves one sticker and marks it saved.
private func save(_ item: StickerItem) {
    guard let result = item.result,
          let idx = items.firstIndex(where: { $0.id == item.id }),
          !items[idx].saved else { return }
    UIImageWriteToSavedPhotosAlbum(result, nil, nil, nil)
    items[idx].saved = true
    Haptics.success()
    ToastWindowManager.shared.show(title: "Saved to Photos")
}

/// Saves every finished sticker not yet saved and reports the count.
private func saveAll() {
    let pending = items.indices.filter { items[$0].status == .done && !items[$0].saved }
    guard !pending.isEmpty else { return }
    for idx in pending {
        if let result = items[idx].result {
            UIImageWriteToSavedPhotosAlbum(result, nil, nil, nil)
            items[idx].saved = true
        }
    }
    let count = pending.count
    ToastWindowManager.shared.show(title: count == 1 ? "Saved 1 sticker to Photos" : "Saved \(count) stickers to Photos")
}
```

- [ ] **Step 2: Verify it compiles**

Run the build/verify command. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Avora/Views/Create/StickerLabView.swift
git commit -m "feat: bulk and per-sticker save in sticker lab"
```

---

## Self-Review Notes

- **Spec coverage:** state model (Task 1), 3-col grid + empty state + toolbar (Task 1), per-item states over checkerboard (Task 2), bounded concurrency 3 + selection order (Task 2), Save All disabled/count + per-item tap save + saved checkmark (Tasks 1–3), unreadable-photo skipped (Task 2 `load`). No large single-preview special case — matches "out of scope."
- **Placeholders:** each task shows complete code; the Task 1 placeholder `StickerCell`/methods are intentional compiling stubs, each replaced in a named later step.
- **Type consistency:** `StickerItem`, `status`/`.processing`/`.done`/`.failed`, `result`, `saved`, `items`, `pickerSelection`, `save(_:)`, `saveAll()`, `load(_:)` used consistently across tasks. `StickerCell(item:onSave:)` signature stable between Task 1 stub and Task 2.
- **Token verification:** Task 2 Step 2 includes a grep to confirm `avoraSuccess`/`avoraError` before relying on them.
