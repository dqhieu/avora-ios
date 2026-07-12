# Styles Custom-Prompt Floating Button — Design

**Date:** 2026-07-12
**Status:** Approved

## Summary

Replace the small "Custom" text CTA in the Styles screen's "All styles" section
header with an icon-only floating button pinned to the bottom-right. The button
opens the same custom-prompt creation flow (`CreateView` with `Style.custom`).

## Problem

The custom-prompt entry point currently lives as a low-emphasis text link in the
grid section header, easy to miss. A persistent floating button gives it a clearer,
always-visible affordance.

## Current State

- [`StylesGridView.swift`](../../../Avora/Views/Home/StylesGridView.swift) renders
  the styles grid inside a `ScrollView`.
- The `"All styles"` section header contains a trailing
  `NavigationLink(value: CreateRoute(style: .custom, placeholder: nil))` labeled
  "Custom", styled with `AvoraCustomButtonStyle` and firing `Haptics.tap()`.
- `StylesGridView` sits inside a `NavigationStack` (in `RootTabView.StylesTab`)
  that already registers `.navigationDestination(for: CreateRoute.self)`.
- The screen is one tab of a `TabView`; the standard tab bar consumes the bottom
  safe-area inset.

## Design

### Placement & structure

- Add a `.overlay(alignment: .bottomTrailing)` on the existing `ScrollView`.
- Inset the overlay by `Spacing.xl` on the trailing and bottom edges (matching the
  header's horizontal inset). The overlay respects the safe area, so the button
  floats above the tab bar and never collides with it.

### Appearance

- Icon-only **glass circle**, ~56pt diameter, using `avoraGlass(in: Circle())` —
  native Liquid Glass on iOS 26+, `.ultraThinMaterial` fallback on 18–25.
- Centered `ThiingIcon(name: "ActionGenerate", size: 28)`.
- `.accessibilityLabel("Custom prompt")` so the icon-only control stays legible to
  VoiceOver, compensating for the removed visible "Custom" label.

### Behavior

- Wrap the button in `NavigationLink(value: CreateRoute(style: .custom, placeholder: nil))`
  so it pushes the existing custom-prompt `CreateView` via the already-registered
  destination.
- Fire `Haptics.tap()` on tap via `.simultaneousGesture(TapGesture())`, matching the
  current CTA.

### Content clearance

- Add `.padding(.bottom, ~72)` to the grid content so the last row of style cards can
  scroll clear of the floating button instead of resting underneath it.

### Removing the old CTA

- Delete the "Custom" `NavigationLink` from the `"All styles"` section header, leaving
  the title + `Spacer`.
- `AvoraCustomButtonStyle` in `DesignSystem/Surfaces.swift` becomes unused. It is
  pre-existing shared design-system code — flag it, do not delete unless asked.

## Out of Scope (YAGNI)

- No scroll-collapse / expand-on-scroll animation.
- No visible text label on the button.
- No change to the custom-prompt `CreateView` flow itself.

## Success Criteria

- The floating glass button appears bottom-right on the Styles screen, above the tab bar.
- Tapping it pushes the custom-prompt `CreateView` (same as the old "Custom" CTA did).
- The old header "Custom" CTA is gone.
- The last row of style cards can scroll fully clear of the button.
- VoiceOver announces the button as "Custom prompt".
- Builds cleanly on iOS 18–26 (glass + material fallback paths compile).
