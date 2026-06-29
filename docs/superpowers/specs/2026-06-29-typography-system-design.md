# Typography System — Design Spec

**Date:** 2026-06-29
**App:** Avora (SwiftUI, iOS)
**Status:** Approved design, pending implementation plan

## Goal

Replace Avora's current all-system-font UI with a two-font typography system:

- **Cormorant Garamond** — high-contrast display serif, used for titles/headings (editorial, premium feel).
- **Bricolage Grotesque** — modern grotesque sans, used for all UI and body text (clean, legible on mobile).

The system is a complete set of semantic tokens that map to Apple's text styles, scale with Dynamic Type, and are consumed via a `Font` extension (`.font(.avoraTitle)`).

## Decisions (locked)

| Decision | Choice |
|----------|--------|
| Font roles | Serif (Cormorant) for display; Sans (Bricolage) for body/UI |
| Scope | Full semantic token set; migrate all existing views |
| Dynamic Type | Yes — every token uses `Font.custom(_:size:relativeTo:)` |
| Bundled weights | Lean curated set (7 static `.ttf` files) |
| Forward-looking extras | Hero/display tier + tabular-figure support, folded in now |

## Bundled fonts (7 static `.ttf` files)

PostScript names verified from the downloaded files; they match the filenames.

| File | PostScript name |
|------|-----------------|
| CormorantGaramond-SemiBold.ttf | `CormorantGaramond-SemiBold` |
| CormorantGaramond-Medium.ttf | `CormorantGaramond-Medium` |
| CormorantGaramond-MediumItalic.ttf | `CormorantGaramond-MediumItalic` |
| BricolageGrotesque-Regular.ttf | `BricolageGrotesque-Regular` |
| BricolageGrotesque-Medium.ttf | `BricolageGrotesque-Medium` |
| BricolageGrotesque-SemiBold.ttf | `BricolageGrotesque-SemiBold` |
| BricolageGrotesque-Bold.ttf | `BricolageGrotesque-Bold` |

Source folder: `/Users/hieudinh/Downloads/fonts/` (Cormorant statics under `Cormorant_Garamond/static/`, Bricolage statics under `Bricolage_Grotesque/static/`). Bricolage-Bold is bundled for emphasis/composition even though no base token defaults to it.

## Type scale (tokens)

The serif/sans boundary sits between `title3` and `headline`: **title3 and larger = Cormorant**, **headline and smaller = Bricolage**. `headline` is intentionally Bricolage — it is an emphasized row/section label, not a display title, so a sans keeps lists crisp.

### Display tier — Cormorant Garamond

| Token | Font | Size | `relativeTo` | Use |
|-------|------|------|--------------|-----|
| `avoraHero` | CormorantGaramond-SemiBold | 48 | `.largeTitle` | Onboarding/paywall splash headlines |
| `avoraLargeTitle` | CormorantGaramond-SemiBold | 34 | `.largeTitle` | Screen hero titles |
| `avoraTitle` | CormorantGaramond-SemiBold | 28 | `.title` | Primary screen titles |
| `avoraTitle2` | CormorantGaramond-Medium | 22 | `.title2` | Section headers |
| `avoraTitle3` | CormorantGaramond-Medium | 20 | `.title3` | Sub-section headers |
| `avoraSerifAccent` | CormorantGaramond-MediumItalic | 20 | `.title3` | Quotes, empty-state flourishes, paywall accent lines |

### UI / body tier — Bricolage Grotesque

| Token | Font | Size | `relativeTo` | Use |
|-------|------|------|--------------|-----|
| `avoraHeadline` | BricolageGrotesque-SemiBold | 17 | `.headline` | Emphasized row/list titles |
| `avoraBody` | BricolageGrotesque-Regular | 17 | `.body` | Default body text |
| `avoraCallout` | BricolageGrotesque-Regular | 16 | `.callout` | Secondary body |
| `avoraSubheadline` | BricolageGrotesque-Medium | 15 | `.subheadline` | Supporting labels |
| `avoraButton` | BricolageGrotesque-SemiBold | 17 | `.body` | Button labels |
| `avoraFootnote` | BricolageGrotesque-Regular | 13 | `.footnote` | Footnotes, helper text |
| `avoraCaption` | BricolageGrotesque-Medium | 12 | `.caption` | Captions, metadata |
| `avoraCaption2` | BricolageGrotesque-Regular | 11 | `.caption2` | Smallest metadata |

Default sizes mirror Apple's text styles so `relativeTo:` scaling behaves predictably under Dynamic Type.

## API

### `Font` extension

