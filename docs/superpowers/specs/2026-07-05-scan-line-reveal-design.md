# Scan-Line Reveal — Design

**Date:** 2026-07-05
**Status:** Approved, ready for implementation plan
**Component:** `Avora/Views/FocusReveal.swift` → `Avora/Views/ScanReveal.swift`
**Call site:** `Avora/Views/Create/CreateView.swift` (`slotCard`)

## Problem

The current generation animation in `CreateView` uses a blur-based effect
(`FocusReveal`): the source photo eases from sharp into a 16pt blur over 12s,
breathes near max blur while waiting, then pulls the downloaded result back into
focus. It works, but reads as too plain/generic — it doesn't feel like an Avora
signature moment.

## Goal

Replace the blur with a **scan-line reveal**: no blur at all. While generating,
a thin glowing accent line sweeps top→bottom on a loop over the sharp source
photo (an "AI is analyzing your photo" beat). When the result is ready, a single
top→bottom sweep acts as a **wipe** — everything above the line shows the
finished result, everything below still shows the source — unveiling the new
image row by row.

## Approach

Rewrite the view in place, renaming for clarity:

- `FocusReveal.swift` → `ScanReveal.swift`, struct `FocusReveal` → `ScanReveal`.
- The initializer interface is unchanged: `(source: UIImage, resultPath: String?,
  isGenerating: Bool)`. The only other change is the one call site in
  `CreateView.slotCard`, which swaps `FocusReveal(...)` for `ScanReveal(...)`.
- File rename is safe: the project uses Xcode synchronized folders, so no
  `.pbxproj` edits are required.

## Component structure

```
ScanReveal (ZStack, clipped to RoundedRectangle(cornerRadius: Radius.lg))
├── sourceImage        // always visible, sharp, aspect-fit, fills card
├── resultImage        // masked: visible only ABOVE the line (top → progress·H)
└── scanLine overlay   // glowing accent line at the current Y
```

- **Result mask:** the result layer uses `.mask` with a top-anchored rectangle of
  height `progress · cardHeight`. `progress` 0→1 maps to line-at-top →
  line-at-bottom, i.e. result unveiled top→bottom. Card height comes from a
  `GeometryReader`.
- **Scan line:** a ~2.5pt `Capsule` filled with `Color.avoraAccent`, plus a
  blurred duplicate behind it (blur ~8pt) for the soft glow. Positioned with
  `offset(y:)` driven by the active line position.
- The looping decorative line and the reveal sweep are **separate motions**. When
  the result lands, the looping line is dropped and one clean top→bottom reveal
  sweep runs from the top (a fresh full sweep reads more clearly as "here's your
  result" than continuing from a random loop position).

## States & motion

| State | Source | Result mask | Line |
|---|---|---|---|
| Generating (`resultImage == nil`) | sharp | hidden | loops top→bottom, ~1.8s/pass, repeating |
| Revealing (result downloaded) | sharp (under mask) | grows top→bottom | leads the wipe, one sweep ~1.2s |
| Done | — | fully shown | faded out |
| Download failed | sharp | hidden | fades out, no reveal |

- **Start scanning:** on appear if `isGenerating`, and when `isGenerating`
  transitions to true (mirrors the current `onAppear` / `onChange(of:)` triggers).
- **Reveal trigger:** `.task(id: resultPath)` downloads the result image via
  `ImageStore.shared.image(for:)`, sets `resultImage`, then runs the reveal sweep.
- **Keep looping until reveal:** the scan loop continues while `resultImage ==
  nil`, so if `isGenerating` flips false before the download finishes, the line
  keeps sweeping until the image is actually ready to reveal.

## Timing / tunable params

Declared as named constants at the top of the struct (like the current
`maxBlur` / `pulseDip`), so they're easy to tweak:

- Loop sweep: **1.8s** per pass, `linear`, `repeatForever(autoreverses: false)`
- Reveal sweep: **1.2s**, `easeInOut`
- Line thickness: **2.5pt**
- Glow blur: **8pt**
- Line color: `Color.avoraAccent`

## Edge cases

- **Failed generation:** unchanged. The refunded/error badge in
  `CreateView.slotCard` short-circuits (the `if case .failed` branch) before
  `ScanReveal` is ever constructed.
- **Result download fails:** the scan line fades out and the source stays sharp —
  the same graceful fallback the current `revealResult()` catch block provides.
- **Multiple photos:** each card owns its own `ScanReveal`, so lines sweep
  independently per card. No cross-card coordination.
- **Line over letterboxing:** the source is aspect-fit within the card, so a
  photo whose ratio differs from the card leaves transparent margins. The scan
  overlay spans the card width and is clipped to the same rounded rect. Photos
  generally fill most of the card, so this is acceptable; revisit only if the
  line over margin areas looks wrong in practice.

## Out of scope

- No change to `CreateView` layout, controls, polling, or the failed-state badge.
- No change to `BatchGenerationPoller` or the generation/download pipeline.
- No shader work — this is pure SwiftUI (Capsule + mask + blur-for-glow).
```
