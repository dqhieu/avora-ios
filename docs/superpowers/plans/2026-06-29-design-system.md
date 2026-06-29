# Dark-Only Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add color/spacing/radius tokens and a "Graphite Glass" premium dark visual system to Avora, lock the app to dark mode, and migrate existing views — using native Liquid Glass on iOS 26+ with a material fallback on iOS 18–25.

**Architecture:** Three token files in `Avora/DesignSystem/` (`Colors.swift`, `Layout.swift`, `Surfaces.swift`) extend the existing typography system. `Surfaces.swift` centralizes the single iOS-26 availability branch behind `avoraGlass`, `avoraElevatedSurface`, and `AvoraPrimaryButtonStyle` so views never write `if #available`. Dark mode is locked via build setting + root modifier. Views are then migrated from ad-hoc colors/literals to tokens.

**Tech Stack:** SwiftUI, Liquid Glass (`glassEffect`, iOS 26+), `xcodeproj` Ruby gem, `xcodebuild`/XcodeBuildMCP, simulator screenshots.

## Global Constraints

- Platform: iOS app, SwiftUI. Single app target `Avora`, shared scheme `Avora`, bundle id `com.hieudinh.Avora`.
- **Deployment target stays iOS 18.0** (app target). Liquid Glass APIs are iOS 26+ and MUST be guarded; the guard lives only in `Surfaces.swift`.
- Xcode 16 **synchronized-folder** project (`PBXFileSystemSynchronizedRootGroup`, `path = Avora`): files under `Avora/` are auto-included — never hand-edit `project.pbxproj` to add file references.
- `GENERATE_INFOPLIST_FILE = YES`. `INFOPLIST_KEY_UIUserInterfaceStyle` IS synthesized (unlike `UIAppFonts`), so set it via build setting using the `xcodeproj` gem.
- Dark mode only. Light mode and light color variants are out of scope.
- **No XCTest target exists**; this is visual UI work. Verification per task = (a) build succeeds, (b) the existing DEBUG font audit still passes, (c) simulator screenshots confirm the result. Reaching authenticated screens uses a temporary `-uiPreviewAuth` launch-arg bypass that is reverted before committing (detailed in Task 5).
- Color values (hex): background `0x0A0A0B`, surface `0x161618`, surfaceElevated `0x212124`, textPrimary/accent `0xFAFAFA`, textSecondary `0x9A9AA0`, textTertiary `0x5E5E64`, border `0x29292E`, borderHighlight white@6%, error `0xE5564B`, success `0x4FB286`. Background gradient `0x121215→0x0B0B0D`; surface gradient `0x1C1C20→0x151517`.
- Spacing `4/8/12/16/24/32`; radius `8/12/16/20`.
- Two simulators are used: iPhone 17 (iOS 26.5, glass path) and iPhone 16 Pro (iOS 18.6, fallback path). Confirm availability with `xcrun simctl list devices available` / XcodeBuildMCP `list_sims`.

---

### Task 1: Color tokens and gradients

**Files:**
- Create: `Avora/DesignSystem/Colors.swift`

**Interfaces:**
- Produces: `Color.avoraBackground/avoraSurface/avoraSurfaceElevated/avoraTextPrimary/avoraTextSecondary/avoraTextTertiary/avoraBorder/avoraBorderHighlight/avoraAccent/avoraOnAccent/avoraError/avoraSuccess`; `LinearGradient.avoraBackgroundGradient/avoraSurfaceGradient`; `Color.init(hex: UInt32)`.

- [ ] **Step 1: Create the color tokens**

Create `Avora/DesignSystem/Colors.swift`:

```swift
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    static let avoraBackground      = Color(hex: 0x0A0A0B)
    static let avoraSurface         = Color(hex: 0x161618)
    static let avoraSurfaceElevated = Color(hex: 0x212124)
    static let avoraTextPrimary     = Color(hex: 0xFAFAFA)
    static let avoraTextSecondary   = Color(hex: 0x9A9AA0)
    static let avoraTextTertiary    = Color(hex: 0x5E5E64)
    static let avoraBorder          = Color(hex: 0x29292E)
    static let avoraBorderHighlight = Color(white: 1.0, opacity: 0.06)
    static let avoraAccent          = Color(hex: 0xFAFAFA)
    static let avoraOnAccent        = Color(hex: 0x0A0A0B)
    static let avoraError           = Color(hex: 0xE5564B)
    static let avoraSuccess         = Color(hex: 0x4FB286)
}

extension LinearGradient {
    static let avoraBackgroundGradient = LinearGradient(
        colors: [Color(hex: 0x121215), Color(hex: 0x0B0B0D)],
        startPoint: .top, endPoint: .bottom
    )
    static let avoraSurfaceGradient = LinearGradient(
        colors: [Color(hex: 0x1C1C20), Color(hex: 0x151517)],
        startPoint: .top, endPoint: .bottom
    )
}
```

