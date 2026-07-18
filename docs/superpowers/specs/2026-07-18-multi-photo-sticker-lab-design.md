# Multi-photo Sticker Lab — Design

**Date:** 2026-07-18
**Status:** Approved

## Goal

Let the Sticker Lab process multiple photos at once. The user picks up to 16
photos, each is turned into a die-cut sticker on-device, and results appear in a
grid. Saving works both in bulk ("Save All to Photos") and per-sticker (tap one
to save just that one).

## Scope

- **Change:** `Avora/Views/Create/StickerLabView.swift` — replace the single-photo
  flow with a multi-select grid flow.
- **Unchanged:** `Avora/Services/StickerProcessor.swift` — it already turns one
  `UIImage` into one sticker. We call it N times; no processor changes needed.

The flow stays fully on-device: no upload, no credits, no Collection/Community.

## State model

Each picked photo tracks its own lifecycle, so one failure or slow photo does not
block the others.

```swift
struct StickerItem: Identifiable {
    let id = UUID()
    let source: UIImage
    var result: UIImage?          // nil until processing succeeds
    var status: Status            // .processing, .done, .failed
    var saved: Bool = false

    enum Status { case processing, done, failed }
}
```

View state:

- `@State private var items: [StickerItem]` — display + processing order = selection order.
- `@State private var pickerSelection: [PhotosPickerItem]` — bound to a
  `PhotosPicker(maxSelectionCount: 16, matching: .images)`.

## Layout

- **Empty state:** the existing centered prompt, reworded to "Pick photos to make
  stickers" (plural). Tapping it opens the picker.
- **With photos:** a `LazyVGrid` of **3 columns**. Each cell is a rounded tile with:
  - checkerboard background (existing `Checkerboard` view), and
  - the sticker (`.done`), or the source image dimmed with a `ProgressView`
    (`.processing`), or an inline "no subject" mark (`.failed`).
  - A tap on a `.done` cell saves that single sticker; a checkmark overlay
    confirms `saved`.
- **Toolbar:** keep a "Pick photos" button (top trailing) to start a new selection,
  disabled while any item is processing.

## Controls

The bottom `AvoraPrimaryButton` becomes **"Save All to Photos"**:

- Saves every `.done` sticker that is not already `saved`.
- Disabled while any item is still `.processing`, or when there is nothing left to
  save (no unsaved `.done` items).
- On completion, a toast reports the count (e.g. "Saved 12 stickers to Photos").

## Processing

On a new selection:

1. Load each `PhotosPickerItem` to a `UIImage`; build `items` with status
   `.processing`.
2. Run the photos through `StickerProcessor.makeSticker` with **bounded
   concurrency of 3** (a `TaskGroup` that keeps at most 3 in flight). This avoids
   16 simultaneous Vision + Core Image passes spiking memory.
3. As each finishes, update that item on the main actor: `.done` with `result`, or
   `.failed`.

Haptics: success when the first sticker completes / on save; error only if an
item fails (kept subtle — no per-item spam).

## Error handling

- Per-item and isolated: a failed photo shows an inline mark in its own cell and is
  skipped by "Save All". Other photos are unaffected.
- A photo that fails to load (unreadable `Data`) is simply not added to `items`.

## Out of scope

- No large single-photo preview when exactly one photo is picked (a 1-photo
  selection shows a 1-item grid).
- No reordering, deletion of individual picked photos, or re-processing a single
  failed item (user re-picks to retry).
- No changes to `StickerProcessor`.

## Success criteria

- Picking 1–16 photos produces a grid where each cell independently shows
  processing → done/failed.
- "Save All" saves exactly the unsaved successful stickers and reports the count.
- Tapping a done sticker saves only that one and marks it saved.
- Project compiles cleanly (build check only; user verifies UI manually).
