# Pixelate → Sharpen Generation Reveal

**Date:** 2026-07-02
**Status:** Approved (design)
**Area:** `Avora/Views/Create/CreateView.swift` generation animation

## Summary

Replace the `SparkleDrift` overlay shown during image generation with a
pixelation effect. The source photo dissolves into blocks while the job runs,
holds (with a gentle pulse) through the result download, then the finished
result **sharpens into focus** from that same blockiness. This reads as one
continuous "your photo developing into the result" motion, and removes the
current spinner that appears while a finished result is still downloading.

## Motivation

Current behaviour (`slotCard` in `CreateView.swift`):
- `SparkleDrift` twinkles over the source photo during `.working` / `isSubmitting`.
- On `.done(path)` the card **immediately** swaps to `RemoteImage`, which shows a
  `ProgressView` spinner while the result downloads, then pops the image in with
  no transition.

Two rough edges: the sparkles are generic, and there is a spinner + hard pop
between "job finished" and "image on screen". The pixelate → sharpen reveal
replaces both with a single cohesive effect.

## Visual Lifecycle (per card)

Each photo card runs this independently (batch generation animates each card on
its own timeline).

1. **Idle** — photo picked, before Generate is tapped: source shown sharp.
2. **Generating** — `isSubmitting` or phase `.working`: block size ramps from
   sharp → max over ~2.5s, then **pulses** gently at max to signal ongoing work.
3. **Result ready, downloading** — phase `.done(path)`, result not yet fetched:
   stays on the pixelated source at max block + pulse. No spinner.
4. **Reveal** — result finished downloading: the result appears at the *same*
   max block size (quick ~0.25s cross-fade beneath the blocks so there is no
   content pop), then block size animates max → sharp over ~0.6s. Pulse stops.
5. **Failed** — phase `.failed`: unchanged. Source photo with the existing
   warning badge. No pixelation.

Approved animation choices:
- **Timing:** ramp to max, then subtle pulse (not asymptotic, not oscillating
  back to sharp).
- **Reveal:** sharpen into focus — result starts at the source's max block size
  and un-pixelates. Not a plain cross-fade.

## Components

### `PixelShader.metal` (new)

A single `[[ stitchable ]]` function usable via SwiftUI `.layerEffect`:

```metal
#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

[[ stitchable ]] half4 pixellate(float2 position,
                                 SwiftUI::Layer layer,
                                 float size) {
    if (size <= 1) { return layer.sample(position); }   // passthrough = sharp
    float2 snapped = floor(position / size) * size + size * 0.5;
    return layer.sample(snapped);
}
```

`size` is the block edge length in points. `size <= 1` renders the layer sharp,
so the same shader covers both the pixelated and resolved ends of the animation.

Added to the `Avora` app target as a normal `.metal` source (Xcode's default
Metal build phase compiles it into `default.metallib`; `ShaderLibrary` resolves
`pixellate` by name at runtime).

### `PixelReveal.swift` (new — replaces `SparkleDrift`)

One self-contained card view that owns the whole visual lifecycle above.

```
struct PixelReveal: View {
    let source: UIImage
    let resultPath: String?     // non-nil once the job phase is .done
    let isGenerating: Bool      // true during isSubmitting / .working
}
```

Responsibilities:
- Render the current image (source until the result loads, then the result),
  clipped to the same rounded card shape used elsewhere, with
  `.layerEffect(ShaderLibrary.pixellate(.float(blockSize)), maxSampleOffset:)`
  applied. `maxSampleOffset` covers the max block size.
- Own `@State private var blockSize` and drive it:
  - **Ramp:** when generating starts, animate `blockSize` 1 → max over ~2.5s
    using `withAnimation(_:completion:)`; on completion start the pulse.
  - **Pulse:** animate a small block-size delta at max with
    `.repeatForever(autoreverses: true)`.
  - **Sharpen:** when the result finishes loading, stop the pulse and animate
    `blockSize` max → 1 over ~0.6s.
- Load the result through `ImageStore` when `resultPath` becomes non-nil,
  mirroring the existing `RemoteImage` pattern
  (`ImageStore.shared.image(for:source:)`). While loading, keep the source at
  max block. On load, cross-fade the result in beneath the blocks (~0.25s) to
  avoid a content pop, then run the sharpen.

Tuning constants (starting values, adjustable during implementation):
`maxBlock ≈ 24pt`, ramp `2.5s`, pulse delta `±4pt` / period `~1.2s`, reveal
cross-fade `0.25s`, sharpen `0.6s`.

### `CreateView.slotCard` (edit)

Collapse the `.working`, `.done`, and `nil`+`isSubmitting` branches into a
**single** `PixelReveal`, keeping `.failed` as its own branch:

```
@ViewBuilder private func slotCard(_ index: Int) -> some View {
    let phase = poller.items.indices.contains(index) ? poller.items[index].phase : nil
    if case .failed = phase {
        // unchanged: source photo + warning badge
    } else {
        let resultPath: String? = { if case .done(let p) = phase { return p } else { return nil } }()
        let isGenerating = isSubmitting || phase == .working
        PixelReveal(source: sourceImages[index], resultPath: resultPath, isGenerating: isGenerating)
    }
}
```

**Why one view, not a switch:** rendering a *single* `PixelReveal` instance
across the working → done transition (rather than switching between different
view types per phase) keeps SwiftUI view identity stable, so the internal
`blockSize` state persists. That continuity is what makes the reveal sharpen
out of the held pixelation instead of resetting. Idle (not generating, no
result) renders the source sharp through the same view, maximising identity
stability.

## Orphaned Code

`Avora/Views/SparkleDrift.swift` becomes fully unused once `slotCard` switches
to `PixelReveal`. These changes make it dead code, so it is **deleted** as part
of this work (both the file and the two call sites in `slotCard`).

## Out of Scope / Not Changing

- `BatchGenerationPoller` and all poll / phase logic.
- Billing, upload, submit, save-all, reset flows.
- `RemoteImage` (still used for `.done` display elsewhere and as the loader
  pattern reference).
- Failed-state UX (warning badge over source).
- Card layout, framing, stacked-deck / strip behaviour.

## Alternatives Considered

- **Downsample `UIImage` + `.interpolation(.none)` scaling** — no Metal file,
  but re-rasterizes per step and animates in visible discrete jumps. Rejected:
  the shader animates one GPU uniform smoothly for ramp, pulse, and sharpen.
- **Core Image `CIPixellate` per frame** — heavier and not smoothly animatable
  through SwiftUI. Rejected for the same reason.

## Success Criteria

- Tapping Generate pixelates each source card (ramp → pulse), no sparkles.
- No spinner appears between job completion and the image showing.
- The finished result sharpens into focus from the held block size, per card.
- Failed cards show the existing warning badge, un-pixelated.
- Batch: each card animates on its own timeline.
- `SparkleDrift.swift` removed; project builds clean with no unused references.