- [ ] **Step 2: Build to verify it compiles**

Run (XcodeBuildMCP `build_sim`, or):
```bash
cd /Users/hieudinh/Projects/avora-ios
xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
cd /Users/hieudinh/Projects/avora-ios
git add Avora/DesignSystem/Colors.swift
git commit -m "feat: add Avora color tokens and gradients"
```

---

### Task 2: Spacing and radius scales

**Files:**
- Create: `Avora/DesignSystem/Layout.swift`

**Interfaces:**
- Produces: `enum Spacing { xs,sm,md,lg,xl,xxl: CGFloat }`, `enum Radius { sm,md,lg,xl: CGFloat }`.

- [ ] **Step 1: Create the layout scales**

Create `Avora/DesignSystem/Layout.swift`:

```swift
import CoreGraphics

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
cd /Users/hieudinh/Projects/avora-ios
xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
cd /Users/hieudinh/Projects/avora-ios
git add Avora/DesignSystem/Layout.swift
git commit -m "feat: add Avora spacing and radius scales"
```

---

### Task 3: Surface and glass helpers (the one place iOS-26 is branched)

**Files:**
- Create: `Avora/DesignSystem/Surfaces.swift`

**Interfaces:**
- Consumes: color/gradient tokens (Task 1), `Radius` (Task 2), `Font.avoraButton` (existing typography).
- Produces: `View.avoraGlass(in: some Shape) -> some View`, `View.avoraElevatedSurface(cornerRadius: CGFloat = Radius.md) -> some View`, `struct AvoraPrimaryButtonStyle: ButtonStyle`.

- [ ] **Step 1: Create the surface helpers**

Create `Avora/DesignSystem/Surfaces.swift`:

```swift
import SwiftUI

extension View {
    /// Native Liquid Glass on iOS 26+, translucent material fallback on 18–25.
    @ViewBuilder
    func avoraGlass(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.avoraBorderHighlight, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
        }
    }

    /// Solid graphite elevated surface: gradient fill + top highlight + soft shadow.
    func avoraElevatedSurface(cornerRadius: CGFloat = Radius.md) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(LinearGradient.avoraSurfaceGradient, in: shape)
            .overlay(shape.strokeBorder(Color.avoraBorderHighlight, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }
}

/// Primary action button: Liquid Glass prominent on iOS 26+, white-fill capsule on 18–25.
struct AvoraPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.avoraButton)
            .foregroundStyle(Color.avoraOnAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .opacity(configuration.isPressed ? 0.85 : 1)

        if #available(iOS 26.0, *) {
            return AnyView(label.glassEffect(.regular.tint(Color.avoraAccent).interactive(), in: .capsule))
        } else {
            return AnyView(label.background(Color.avoraAccent, in: Capsule()))
        }
    }
}
```

Note: `RoundedRectangle` conforms to `InsettableShape`, so `strokeBorder` is valid in `avoraElevatedSurface`. In `avoraGlass` the parameter is a generic `some Shape`, so it uses `stroke`.

- [ ] **Step 2: Add a DEBUG preview to eyeball the surfaces**

Append to `Avora/DesignSystem/Surfaces.swift`:

```swift
#if DEBUG
#Preview("Surfaces") {
    VStack(spacing: Spacing.lg) {
        Text("Elevated surface")
            .foregroundStyle(Color.avoraTextPrimary)
            .frame(maxWidth: .infinity, minHeight: 80)
            .avoraElevatedSurface(cornerRadius: Radius.lg)
        Text("Glass")
            .foregroundStyle(Color.avoraTextPrimary)
            .padding(Spacing.lg)
            .avoraGlass(in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        Button("Generate") {}
            .buttonStyle(AvoraPrimaryButtonStyle())
    }
    .padding(Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LinearGradient.avoraBackgroundGradient)
}
#endif
```

- [ ] **Step 3: Build to verify it compiles**

```bash
cd /Users/hieudinh/Projects/avora-ios
xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
cd /Users/hieudinh/Projects/avora-ios
git add Avora/DesignSystem/Surfaces.swift
git commit -m "feat: add Avora glass and elevated-surface helpers with iOS 26 fallback"
```

---

### Task 4: Lock dark mode and apply the background gradient

