# Design System (Dark-Only) — Design Spec

**Date:** 2026-06-29
**App:** Avora (SwiftUI, iOS)
**Status:** Approved design, pending implementation plan
**Builds on:** [Typography system](2026-06-29-typography-system-design.md) (already shipped — `Font.avora*` tokens in `Avora/DesignSystem/`)

## Goal

Add a color/spacing/radius design system to Avora and lock the app to dark mode. The visual direction is **"Graphite Glass"** — a near-monochrome, image-forward dark palette with premium depth (subtle gradients, soft shadows, edge highlights), using Apple's native **Liquid Glass** on the floating control layer where the platform supports it.

## Decisions (locked)

| Decision | Choice |
|----------|--------|
| Token scope | Colors + spacing + radius (typography already done) |
| Palette | Neutral Gallery base — near-black neutrals, near-white text/action; UI recedes so generated images carry color |
| Premium treatment | Gradients + soft shadows + 1px edge highlights; "Graphite Glass" |
| Glass strategy | Native Liquid Glass on the control/chrome layer; solid graphite surfaces for content |
| Deployment target | Keep **iOS 18.0**; native glass on iOS 26+, manual fallback on 18–25 |
| Appearance | Dark mode only |
| Migration | Full — replace ad-hoc colors and cornerRadius/padding literals app-wide |

## Where Liquid Glass applies

Per Apple HIG, Liquid Glass belongs on the floating control/chrome layer, not on content.

- **Native glass (iOS 26+), with `.ultraThinMaterial` + hairline + shadow fallback on 18–25:**
  primary buttons (`Generate`, `Sign in with Apple`), the "Generating…" progress overlay, and sheet backgrounds (Paywall).
- **Graphite elevated surfaces (all iOS versions, solid — not glass):**
  style cards, the credit/stats bar. Solid `avoraSurface` with a subtle gradient, a 1px top highlight, and a soft shadow — kept solid so they don't compete with generated imagery and stay legible.

## Color tokens (`Avora/DesignSystem/Colors.swift`)

Dark-only, so values are fixed (no light variants). Delivered as a `Color` extension matching the `Font.avora*` pattern, with a private hex initializer.

| Token | Hex | Role |
|-------|-----|------|
| `avoraBackground` | `0x0A0A0B` | App canvas base |
| `avoraSurface` | `0x161618` | Content surfaces (cards, rows) |
| `avoraSurfaceElevated` | `0x212124` | Higher elevation (raised controls) |
| `avoraTextPrimary` | `0xFAFAFA` | Primary text |
| `avoraTextSecondary` | `0x9A9AA0` | Secondary text |
| `avoraTextTertiary` | `0x5E5E64` | Placeholders, disabled, tertiary |
| `avoraBorder` | `0x29292E` | Hairline borders, separators |
| `avoraBorderHighlight` | white @ 6% | 1px top-edge highlight on elevated surfaces |
| `avoraAccent` | `0xFAFAFA` | Action color (fallback button fill, tint) |
| `avoraError` | `0xE5564B` | Error text/state |
| `avoraSuccess` | `0x4FB286` | Success (purchase confirmation) |

`onAccent` (text on the white action color) is `avoraBackground`.

### Gradients (`Colors.swift`)

| Token | Stops (top → bottom) | Use |
|-------|----------------------|-----|
| `avoraBackgroundGradient` | `0x121215 → 0x0B0B0D` | App canvas, applied once at root |
| `avoraSurfaceGradient` | `0x1C1C20 → 0x151517` | Elevated content surfaces |

## Spacing & radius (`Avora/DesignSystem/Layout.swift`)

```swift
enum Spacing { // CGFloat
    static let xs: CGFloat = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32
}
enum Radius {  // CGFloat
    static let sm: CGFloat = 8, md = 12, lg = 16, xl = 20
}
```

Existing literals normalize onto the scale: thumbnail `10 → Radius.sm`, progress overlay `12 → Radius.md`, style card `14 → Radius.md`, preview `16 → Radius.lg`. Login's capsule button stays a capsule.

## Surface & glass API (`Avora/DesignSystem/Surfaces.swift`)

Centralizes the iOS-26 availability branch so views never write `if #available` for glass.