```swift
extension Font {
    // Display — Cormorant Garamond
    static let avoraHero       = Font.custom("CormorantGaramond-SemiBold", size: 48, relativeTo: .largeTitle)
    static let avoraLargeTitle = Font.custom("CormorantGaramond-SemiBold", size: 34, relativeTo: .largeTitle)
    static let avoraTitle      = Font.custom("CormorantGaramond-SemiBold", size: 28, relativeTo: .title)
    static let avoraTitle2     = Font.custom("CormorantGaramond-Medium",   size: 22, relativeTo: .title2)
    static let avoraTitle3     = Font.custom("CormorantGaramond-Medium",   size: 20, relativeTo: .title3)
    static let avoraSerifAccent = Font.custom("CormorantGaramond-MediumItalic", size: 20, relativeTo: .title3)

    // UI / body — Bricolage Grotesque
    static let avoraHeadline    = Font.custom("BricolageGrotesque-SemiBold", size: 17, relativeTo: .headline)
    static let avoraBody        = Font.custom("BricolageGrotesque-Regular",  size: 17, relativeTo: .body)
    static let avoraCallout     = Font.custom("BricolageGrotesque-Regular",  size: 16, relativeTo: .callout)
    static let avoraSubheadline = Font.custom("BricolageGrotesque-Medium",   size: 15, relativeTo: .subheadline)
    static let avoraButton      = Font.custom("BricolageGrotesque-SemiBold", size: 17, relativeTo: .body)
    static let avoraFootnote    = Font.custom("BricolageGrotesque-Regular",  size: 13, relativeTo: .footnote)
    static let avoraCaption     = Font.custom("BricolageGrotesque-Medium",   size: 12, relativeTo: .caption)
    static let avoraCaption2    = Font.custom("BricolageGrotesque-Regular",  size: 11, relativeTo: .caption2)
}
```

Usage: `Text("Choose a style").font(.avoraTitle)`.

### Emphasis & color — by composition, not new tokens

Do **not** add a token per weight×color combination. Use SwiftUI composition on an existing token:

```swift
Text("Subtle").font(.avoraBody).foregroundStyle(.secondary)
Text("Strong").font(.avoraBody.weight(.bold))   // resolves to BricolageGrotesque-Bold
```

### Tabular figures

Numbers that change in place (credits, prices, counts) must use tabular figures so digits don't jitter. Mechanism: `.monospacedDigit()` chained onto any token. Bricolage Grotesque supports tabular figures.

```swift
Text("\(credits) credits").font(.avoraSubheadline.monospacedDigit())
Text(price).font(.avoraTitle2.monospacedDigit())
```

Convention documented here; no extra tokens required.

## Font registration

1. Copy the 7 `.ttf` files into `Avora/Resources/Fonts/`, added to the **app target** (Target Membership checked).
2. The project uses `GENERATE_INFOPLIST_FILE = YES`, so register fonts via the `INFOPLIST_KEY_UIAppFonts` build setting — an array of the 7 filenames — added to both Debug and Release configs in `project.pbxproj`. If the build-setting array proves unreliable in practice, fall back to an explicit `Info.plist` with a `UIAppFonts` array.
3. After building, the fonts must be loadable by their PostScript names (verified above) via `Font.custom`.

## Migration

The app currently uses system fonts everywhere; only ~7 explicit `.font()` calls exist (in `LoginView`, `StylesGridView`, `CreateView`, `PaywallView`). Most `Text` uses the default body font.

1. **Root default:** apply `.font(.avoraBody)` at the top of the view tree (in `RootTabView`) so all unstyled `Text` inherits Bricolage as the default body font.
2. **Migrate explicit calls:** replace each existing `.font(.headline)`, `.font(.subheadline)`, `.font(.caption)`, etc. with the matching `avora*` token.
3. **Apply display tokens:** set Cormorant tokens on screen titles and section headers where they currently rely on default styling.

### Navigation-bar titles (known iOS constraint)

SwiftUI's `.navigationTitle` ignores `.font()`. To render Cormorant in nav-bar titles, configure `UINavigationBarAppearance` once at launch:

- `largeTitleTextAttributes[.font]` → a `UIFont` for `CormorantGaramond-SemiBold` sized for large titles.
- `titleTextAttributes[.font]` → a `UIFont` for the inline title.

This lives in a small `AppearanceConfigurator` invoked from app startup. Use `UIFontMetrics(forTextStyle:)` to keep the UIKit nav fonts Dynamic-Type-aware, consistent with the SwiftUI tokens.

## File structure

**New:**
- `Avora/Resources/Fonts/` — the 7 `.ttf` files
- `Avora/DesignSystem/Typography.swift` — the `Font` extension tokens
- `Avora/DesignSystem/AppearanceConfigurator.swift` — UIKit nav-bar appearance setup

The `DesignSystem/` folder is the namespace for future `Colors.swift` / `Spacing.swift` when the system grows beyond typography.

**Modified:**
- `Avora.xcodeproj/project.pbxproj` — add font resources to target + `INFOPLIST_KEY_UIAppFonts`
- `Avora/RootTabView.swift` (root default font) and `Avora/AvoraApp.swift` (appearance setup invocation)
- `Avora/LoginView.swift`, `Avora/Views/Home/StylesGridView.swift`, `Avora/Views/Create/CreateView.swift`, `Avora/Views/Paywall/PaywallView.swift` — migrate `.font()` calls

## Success criteria

- All 7 fonts load and render by PostScript name on a clean build (no fallback to system font).
- Every existing `.font()` call site uses an `avora*` token; default body text renders in Bricolage Grotesque.
- Titles/headings render in Cormorant Garamond, including nav-bar large titles.
- Text scales when the device Dynamic Type setting changes.
- Numbers in credits/price/count contexts use tabular figures (no horizontal jitter when values change).
- App builds and runs in the simulator with no typography-related warnings.

## Out of scope (YAGNI)

- Color, spacing, corner-radius, or other design tokens (folder is set up for them; not built now).
- Condensed/optical-size Bricolage variants and the variable fonts.
- Per-weight/per-color token proliferation (handled by composition).