**Files:**
- Modify: `Avora.xcodeproj/project.pbxproj` (via `xcodeproj` gem — `INFOPLIST_KEY_UIUserInterfaceStyle` only)
- Modify: `Avora/Assets.xcassets/AccentColor.colorset/Contents.json`
- Modify: `Avora/ContentView.swift`

**Interfaces:**
- Consumes: `LinearGradient.avoraBackgroundGradient` (Task 1).

- [ ] **Step 1: Set the dark-mode build setting**

```bash
cd /Users/hieudinh/Projects/avora-ios
ruby -e '
require "xcodeproj"
project = Xcodeproj::Project.open("Avora.xcodeproj")
target = project.targets.find { |t| t.name == "Avora" }
target.build_configurations.each do |c|
  c.build_settings["INFOPLIST_KEY_UIUserInterfaceStyle"] = "Dark"
end
project.save
puts "UIUserInterfaceStyle=Dark set"
'
grep -n "INFOPLIST_KEY_UIUserInterfaceStyle" Avora.xcodeproj/project.pbxproj
```
Expected: prints confirmation; `grep` shows the key on both Debug and Release.

- [ ] **Step 2: Set the accent color asset**

Replace `Avora/Assets.xcassets/AccentColor.colorset/Contents.json` with:

```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.980",
          "green" : "0.980",
          "red" : "0.980"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 3: Apply the gradient canvas and lock the color scheme**

In `Avora/ContentView.swift`, change the body (currently the `Group { … }.font(.avoraBody)`) to:

```swift
    var body: some View {
        Group {
            if app.isAuthenticated {
                RootTabView()
            } else {
                LoginView()
            }
        }
        .font(.avoraBody)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.avoraBackgroundGradient.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
```

(`ScrollView` is transparent, so the gradient shows through Home and Collection automatically. `List`-based screens are handled in Task 5.)

- [ ] **Step 4: Build, run, and screenshot the login screen**

Run (XcodeBuildMCP `build_run_sim` on the iPhone 17 sim, then `screenshot`), or:
```bash
cd /Users/hieudinh/Projects/avora-ios
xcrun simctl boot "iPhone 17" 2>/dev/null; true
xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: build succeeds; app launches locked in dark mode. The login screen still shows its photo background (its own black base is intentional and unchanged). Confirm no light-mode flash.

- [ ] **Step 5: Commit**

```bash
cd /Users/hieudinh/Projects/avora-ios
git add Avora.xcodeproj/project.pbxproj Avora/Assets.xcassets/AccentColor.colorset/Contents.json Avora/ContentView.swift
git commit -m "feat: lock app to dark mode with gradient canvas and accent color"
```

---

### Task 5: Migrate views to tokens, surfaces, and glass

**Files:**
- Modify: `Avora/LoginView.swift`
- Modify: `Avora/Views/Home/StylesGridView.swift`
- Modify: `Avora/Views/Collection/CollectionView.swift`
- Modify: `Avora/Views/Create/CreateView.swift`
- Modify: `Avora/Views/Paywall/PaywallView.swift`
- Modify: `Avora/Views/RemoteImage.swift`
- Temporary (reverted in Step 9): `Avora/State/AppState.swift`

**Interfaces:**
- Consumes: all tokens/helpers from Tasks 1–3.

- [ ] **Step 1: Migrate `LoginView` to the primary button style**

In `Avora/LoginView.swift`, replace the `loginButton` and `loginButtonLabel` computed properties (the `if #available` block and the label group, currently lines 26–63) with:

```swift
    private var loginButton: some View {
        Button(action: logIn) {
            loginButtonLabel
        }
        .buttonStyle(AvoraPrimaryButtonStyle())
        .disabled(isLoading)
    }

    private var loginButtonLabel: some View {
        Group {
            if isLoading {
                ProgressView().tint(Color.avoraOnAccent)
            } else {
                Text("Sign in with Apple")
            }
        }
    }
```

(The black base background and photo at the top of `body` are unchanged. The button's frame/foreground/glass now come from `AvoraPrimaryButtonStyle`, removing the per-view `if #available`.)

- [ ] **Step 2: Migrate `StylesGridView`**

In `Avora/Views/Home/StylesGridView.swift`:

Replace the credits row (currently lines 12–16) with a graphite credit bar:

```swift
                HStack {
                    Label("\(p.totalCredits) credits", systemImage: "sparkles")
                    Spacer()
                    Text("\(p.totalGenerations) generations")
                        .foregroundStyle(Color.avoraTextSecondary)
                }
                .font(.avoraSubheadline.monospacedDigit())
                .padding(Spacing.md)
                .avoraElevatedSurface(cornerRadius: Radius.md)
                .padding(.horizontal, Spacing.lg)
```

Replace the `StyleCard` body (currently lines 60–69) with token-based surface and colors:

```swift
        VStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(LinearGradient.avoraSurfaceGradient)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: "photo")
                        .font(.avoraLargeTitle)
                        .foregroundStyle(Color.avoraTextTertiary)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Color.avoraBorderHighlight, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            Text(style.name)
                .font(.avoraHeadline)
                .padding(.top, Spacing.xs)
        }
```

- [ ] **Step 3: Migrate `CollectionView`**

In `Avora/Views/Collection/CollectionView.swift`:

Change the grid spacing/padding literals — `LazyVGrid(columns: cols, spacing: 8)` → `spacing: Spacing.sm`, and `.padding(8)` → `.padding(Spacing.sm)`.

Replace the `Thumb` body (currently lines 50–58) with:

```swift
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(Color.avoraSurface)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                RemoteImage(path: path, contentMode: .fill)
            }
            .clipShape(.rect(cornerRadius: Radius.sm, style: .continuous))
```

- [ ] **Step 4: Migrate `CreateView`**

In `Avora/Views/Create/CreateView.swift`:

`VStack(spacing: 16)` (line 16) → `VStack(spacing: Spacing.lg)`; `.padding()` (line 20) → `.padding(Spacing.lg)`.

Placeholder rectangle (lines 35–36) →:

```swift
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Color.avoraSurface)
                    .overlay {
                        Text("Pick a photo to start")
                            .foregroundStyle(Color.avoraTextSecondary)
                    }
```

"Generating…" overlay (lines 39–41) → glass:

```swift
                ProgressView("Generating…")
                    .padding(Spacing.lg)
                    .avoraGlass(in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
```

Buttons: make the hero `Generate` (lines 64–67) use the primary style, and recolor the secondary buttons off system blue:

```swift
            Button { Task { await generate() } } label: {
                Label("Generate", systemImage: "wand.and.stars")
            }
            .buttonStyle(AvoraPrimaryButtonStyle())
            .disabled(sourceImage == nil || isWorking)
```

For the remaining buttons, add `.tint(Color.avoraAccent)`:
- `Save` button (line 53 area): after `.buttonStyle(.borderedProminent)` add `.tint(Color.avoraAccent)`.
- `Generate again` button (line 57 area): after `.buttonStyle(.bordered)` add `.tint(Color.avoraAccent)`.
- `PhotosPicker` (line 63 area): after `.buttonStyle(.bordered)` add `.tint(Color.avoraAccent)`.

Error text (line 71) → `.foregroundStyle(Color.avoraError)` (keep `.font(.avoraFootnote)`).

- [ ] **Step 5: Migrate `PaywallView`**

In `Avora/Views/Paywall/PaywallView.swift`:

Change the description color (line 23) `.foregroundStyle(.secondary)` → `.foregroundStyle(Color.avoraTextSecondary)`.

Make it a glass sheet with token rows — modify the `List` (lines 12–32 area) by adding these modifiers to the `List` (alongside the existing `.navigationTitle("Credits")`):

```swift
            .listRowBackground(Color.avoraSurface)
            .scrollContentBackground(.hidden)
            .presentationBackground(.thinMaterial)
```

(`.listRowBackground` applies to the rows; `.presentationBackground(.thinMaterial)` gives the sheet a translucent glass feel on all supported iOS versions.)

- [ ] **Step 6: Migrate `RemoteImage`**

In `Avora/Views/RemoteImage.swift`, line 18, change `.foregroundStyle(.secondary)` → `.foregroundStyle(Color.avoraTextSecondary)`.

- [ ] **Step 7: Verify the build and the migration gate**

```bash
cd /Users/hieudinh/Projects/avora-ios
xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 17' build
grep -rnE "\.foregroundStyle\(\.(secondary|red)\)|\.fill\(\.secondary|cornerRadius: 1[0-9]\b" Avora --include="*.swift"
```
Expected: `BUILD SUCCEEDED`; the `grep` returns **no matches** (no ad-hoc secondary/red colors or stray `cornerRadius: 1x` literals remain in views).

- [ ] **Step 8: Screenshot the authenticated screens (temporary auth bypass)**

Temporarily allow the simulator to show authenticated screens. In `Avora/State/AppState.swift`:

Change the `isAuthenticated` initializer (line 9) to:
```swift
    var isAuthenticated = ProcessInfo.processInfo.arguments.contains("-uiPreviewAuth") || SupabaseClientProvider.client.auth.currentSession != nil
```

Add this as the first line of `bootstrap()`:
```swift
        if ProcessInfo.processInfo.arguments.contains("-uiPreviewAuth") { return }
```

Then run on the iPhone 17 (iOS 26) sim with the launch arg (XcodeBuildMCP `build_run_sim` with `launchArgs: ["-uiPreviewAuth"]`, then `screenshot`).

Expected: the Home screen shows the graphite credit bar and style cards with depth (gradient + highlight + shadow), Cormorant nav title, near-black gradient canvas, white text. Navigate to Create to confirm the glass "Generating…" overlay and the glass `Generate` button.

- [ ] **Step 9: Revert the temporary bypass**

```bash
cd /Users/hieudinh/Projects/avora-ios
git checkout Avora/State/AppState.swift
grep -c "uiPreviewAuth" Avora/State/AppState.swift
```
Expected: `0` (bypass gone).

- [ ] **Step 10: Final clean build and commit**

```bash
cd /Users/hieudinh/Projects/avora-ios
xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 17' build
git add Avora/LoginView.swift Avora/Views/Home/StylesGridView.swift Avora/Views/Collection/CollectionView.swift Avora/Views/Create/CreateView.swift Avora/Views/Paywall/PaywallView.swift Avora/Views/RemoteImage.swift
git commit -m "feat: migrate views to design system tokens, surfaces, and glass"
```
Expected: `BUILD SUCCEEDED`; `AppState.swift` is NOT in the commit (it was reverted).

---

### Task 6: Verify the iOS 18–25 fallback path

Confirms glass surfaces fall back cleanly (no availability crash, no visual breakage) on a pre-26 OS.

**Files:** none (verification only; fix forward if breakage is found).

- [ ] **Step 1: Build and run on an iOS 18 simulator**

Run on the iPhone 16 Pro (iOS 18.6) simulator (XcodeBuildMCP: set `simulatorId` to the iPhone 16 Pro from `list_sims`, then `build_run_sim`), or:
```bash
cd /Users/hieudinh/Projects/avora-ios
xcrun simctl boot "iPhone 16 Pro" 2>/dev/null; true
xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
xcrun simctl install booted "$(xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -showBuildSettings 2>/dev/null | awk -F' = ' '/ CODESIGNING_FOLDER_PATH/{print $2}')"
xcrun simctl launch booted com.hieudinh.Avora
```
Expected: build succeeds; the app launches in dark mode on iOS 18.6 with no crash.

- [ ] **Step 2: Screenshot and confirm the fallback button**

```bash
xcrun simctl io booted screenshot /tmp/avora-ios18-login.png
```
Expected: the login `Sign in with Apple` button renders as a solid white capsule (the `AvoraPrimaryButtonStyle` non-glass branch), not broken or invisible. The app does not crash on launch (proves the `#available` guard in `Surfaces.swift` works).

- [ ] **Step 3: (If breakage found) fix and re-verify**

If any glass surface renders incorrectly on iOS 18, adjust the `else` branch in `Surfaces.swift` only, rebuild on iPhone 16 Pro, re-screenshot, and commit:
```bash
cd /Users/hieudinh/Projects/avora-ios
git add Avora/DesignSystem/Surfaces.swift
git commit -m "fix: correct iOS 18 fallback rendering for glass surfaces"
```
If no breakage, no commit — verification is complete.

---

## Self-Review

**Spec coverage:**
- Color tokens → Task 1. ✓
- Gradients → Task 1. ✓
- Spacing + radius → Task 2. ✓
- Glass/elevated-surface API + centralized availability branch → Task 3. ✓
- Liquid Glass scoped to controls/overlays/sheets (buttons, generating overlay, paywall sheet); content cards solid graphite → Tasks 3, 5. ✓
- Dark-mode lock (build setting + preferredColorScheme + AccentColor) → Task 4. ✓
- Background gradient canvas → Task 4 (+ List handling in Task 5). ✓
- Full migration of all listed views → Task 5. ✓
- Migration notes (material over imagery → glass; bordered buttons off blue; login black-over-image kept) → Task 5 Steps 1, 4. ✓
- iOS 18 fallback verification → Task 6. ✓
- Success criteria (dark lock, no ad-hoc colors/literals, glass on 26, fallback on 18, build clean, font audit intact) → Tasks 4, 5 (grep gate), 6. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code; every command has expected output. ✓

**Type consistency:** `avoraGlass(in:)`, `avoraElevatedSurface(cornerRadius:)`, `AvoraPrimaryButtonStyle`, and all `Color.avora*`/`LinearGradient.avora*`/`Spacing.*`/`Radius.*` names are defined in Tasks 1–3 and used identically in Tasks 4–5. `Color.avoraOnAccent` (used in LoginView ProgressView tint and the button style) is defined in Task 1. ✓
