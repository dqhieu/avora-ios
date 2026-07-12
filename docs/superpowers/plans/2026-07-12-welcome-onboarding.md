# First-Run Welcome Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-time 3-slide welcome carousel on first authenticated launch that explains what Avora does and how to start, plus a Settings row to replay it.

**Architecture:** A new `WelcomeView` (paged `TabView`) is presented as a `.fullScreenCover` over `RootTabView`, gated by a device-local `@AppStorage("hasSeenWelcome")` flag. The existing signup-bonus modal is gated behind the same flag so the two never stack. A "Show Intro Again" button in Settings resets the flag to replay the carousel. No backend changes.

**Tech Stack:** SwiftUI, iOS, existing Avora design system (`Spacing`, `Radius`, typography tokens, `AvoraPrimaryButton`, `ThiingIcon`, `LinearGradient.avoraBackgroundGradient`, `Haptics`).

**Source spec:** `docs/superpowers/specs/2026-07-12-welcome-onboarding-design.md`

## Global Constraints

- **iOS app only.** No changes to `supabase/` or any backend.
- **No iOS test target exists** and the app is **never run on the simulator** (project convention). Per-task verification = the app **builds/compiles** + SwiftUI `#Preview`s render + user manual check. There is no XCTest loop.
- **Build/compile command** (compile check only — never launch):
  `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
  (Or XcodeBuildMCP `build_sim` with the `Avora` scheme.)
- **Persistence key:** `@AppStorage("hasSeenWelcome")`, default `false`. Use this exact string in every file that reads/writes it.
- **Design tokens (verbatim values):** `Spacing.xs=4, md=12, lg=16, xl=24, xxl=32`; `Radius.md=12, lg=16, xl=20`. Fonts: `.avoraTitle`, `.avoraTitle2`, `.avoraSubheadline`, `.avoraBody`. Colors: `.avoraTextPrimary`, `.avoraTextSecondary`, `.avoraSurface`, `.avoraBorderHighlight`. Background: `LinearGradient.avoraBackgroundGradient`.
- **File-size guideline:** keep new files focused; `WelcomeView.swift` should stay near ~190 lines.
- **Commit style:** conventional commits, no AI references.

---

### Task 1: WelcomeView carousel with fallback artwork

Builds the standalone carousel. It compiles and previews on its own before any wiring, so a reviewer can approve the UI in isolation. Real before→after images are provided later; this task ships **asset-free fallbacks** so the build is green now.

**Files:**
- Create: `Avora/Views/WelcomeView.swift`

**Interfaces:**
- Consumes: nothing (leaf UI). Design-system symbols listed in Global Constraints; `ThiingIcon(name:size:)`; `Haptics.tap()`, `Haptics.impact()`; `AvoraPrimaryButton(action:label:)`.
- Produces: `struct WelcomeView: View` with initializer `WelcomeView(onFinish: @escaping () -> Void)`. `onFinish` is called exactly once when the user taps **Get Started** (last slide) or **Skip**. Task 2 relies on this signature.

- [ ] **Step 1: Create `Avora/Views/WelcomeView.swift` with the full carousel**

```swift
import SwiftUI

/// One-time first-run walkthrough. Three passive slides that explain the value
/// prop and the core mechanic, then release the user into the app. Presented as
/// a full-screen cover by `ContentView`; `onFinish` is called once when the user
/// finishes the last slide or skips.
struct WelcomeView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let slides = WelcomeSlide.all

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient.avoraBackgroundGradient.ignoresSafeArea()

            TabView(selection: $page) {
                ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                    WelcomeSlideView(slide: slide).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            skipButton
        }
        .overlay(alignment: .bottom) { footer }
        .font(.avoraBody)
    }

    private var skipButton: some View {
        HStack {
            Spacer()
            Button("Skip") { Haptics.tap(); onFinish() }
                .font(.avoraSubheadline)
                .foregroundStyle(Color.avoraTextSecondary)
                .padding(Spacing.lg)
        }
    }

    private var footer: some View {
        VStack(spacing: Spacing.lg) {
            WelcomePageDots(count: slides.count, current: page)
            AvoraPrimaryButton(action: advance) {
                Text(page == slides.count - 1 ? "Get Started" : "Next")
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.xxl)
    }

    private func advance() {
        Haptics.impact()
        if page == slides.count - 1 {
            onFinish()
        } else {
            withAnimation { page += 1 }
        }
    }
}

private struct WelcomeSlide {
    enum Art { case beforeAfter, styleToPhoto, ready }
    let art: Art
    let title: String
    let subtitle: String

    static let all: [WelcomeSlide] = [
        WelcomeSlide(art: .beforeAfter,
                     title: "Turn your photos into art",
                     subtitle: "Pick a style and Avora restyles your photo with AI."),
        WelcomeSlide(art: .styleToPhoto,
                     title: "Pick a style, add your photo",
                     subtitle: "Tap any style, choose a photo, and we do the rest."),
        WelcomeSlide(art: .ready,
                     title: "Ready to create",
                     subtitle: "Your first credits are on us."),
    ]
}