```swift
extension View {
    /// Native Liquid Glass on iOS 26+, `.ultraThinMaterial` + hairline + shadow on 18–25.
    func avoraGlass(in shape: some Shape) -> some View

    /// Solid graphite surface: surface gradient + 1px top highlight + soft shadow. All iOS versions.
    func avoraElevatedSurface(cornerRadius: CGFloat) -> some View
}

/// Primary action button: Liquid Glass prominent on iOS 26+, white-gradient fill on 18–25.
struct AvoraPrimaryButtonStyle: ButtonStyle { /* … */ }
```

Soft-shadow spec used by `avoraElevatedSurface`: black at ~50% opacity, radius ~16, y-offset ~8 — paired with the `avoraBorderHighlight` top edge.

## Dark-mode lock (three layers)

1. `INFOPLIST_KEY_UIUserInterfaceStyle = Dark` — set via the `xcodeproj` gem on Debug + Release. (This key *is* synthesized by `GENERATE_INFOPLIST_FILE`, unlike `UIAppFonts`.)
2. `.preferredColorScheme(.dark)` on the root `ContentView`.
3. `AccentColor.colorset` set to `#FAFAFA` (single dark-appearance value) so any unmigrated system control tint matches.

## File structure

**New:**
- `Avora/DesignSystem/Colors.swift` — color tokens + gradients + hex initializer
- `Avora/DesignSystem/Layout.swift` — `Spacing` + `Radius`
- `Avora/DesignSystem/Surfaces.swift` — `avoraGlass`, `avoraElevatedSurface`, `AvoraPrimaryButtonStyle` (the one place iOS-26 availability is branched)

**Modify:**
- `Avora.xcodeproj/project.pbxproj` — `INFOPLIST_KEY_UIUserInterfaceStyle = Dark` (via `xcodeproj` gem)
- `Avora/Assets.xcassets/AccentColor.colorset/Contents.json` — `#FAFAFA`
- `Avora/ContentView.swift` — `avoraBackgroundGradient` canvas + `.preferredColorScheme(.dark)`
- `Avora/LoginView.swift` — primary button → `AvoraPrimaryButtonStyle`; keep black-over-image treatment
- `Avora/Views/Home/StylesGridView.swift` — credit bar + style cards → tokens + `avoraElevatedSurface`
- `Avora/Views/Collection/CollectionView.swift` — thumbnails → surface tokens + radius
- `Avora/Views/Create/CreateView.swift` — preview/overlay → tokens; "Generating…" overlay → `avoraGlass`; buttons → token styles; error → `avoraError`
- `Avora/Views/Paywall/PaywallView.swift` — sheet/rows → tokens; price/title already tokenized for type
- `Avora/Views/RemoteImage.swift` — placeholder → surface/text tokens

## Migration notes (the careful bits)

- `.secondary` foreground → `avoraTextSecondary`; `.red` → `avoraError`.
- Existing `.ultraThinMaterial` over imagery (login button, generating overlay) is replaced by `avoraGlass` (which itself falls back to material on 18–25) — preserving the blur where it overlays images.
- `.borderedProminent` / `.bordered` buttons in CreateView/Paywall are restyled to token-based styles so they stop defaulting to system blue.
- Login screen keeps its intentional black-over-photo background; only its button style/token changes.

## Success criteria

- App launches locked in dark mode regardless of the device's system appearance setting.
- No ad-hoc colors remain in views (`.secondary`, `.red`, `Color.black` as a surface, raw materials for non-image surfaces); all use `avora*` tokens. (Login's image background excepted.)
- No raw `cornerRadius:`/padding magic numbers remain in migrated views; they use `Radius`/`Spacing`.
- On iOS 26 simulator: primary buttons, the generating overlay, and the Paywall sheet render with native Liquid Glass; content cards render as solid graphite surfaces with visible depth (gradient + highlight + shadow).
- On an iOS 18–25 simulator: the same surfaces render via the material/shadow fallback with no visual breakage and no availability crashes.
- App builds with no warnings; the existing font audit still passes.

## Out of scope (YAGNI)

- Light mode and any light-variant color values.
- A warning semantic color (nothing uses it).
- Reusable component library beyond the three surface/button helpers (no generic card/list-row components yet).
- Glass on content cards (kept solid by design for image legibility).
