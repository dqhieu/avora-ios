# Avora — First-Run Welcome Onboarding Design

**Date:** 2026-07-12
**Status:** Approved design, ready for implementation planning
**Scope:** iOS app only. No backend/Supabase changes.

---

## 1. Problem

New users land on the **Styles grid** (Create tab) with no explanation of what
the app does or how to start. First-time observation: a non-technical user
didn't understand (a) *what* Avora is for — that it turns **her own photos**
into styled art — nor (b) *how to start* — tap a style, then pick a photo. The
grid reads like a gallery, not a starting point.

Confirmed gap: **both** value/concept and mechanics.

## 2. Solution

A short, one-time **welcome carousel** shown on first authenticated launch. It
explains the value and the first move, then releases the user into the normal
Styles grid. "Explain, then release" — no interactive coach marks, no forced
guided generation.

### Decisions log

| Decision | Choice | Notes |
|---|---|---|
| Onboarding style | 3-slide welcome carousel | "Explain, then release" |
| Interactivity | Passive slides, then drop into app | No coach marks / guided flow |
| Trigger | First authenticated launch | Before the signup-bonus modal |
| Persistence | `@AppStorage("hasSeenWelcome")` | Device-local; no server/profile change |
| Sequencing | Welcome → signup-bonus modal → grid | Gate bonus behind `hasSeenWelcome` |
| Presentation | `.fullScreenCover` over `RootTabView` | |
| Re-show from Settings | "Show Intro Again" row | Resets `hasSeenWelcome`, re-triggers carousel |
| Imagery | Bundled before→after pair, with fallback | Real assets provided later |

## 3. Slides (animated direction)

Research into the niche (Lensa, Remini, EPIK, Photoleap, Prisma) showed the
transformation *is* the onboarding: these apps **show** an animated photo→art
reveal and a living gallery of real results rather than describing the app, and
close on a success-state celebration. Avora already owns every piece to do this —
the `ScanReveal` scan-line, remote style samples, and `ConfettiView` — so the
slides are animated, not static.

| # | Title | Subtitle | Visual |
|---|---|---|---|
| 1 | Turn your photos into art | Avora restyles your photo with AI in seconds. | Hero card: crossfades through styled results with a slow zoom while the signature scan line sweeps. Opens with the bundled before→after pair when present. |
| 2 | Pick a style, add your photo | Dozens of styles — tap one, choose a photo, done. | Living gallery: 3-wide grid of real style samples that spring in with a stagger. |
| 3 | Ready to create | Your first credits are on us. | App's 3D create icon with a gentle pulse; confetti burst fires on reaching the slide. |

- Primary button: **"Next"** on slides 1–2, **"Get Started"** on slide 3.
- **"Skip"** control in the top corner (dismisses immediately, same as finishing).
- Page-dot indicator; per-slide text rises + fades in as it becomes active; page
  changes fire a selection haptic.
- Style samples come from `app.styles` (loaded on appear via `app.loadStyles()`);
  every slide has a graceful glyph/gradient fallback while images load.

## 4. Architecture

### New files
- `Avora/Views/WelcomeView.swift` — orchestrator: paged `TabView`, footer (dots +
  CTA), Skip, confetti overlay, page haptics, `slidePage`/text entrance, and the
  `WelcomeSlide` model. Loads styles on appear via `.task { app.loadStyles() }`.
- `Avora/Views/WelcomeSlides.swift` — the animated artwork: `WelcomeHero`
  (scan-line + crossfade + zoom), `WelcomeStyleGallery` (staggered grid),
  `WelcomeReadyArt` (pulsing icon), and the `WelcomeFrame` enum. Imports `Combine`
  for the hero's crossfade `Timer`.
- Styled with existing design tokens (`Spacing`, `Radius`, typography, colors,
  `LinearGradient.avoraBackgroundGradient`); reuses `RemoteImage`, `ThiingIcon`,
  `ConfettiView`. Dismiss callback fired by both "Get Started" and "Skip".
- `ContentView` injects `.environment(app)` into the cover so `WelcomeView` can
  read `app.styles`.

### Modified file
- `Avora/ContentView.swift`
  - Add `@AppStorage("hasSeenWelcome") private var hasSeenWelcome = false`.
  - `showWelcome = app.isAuthenticated && !hasSeenWelcome`.
  - Present `WelcomeView` via `.fullScreenCover(isPresented:)` bound to a state
    derived from `showWelcome`; on dismiss set `hasSeenWelcome = true`.
  - Gate the existing signup-bonus overlay behind `hasSeenWelcome` so the
    carousel and the bonus modal never render at the same time:
    `showSignupBonus = hasSeenWelcome && profile?.signupBonusSeen == false && config.signupExtra > 0`.

- `Avora/Views/Settings/SettingsView.swift`
  - Add `@AppStorage("hasSeenWelcome") private var hasSeenWelcome = false`.
  - Add a **"Show Intro Again"** button (in the Restore Purchases / Sign Out
    section). On tap: `Haptics.tap()`, set `hasSeenWelcome = false`, then
    `dismiss()` the Settings sheet — the carousel re-appears over `RootTabView`
    (the signup-bonus modal stays hidden since `signupBonusSeen` is already
    true for an existing user).

### Flow

```
Login ──► isAuthenticated
             │
             ├─ hasSeenWelcome == false ──► WelcomeView (fullScreenCover)
             │                                   │ dismiss → hasSeenWelcome = true
             │                                   ▼
             └─ hasSeenWelcome == true ──► RootTabView
                                              │
                                              └─ signupBonusSeen == false ──► SignupBonusModal
                                                                                   │ dismiss
                                                                                   ▼
                                                                              Styles grid
```

## 5. Imagery

- **Slide 1 (hero):** bundle `OnboardingBefore` and `OnboardingAfter` in the
  asset catalog. **Fallback when absent:** use an existing style
  `sampleImagePath` (via `RemoteImage`) for the "after" and an SF Symbol
  (`photo`) placeholder for the "before", so the build ships before the real
  pair is delivered.
- **Slides 2 & 3:** lightweight visuals only — a mocked style tile and the app's
  existing 3D icons (`ThiingIcon`). No new assets required.

## 6. Testing / Verification

- SwiftUI `#Preview`s: each slide state and the full carousel.
- Build to confirm compilation (no simulator run — user verifies UI manually).
- Manual checks:
  1. Fresh install → Welcome carousel appears before the signup-bonus modal.
  2. Finishing (or Skip) → carousel dismisses, bonus modal shows, then grid.
  3. Relaunch → carousel does **not** reappear.
  4. Settings → "Show Intro Again" → Settings dismisses and the carousel
     re-appears (no signup-bonus modal for the existing user).

## 7. Out of scope (YAGNI)

- Interactive coach marks / guided first generation.
- Per-account server flag (device-local `AppStorage` is sufficient).
- Analytics events, extra localization.