private struct WelcomeSlideView: View {
    let slide: WelcomeSlide

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer(minLength: 0)
            artwork
            VStack(spacing: Spacing.md) {
                Text(slide.title)
                    .font(.avoraTitle)
                    .foregroundStyle(Color.avoraTextPrimary)
                    .multilineTextAlignment(.center)
                Text(slide.subtitle)
                    .font(.avoraSubheadline)
                    .foregroundStyle(Color.avoraTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xl)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 140) // clear the footer (dots + CTA)
    }

    @ViewBuilder
    private var artwork: some View {
        switch slide.art {
        case .beforeAfter:
            HStack(spacing: Spacing.md) {
                tile("OnboardingBefore", fallback: "photo")
                Image(systemName: "arrow.right")
                    .font(.avoraTitle2)
                    .foregroundStyle(Color.avoraTextSecondary)
                tile("OnboardingAfter", fallback: "sparkles")
            }
        case .styleToPhoto:
            HStack(spacing: Spacing.md) {
                glyphTile("square.grid.2x2")
                Image(systemName: "plus").foregroundStyle(Color.avoraTextSecondary)
                glyphTile("photo")
                Image(systemName: "arrow.right").foregroundStyle(Color.avoraTextSecondary)
                glyphTile("sparkles")
            }
        case .ready:
            ThiingIcon(name: "TabCreate", size: 112)
        }
    }

    // Before/after hero tiles. Uses the bundled asset when present; falls back to
    // an SF Symbol placeholder so the build ships before real art is delivered.
    @ViewBuilder
    private func tile(_ assetName: String, fallback symbol: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        Group {
            if UIImage(named: assetName) != nil {
                Image(assetName).resizable().scaledToFill()
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(Color.avoraTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.avoraSurface)
            }
        }
        .frame(width: 120, height: 160)
        .clipShape(shape)
        .overlay(shape.stroke(Color.avoraBorderHighlight, lineWidth: 0.5))
    }

    private func glyphTile(_ symbol: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        return Image(systemName: symbol)
            .font(.system(size: 26))
            .foregroundStyle(Color.avoraTextPrimary)
            .frame(width: 64, height: 64)
            .background(Color.avoraSurface, in: shape)
            .overlay(shape.stroke(Color.avoraBorderHighlight, lineWidth: 0.5))
    }
}

private struct WelcomePageDots: View {
    let count: Int
    let current: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == current ? Color.avoraTextPrimary
                                       : Color.avoraTextSecondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

#if DEBUG
#Preview("Welcome carousel") {
    WelcomeView(onFinish: {})
}
#endif
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`. (Do not launch the app.)

- [ ] **Step 3: Verify the preview renders (manual)**

Open `Avora/Views/WelcomeView.swift` in Xcode; the "Welcome carousel" canvas preview should show slide 1 with two placeholder tiles + arrow, the page dots, and a "Next" button. Swiping to slide 3 shows the 3D icon and a "Get Started" button.

- [ ] **Step 4: Commit**

```bash
git add Avora/Views/WelcomeView.swift
git commit -m "feat: add first-run welcome carousel view"
```

---

### Task 2: Wire the carousel into ContentView and gate the signup bonus

Presents `WelcomeView` on first authenticated launch and ensures it precedes the signup-bonus modal.

**Files:**
- Modify: `Avora/ContentView.swift`

**Interfaces:**
- Consumes: `WelcomeView(onFinish:)` from Task 1; `AppState` (`isAuthenticated`, `profile?.signupBonusSeen`, `config.signupExtra`, `markSignupBonusSeen()`).
- Produces: first-run sequencing (Welcome → signup bonus → grid). No new public symbols.

- [ ] **Step 1: Add the `hasSeenWelcome` flag and gate `showSignupBonus`**

In `Avora/ContentView.swift`, add the `@AppStorage` property and replace the existing `showSignupBonus` computed property so the bonus only shows after the welcome is done. Replace lines 4–8:

```swift
    @Environment(AppState.self) private var app
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    private var showWelcome: Bool {
        app.isAuthenticated && !hasSeenWelcome
    }

    private var showSignupBonus: Bool {
        hasSeenWelcome
            && app.profile?.signupBonusSeen == false
            && app.config.signupExtra > 0
    }
```

- [ ] **Step 2: Present the carousel as a full-screen cover**

Still in `Avora/ContentView.swift`, add a `.fullScreenCover` modifier to the outer `Group` (after the existing `.animation(...)` line, line 29). The binding is driven by `showWelcome` and clears the flag on dismiss; `onFinish` sets the flag directly:

```swift
        .fullScreenCover(isPresented: Binding(
            get: { showWelcome },
            set: { if !$0 { hasSeenWelcome = true } }
        )) {
            WelcomeView { hasSeenWelcome = true }
        }
