# Style Card Pill Tag — Design

**Date:** 2026-06-30
**Status:** Approved, pending implementation plan

## Goal

Show a small curated pill tag (e.g. "Hot 🔥", "Trending 🔥", "Popular 🔥") on
the top-right corner of style cards in the styles grid, to draw attention to
selected styles.

## Decisions

| Question | Decision |
|----------|----------|
| What decides a tag? | **Manually curated** — backend assigns per style |
| How is it modeled? | **Free-form text** — backend sends a `badgeText` string, app renders it verbatim |
| Color / treatment? | **Single fixed style** for all tags |
| Visual style | **Light chip** (style D): soft pill, adapts to light/dark via design tokens |
| Dark mode | **Adaptive** — light chip + dark text in light mode; flips to dark chip + light text in dark mode |

## Data Model

Add one optional field to `Avora/Models/Style.swift`:

```swift
struct Style: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let sampleImagePath: String?
    let active: Bool
    let sortOrder: Int
    let badgeText: String?   // e.g. "Hot 🔥"; nil/absent = no pill
}
```

- Optional, so existing API responses without the key still decode (synthesized
  `Codable` maps a missing key to `nil`).
- No enum, no color field — backend owns the full string.

## Rendering

In `Avora/Views/Home/StylesGridView.swift`, the pill overlays the **image
tile** (not the whole card), so the label below stays untouched.

- Placement: `.overlay(alignment: .topTrailing)` on the tile, inset 8pt from the
  top and trailing edges.
- Visibility: only render when `badgeText` is non-nil **and** non-empty after
  trimming whitespace. Blank strings produce no chip.
- `.allowsHitTesting(false)` on the pill so it never intercepts the card's
  navigation tap.

## The Pill — `StyleBadge`

A small private view (kept in `StylesGridView.swift`; file stays well under
200 lines):

| Property | Value |
|----------|-------|
| Text | `badgeText` |
| Font | `.avoraCaption2` (11pt) |
| Padding | ~7pt horizontal, ~4pt vertical |
| Shape | `Capsule()` |
| Background | `.avoraSurface` (adaptive) |
| Text color | `.avoraTextPrimary` (adaptive) |
| Border | hairline `.avoraBorderHighlight` |
| Shadow | `black.opacity(0.12)`, radius 3, y 1 — keeps the chip legible over bright/light thumbnails |

## Out of Scope

- No data-driven / computed tags (manual curation only).
- No per-tag color or backend-controlled styling.
- No animation / appearance transition.
- No changes to the style label, grid layout, or tap behavior.

## Success Criteria

- A style with `badgeText: "Hot 🔥"` shows a legible pill at the card's
  top-right in both light and dark mode.
- A style with `badgeText: nil` or `""` shows no pill and looks identical to
  today.
- Tapping anywhere on the card (including over the pill) still navigates to the
  create screen.
- Existing style API responses (no `badgeText` key) decode without error.
