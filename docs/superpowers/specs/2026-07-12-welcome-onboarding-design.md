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

## 3. Slides

| # | Title | Subtitle | Visual |
|---|---|---|---|
| 1 | Turn your photos into art | Pick a style and Avora restyles your photo with AI. | Before→after hero pair |
| 2 | Pick a style, add your photo | Tap any style, choose a photo, and we do the rest. | Style tile + photo glyph → result |
| 3 | Ready to create | Your first credits are on us. | App's 3D icon + "Get Started" CTA |

- Primary button: **"Next"** on slides 1–2, **"Get Started"** on slide 3.
- **"Skip"** control in the top corner (dismisses immediately, same as finishing).
- Page-dot indicator.

## 4. Architecture

### New file
- `Avora/Views/WelcomeView.swift`
  - Paged `TabView` (`.page` index style) over a local `[WelcomeSlide]` array
    (`image`/`title`/`subtitle`).
  - Styled with existing design tokens: `.avoraBody`, `Spacing`, `avoraGlass`,
    `LinearGradient.avoraBackgroundGradient`.
  - Dismiss callback fired by both "Get Started" and "Skip".
  - Keep under the 200-line file limit; slide data + a small `WelcomeSlide`
    struct live in the same file.

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