```

The full modified `body` reads:

```swift
    var body: some View {
        Group {
            if app.isAuthenticated {
                RootTabView()
                    .overlay {
                        if showSignupBonus {
                            SignupBonusModal(credits: app.config.signupExtra) {
                                Task { await app.markSignupBonusSeen() }
                            }
                            .transition(.opacity)
                        }
                    }
            } else {
                LoginView()
            }
        }
        .font(.avoraBody)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.avoraBackgroundGradient.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: showSignupBonus)
        .fullScreenCover(isPresented: Binding(
            get: { showWelcome },
            set: { if !$0 { hasSeenWelcome = true } }
        )) {
            WelcomeView { hasSeenWelcome = true }
        }
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Avora/ContentView.swift
git commit -m "feat: show welcome carousel before signup bonus on first launch"
```

---

### Task 3: "Show Intro Again" row in Settings

Lets the user replay the carousel without reinstalling.

**Files:**
- Modify: `Avora/Views/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `@AppStorage("hasSeenWelcome")`; `@Environment(\.dismiss)` (already present at line 5); `Haptics.tap()`.
- Produces: a button that sets `hasSeenWelcome = false` then dismisses Settings, causing `ContentView` to re-present the carousel.

- [ ] **Step 1: Add the `hasSeenWelcome` property**

In `Avora/Views/Settings/SettingsView.swift`, add below the existing `@State` properties (after line 8, `editingUsername`):

```swift
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
```

- [ ] **Step 2: Add the "Show Intro Again" button**

In the section that contains "Restore Purchases" / "Sign Out" (lines 29–41), add the button between them:

```swift
            Section {
                Button("Restore Purchases") {
                    Haptics.tap()
                    Task {
                        try? await AvoraPurchases.restore()
                        await app.refreshProfile()
                    }
                }
                Button("Show Intro Again") {
                    Haptics.tap()
                    hasSeenWelcome = false
                    dismiss()
                }
                Button("Sign Out") {
                    Haptics.tap()
                    Task { await app.signOut() }
                }
            }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Avora/Views/Settings/SettingsView.swift
git commit -m "feat: add Show Intro Again row to settings"
```

---

### Task 4: Drop in real before→after assets (when available)

Deferred until the real photo pair is provided. The app already builds and ships with fallbacks; this task swaps them in with **zero code change**.

**Files:**
- Create: `Avora/Assets.xcassets/OnboardingBefore.imageset/` (via Xcode)
- Create: `Avora/Assets.xcassets/OnboardingAfter.imageset/` (via Xcode)

- [ ] **Step 1: Add the imagesets**

In Xcode, open `Avora/Assets.xcassets`, add two new Image Sets named exactly `OnboardingBefore` and `OnboardingAfter`, and drop the original photo into `OnboardingBefore` and its styled result into `OnboardingAfter` (@1x/@2x/@3x or a single universal image).

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`. Slide 1 now renders the real pair instead of the SF Symbol fallback (the `UIImage(named:) != nil` check in Task 1 picks them up automatically).

- [ ] **Step 3: Commit**

```bash
git add Avora/Assets.xcassets/OnboardingBefore.imageset Avora/Assets.xcassets/OnboardingAfter.imageset
git commit -m "feat: add welcome before/after hero images"
```

---

## Manual Verification (after Tasks 1–3)

Run these on device/simulator by hand (you verify UI; the executor does not launch the app):

1. Fresh install → sign in → **welcome carousel appears** before the signup-bonus modal.
2. Tap through to **Get Started** (or **Skip**) → carousel dismisses → signup-bonus modal shows → then the Styles grid.
3. Force-quit and relaunch → carousel does **not** reappear.
4. Settings → **Show Intro Again** → Settings closes and the carousel reappears (no signup-bonus modal for the existing user).

---

## Self-Review

**Spec coverage:**
- 3-slide carousel, "explain then release" → Task 1. ✓
- `@AppStorage("hasSeenWelcome")` persistence → Tasks 1–3 (consistent key). ✓
- Sequencing Welcome → signup bonus → grid; bonus gated behind flag → Task 2. ✓
- `.fullScreenCover` over `RootTabView` → Task 2. ✓
- Bundled before→after with SF-Symbol fallback → Task 1 (fallback) + Task 4 (real assets). ✓
- Settings "Show Intro Again" row → Task 3. ✓
- Slides 2 & 3 asset-free visuals → Task 1. ✓
- No backend changes; out-of-scope items excluded → whole plan. ✓

**Placeholder scan:** No TBD/TODO; all code shown in full; no "handle edge cases" hand-waving. ✓

**Type consistency:** `WelcomeView(onFinish:)` defined in Task 1, consumed identically in Task 2. `hasSeenWelcome` (exact string `"hasSeenWelcome"`, default `false`) identical across Tasks 1–3. Asset names `OnboardingBefore`/`OnboardingAfter` match between Task 1's `UIImage(named:)` checks and Task 4's imageset names. ✓
