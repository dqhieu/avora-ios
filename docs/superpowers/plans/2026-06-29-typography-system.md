# Typography System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Avora's all-system-font UI with a two-font typography system (Cormorant Garamond for display, Bricolage Grotesque for UI/body) exposed as Dynamic-Type-aware semantic tokens.

**Architecture:** Bundle 7 static `.ttf` files, register them via the `INFOPLIST_KEY_UIAppFonts` build setting, expose a `Font` extension of `avora*` tokens that each use `Font.custom(_:size:relativeTo:)`, set the SwiftUI root default font to Bricolage, configure `UINavigationBarAppearance` so nav-bar titles render Cormorant, then migrate the handful of explicit `.font()` call sites.

**Tech Stack:** SwiftUI, UIKit (appearance + `UIFont`/`UIFontMetrics`), Xcode 16 synchronized-folder project, `xcodeproj` Ruby gem, `xcodebuild`/`simctl` (or XcodeBuildMCP).

## Global Constraints

- Platform: iOS app, SwiftUI. Single app target named `Avora`; shared scheme `Avora`.
- The project is an Xcode 16 **synchronized-folder** project (`PBXFileSystemSynchronizedRootGroup`, `path = Avora`). **Any file placed under `Avora/` is automatically compiled/bundled** — never hand-edit `project.pbxproj` to add file references.
- The project uses `GENERATE_INFOPLIST_FILE = YES`; there is **no** standalone `Info.plist`. Info.plist keys are set as `INFOPLIST_KEY_*` build settings.
- Exact PostScript names (verified from the font files; they match the filenames): `CormorantGaramond-SemiBold`, `CormorantGaramond-Medium`, `CormorantGaramond-MediumItalic`, `BricolageGrotesque-Regular`, `BricolageGrotesque-Medium`, `BricolageGrotesque-SemiBold`, `BricolageGrotesque-Bold`.
- Source font files live at `/Users/hieudinh/Downloads/fonts/` (Cormorant statics under `Cormorant_Garamond/static/`, Bricolage statics under `Bricolage_Grotesque/static/`).
- Every token uses `relativeTo:` so it scales with Dynamic Type.
- **No XCTest target exists** in this project, and this is visual UI work. Verification per task is: (a) the build succeeds, (b) the DEBUG runtime font audit passes (Task 1), and (c) simulator screenshots confirm the visual result. This is a deliberate, pragmatic choice — adding a unit-test target is out of scope for this plan.
- Build/run commands below use `xcodebuild`/`simctl`; the XcodeBuildMCP equivalents (`build_run_sim`, `screenshot`) are acceptable substitutes. Before the first build, confirm scheme + simulator (`xcodebuild -list -project Avora.xcodeproj`, `xcrun simctl list devices available`). Examples assume an available `iPhone 16` simulator — substitute a real device name if needed.

---

### Task 1: Bundle fonts, register them, and add a runtime font audit

Establishes that all 7 fonts load by PostScript name. Uses a real red→green cycle: the DEBUG audit traps before fonts are bundled, passes after.

**Files:**
- Create: `Avora/Services/FontAudit.swift`
- Modify: `Avora/AvoraApp.swift:7-11` (add DEBUG assertion in `init()`)
- Create (resources): `Avora/Resources/Fonts/*.ttf` (7 files)
- Modify: `Avora.xcodeproj/project.pbxproj` (via `xcodeproj` gem — adds `INFOPLIST_KEY_UIAppFonts` only)

**Interfaces:**
- Produces: `enum FontAudit` with `static let requiredPostScriptNames: [String]` and `static func missingPostScriptNames() -> [String]`.

- [ ] **Step 1: Create the font audit**

Create `Avora/Services/FontAudit.swift`:

```swift
import UIKit

/// Verifies that every bundled custom font is registered and resolvable by its
/// PostScript name. A non-empty result means a font file is missing from the
/// bundle or its UIAppFonts registration, or its PostScript name is wrong.
enum FontAudit {
    static let requiredPostScriptNames = [
        "CormorantGaramond-SemiBold",
        "CormorantGaramond-Medium",
        "CormorantGaramond-MediumItalic",
        "BricolageGrotesque-Regular",
        "BricolageGrotesque-Medium",
        "BricolageGrotesque-SemiBold",
        "BricolageGrotesque-Bold",
    ]

    static func missingPostScriptNames() -> [String] {
        requiredPostScriptNames.filter { UIFont(name: $0, size: 12) == nil }
    }
}
```

- [ ] **Step 2: Add the DEBUG assertion at launch**

In `Avora/AvoraApp.swift`, change the `init()` (currently lines 7-11) to:

```swift
    init() {
        #if DEBUG
        let missingFonts = FontAudit.missingPostScriptNames()
        assert(missingFonts.isEmpty, "Missing bundled fonts: \(missingFonts)")
        #endif
        let app = AppState()
        _app = State(initialValue: app)
        Task { await app.bootstrap() }
    }
```

- [ ] **Step 3: Build & run to verify the audit FAILS (red)**

Run:

```bash
cd /Users/hieudinh/Projects/avora-ios
xcodebuild -project Avora.xcodeproj -scheme Avora \
  -destination 'platform=iOS Simulator,name=iPhone 16' build && \
xcrun simctl install booted "$(xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' -showBuildSettings 2>/dev/null | awk -F' = ' '/ CODESIGNING_FOLDER_PATH/{print $2}')" && \
xcrun simctl launch booted com.hieudinh.Avora
```

Expected: the build succeeds, but the app **traps on launch** with `Missing bundled fonts: [...all 7...]` (fonts not bundled yet). This confirms the audit detects unregistered fonts.

(Simpler alternative: XcodeBuildMCP `build_run_sim`, then observe the assertion crash in logs.)

- [ ] **Step 4: Copy the 7 font files into the bundle**

```bash
cd /Users/hieudinh/Projects/avora-ios
mkdir -p Avora/Resources/Fonts
cp /Users/hieudinh/Downloads/fonts/Cormorant_Garamond/static/CormorantGaramond-SemiBold.ttf Avora/Resources/Fonts/
cp /Users/hieudinh/Downloads/fonts/Cormorant_Garamond/static/CormorantGaramond-Medium.ttf Avora/Resources/Fonts/
cp /Users/hieudinh/Downloads/fonts/Cormorant_Garamond/static/CormorantGaramond-MediumItalic.ttf Avora/Resources/Fonts/
cp /Users/hieudinh/Downloads/fonts/Bricolage_Grotesque/static/BricolageGrotesque-Regular.ttf Avora/Resources/Fonts/
cp /Users/hieudinh/Downloads/fonts/Bricolage_Grotesque/static/BricolageGrotesque-Medium.ttf Avora/Resources/Fonts/
cp /Users/hieudinh/Downloads/fonts/Bricolage_Grotesque/static/BricolageGrotesque-SemiBold.ttf Avora/Resources/Fonts/
cp /Users/hieudinh/Downloads/fonts/Bricolage_Grotesque/static/BricolageGrotesque-Bold.ttf Avora/Resources/Fonts/
ls Avora/Resources/Fonts
```

Expected: 7 `.ttf` files listed. (They are auto-included by the synchronized folder group.)

- [ ] **Step 5: Register the fonts via `INFOPLIST_KEY_UIAppFonts`**

Run this Ruby script (the `xcodeproj` gem is installed):

```bash
cd /Users/hieudinh/Projects/avora-ios
ruby -e '
require "xcodeproj"
project = Xcodeproj::Project.open("Avora.xcodeproj")
fonts = %w[
  CormorantGaramond-SemiBold.ttf
  CormorantGaramond-Medium.ttf
  CormorantGaramond-MediumItalic.ttf
  BricolageGrotesque-Regular.ttf
  BricolageGrotesque-Medium.ttf
  BricolageGrotesque-SemiBold.ttf
  BricolageGrotesque-Bold.ttf
]
target = project.targets.find { |t| t.name == "Avora" }
target.build_configurations.each do |c|
  c.build_settings["INFOPLIST_KEY_UIAppFonts"] = fonts
end
project.save
puts "UIAppFonts set on #{target.build_configurations.map(&:name).join(\", \")}"
'
grep -n "INFOPLIST_KEY_UIAppFonts" Avora.xcodeproj/project.pbxproj
```

Expected: prints the config names; `grep` shows the `INFOPLIST_KEY_UIAppFonts` array in both Debug and Release.

> Fallback if the array build setting does not surface in the generated Info.plist: create `Avora/Info.plist` with a `UIAppFonts` array of the 7 filenames and set `INFOPLIST_FILE = Avora/Info.plist` + `GENERATE_INFOPLIST_FILE = NO`. Only do this if Step 6 still shows missing fonts.

- [ ] **Step 6: Build & run to verify the audit PASSES (green)**

Run the same command as Step 3.

Expected: build succeeds and the app **launches without trapping** (no "Missing bundled fonts" message). The audit now finds all 7 fonts registered.

- [ ] **Step 7: Commit**

```bash
cd /Users/hieudinh/Projects/avora-ios
git add Avora/Services/FontAudit.swift Avora/AvoraApp.swift Avora/Resources/Fonts Avora.xcodeproj/project.pbxproj
git commit -m "feat: bundle and register Cormorant and Bricolage fonts with runtime audit"
```

---

### Task 2: Typography token API

Adds the `Font` extension with all semantic tokens plus a DEBUG specimen preview.

**Files:**
- Create: `Avora/DesignSystem/Typography.swift`

**Interfaces:**
- Consumes: the registered PostScript names from Task 1.
- Produces: `Font` static members `avoraHero, avoraLargeTitle, avoraTitle, avoraTitle2, avoraTitle3, avoraSerifAccent, avoraHeadline, avoraBody, avoraCallout, avoraSubheadline, avoraButton, avoraFootnote, avoraCaption, avoraCaption2`.

- [ ] **Step 1: Create the token extension**

Create `Avora/DesignSystem/Typography.swift`:

```swift
import SwiftUI

extension Font {
    // Display tier — Cormorant Garamond
    static let avoraHero        = Font.custom("CormorantGaramond-SemiBold", size: 48, relativeTo: .largeTitle)
    static let avoraLargeTitle  = Font.custom("CormorantGaramond-SemiBold", size: 34, relativeTo: .largeTitle)
    static let avoraTitle       = Font.custom("CormorantGaramond-SemiBold", size: 28, relativeTo: .title)
    static let avoraTitle2      = Font.custom("CormorantGaramond-Medium",   size: 22, relativeTo: .title2)
    static let avoraTitle3      = Font.custom("CormorantGaramond-Medium",   size: 20, relativeTo: .title3)
    static let avoraSerifAccent = Font.custom("CormorantGaramond-MediumItalic", size: 20, relativeTo: .title3)

    // UI / body tier — Bricolage Grotesque
    static let avoraHeadline    = Font.custom("BricolageGrotesque-SemiBold", size: 17, relativeTo: .headline)
    static let avoraBody        = Font.custom("BricolageGrotesque-Regular",  size: 17, relativeTo: .body)
    static let avoraCallout     = Font.custom("BricolageGrotesque-Regular",  size: 16, relativeTo: .callout)
    static let avoraSubheadline = Font.custom("BricolageGrotesque-Medium",   size: 15, relativeTo: .subheadline)
    static let avoraButton      = Font.custom("BricolageGrotesque-SemiBold", size: 17, relativeTo: .body)
    static let avoraFootnote    = Font.custom("BricolageGrotesque-Regular",  size: 13, relativeTo: .footnote)
    static let avoraCaption     = Font.custom("BricolageGrotesque-Medium",   size: 12, relativeTo: .caption)
    static let avoraCaption2    = Font.custom("BricolageGrotesque-Regular",  size: 11, relativeTo: .caption2)
}

#if DEBUG
#Preview("Typography specimen") {
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reimagine your photos").font(.avoraHero)
            Text("Choose a style").font(.avoraLargeTitle)
            Text("Your collection").font(.avoraTitle)
            Text("Recent generations").font(.avoraTitle2)
            Text("Section header").font(.avoraTitle3)
            Text("“Crafted just for you.”").font(.avoraSerifAccent)
            Divider()
            Text("Vintage Film Portrait").font(.avoraHeadline)
            Text("Upload a photo and Avora transforms it in seconds.").font(.avoraBody)
            Text("Secondary body copy").font(.avoraCallout)
            Text("12 styles available").font(.avoraSubheadline)
            Text("Generate").font(.avoraButton)
            Text("Saved to your library").font(.avoraFootnote)
            Text("2 credits").font(.avoraCaption)
            Text("Updated just now").font(.avoraCaption2)
            Text("1,234 credits").font(.avoraTitle2.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
#endif
```

- [ ] **Step 2: Build to verify it compiles**

```bash
cd /Users/hieudinh/Projects/avora-ios
xcodebuild -project Avora.xcodeproj -scheme Avora \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
cd /Users/hieudinh/Projects/avora-ios
git add Avora/DesignSystem/Typography.swift
git commit -m "feat: add Avora typography tokens (Font extension)"
```

---

### Task 3: Nav-bar appearance + root default body font

Makes nav-bar titles render Cormorant and sets Bricolage as the default for all SwiftUI text.

**Files:**
- Create: `Avora/DesignSystem/AppearanceConfigurator.swift`
- Modify: `Avora/AvoraApp.swift` (call configurator in `init()`)
- Modify: `Avora/ContentView.swift:7-13` (apply `.font(.avoraBody)` to the root `Group`)

**Interfaces:**
- Consumes: Cormorant PostScript name (Task 1), `Font.avoraBody` (Task 2).
- Produces: `enum AppearanceConfigurator` with `static func configureNavigationBar()`.

- [ ] **Step 1: Create the appearance configurator**

Create `Avora/DesignSystem/AppearanceConfigurator.swift`:

```swift
import UIKit

/// Applies custom fonts to UIKit-backed chrome that SwiftUI modifiers cannot
/// reach — specifically navigation-bar titles, which ignore `.font()`.
enum AppearanceConfigurator {
    static func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()

        if let largeTitle = UIFont(name: "CormorantGaramond-SemiBold", size: 34) {
            appearance.largeTitleTextAttributes[.font] =
                UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: largeTitle)
        }
        if let inlineTitle = UIFont(name: "CormorantGaramond-SemiBold", size: 17) {
            appearance.titleTextAttributes[.font] =
                UIFontMetrics(forTextStyle: .headline).scaledFont(for: inlineTitle)
        }

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
}
```

- [ ] **Step 2: Invoke the configurator at launch**

In `Avora/AvoraApp.swift`, add the call at the top of `init()` (before the DEBUG audit block from Task 1):

```swift
    init() {
        AppearanceConfigurator.configureNavigationBar()
        #if DEBUG
        let missingFonts = FontAudit.missingPostScriptNames()
        assert(missingFonts.isEmpty, "Missing bundled fonts: \(missingFonts)")
        #endif
        let app = AppState()
        _app = State(initialValue: app)
        Task { await app.bootstrap() }
    }
```

- [ ] **Step 3: Set the root default font**

In `Avora/ContentView.swift`, apply the default font to the root `Group` (lines 7-13):

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
    }
```

- [ ] **Step 4: Build, run, and screenshot the home screen**

```bash
cd /Users/hieudinh/Projects/avora-ios
xcodebuild -project Avora.xcodeproj -scheme Avora \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
xcrun simctl launch booted com.hieudinh.Avora
xcrun simctl io booted screenshot /tmp/avora-home.png
```

Expected: the "Avora" large navigation title renders in Cormorant Garamond (serif); body/label text renders in Bricolage Grotesque (sans). (XcodeBuildMCP `screenshot` is an acceptable substitute.) Open `/tmp/avora-home.png` to confirm.

- [ ] **Step 5: Commit**

```bash
cd /Users/hieudinh/Projects/avora-ios
git add Avora/DesignSystem/AppearanceConfigurator.swift Avora/AvoraApp.swift Avora/ContentView.swift
git commit -m "feat: render nav titles in Cormorant and default body to Bricolage"
```

---

### Task 4: Migrate explicit `.font()` call sites + tabular numbers

Replaces every existing `.font(...)` with an `avora*` token, applies display tokens to in-body titles, and adds tabular figures to number displays. (SF Symbol icon sizing is included for size consistency; custom fonts apply to symbols by point size.)

**Files:**
- Modify: `Avora/LoginView.swift:58`
- Modify: `Avora/Views/Home/StylesGridView.swift:16,66,68`
- Modify: `Avora/Views/Create/CreateView.swift:71`
- Modify: `Avora/Views/Paywall/PaywallView.swift:20,22,26`

**Interfaces:**
- Consumes: tokens from Task 2; root default font from Task 3.

- [ ] **Step 1: Migrate `LoginView`**

In `Avora/LoginView.swift`, line 58, change:

```swift
                    .font(.headline.weight(.semibold))
```

to:

```swift
                    .font(.avoraButton)
```

- [ ] **Step 2: Migrate `StylesGridView`**

In `Avora/Views/Home/StylesGridView.swift`:

Line 16 — change the credits/generations row font to tabular subheadline:

```swift
                }.padding(.horizontal).font(.avoraSubheadline.monospacedDigit())
```

Line 66 — change the placeholder icon size token:

```swift
                    Image(systemName: "photo").font(.avoraLargeTitle).foregroundStyle(.secondary)
```

Line 68 — change the style-card title (drop `.bold()`, since `avoraHeadline` is already SemiBold):

```swift
            Text(style.name).font(.avoraHeadline).padding(.top, 4)
```

- [ ] **Step 3: Migrate `CreateView`**

In `Avora/Views/Create/CreateView.swift`, line 71, change:

```swift
            Text(errorText).foregroundStyle(.red).font(.avoraFootnote)
```

- [ ] **Step 4: Migrate `PaywallView`**

In `Avora/Views/Paywall/PaywallView.swift`:

Line 20 — emphasize the package title:

```swift
                                    Text(pkg.storeProduct.localizedTitle).font(.avoraHeadline)
```

Line 22 — change the description caption token:

```swift
                                        .font(.avoraCaption)
```

Line 26 — make the price tabular and weighted (drop `.bold()`):

```swift
                                Text(pkg.storeProduct.localizedPriceString).font(.avoraHeadline.monospacedDigit())
```

- [ ] **Step 5: Build, run, and screenshot each migrated screen**

```bash
cd /Users/hieudinh/Projects/avora-ios
xcodebuild -project Avora.xcodeproj -scheme Avora \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
xcrun simctl launch booted com.hieudinh.Avora
xcrun simctl io booted screenshot /tmp/avora-migrated.png
```

Expected: `BUILD SUCCEEDED`; the home grid, style-card titles, and (after navigating) the Create and Paywall screens render with the new tokens; credit counts and prices use tabular (non-jittering) figures. Verify the login screen separately if reachable. (Navigate via XcodeBuildMCP UI automation or manually in the simulator to capture Create/Paywall.)

- [ ] **Step 6: Verify no stale system `.font()` calls remain**

```bash
cd /Users/hieudinh/Projects/avora-ios
grep -rn "\.font(\.\(headline\|subheadline\|body\|callout\|title\|title2\|title3\|largeTitle\|footnote\|caption\|caption2\))" Avora --include="*.swift"
```

Expected: **no matches** (every call site now uses an `avora*` token or the inherited root default).

- [ ] **Step 7: Commit**

```bash
cd /Users/hieudinh/Projects/avora-ios
git add Avora/LoginView.swift Avora/Views/Home/StylesGridView.swift Avora/Views/Create/CreateView.swift Avora/Views/Paywall/PaywallView.swift
git commit -m "feat: migrate view font call sites to Avora typography tokens"
```

---

### Task 5: Dynamic Type verification

Confirms tokens scale with the system text-size setting and that layouts hold at large sizes. Fix any overflow found.

**Files:**
- Modify (only if overflow is found): the affected view file(s).

- [ ] **Step 1: Launch at the default text size and screenshot**

```bash
cd /Users/hieudinh/Projects/avora-ios
xcrun simctl ui booted content_size medium
xcrun simctl launch booted com.hieudinh.Avora
xcrun simctl io booted screenshot /tmp/avora-type-medium.png
```

- [ ] **Step 2: Launch at an accessibility-XL text size and screenshot**

```bash
xcrun simctl ui booted content_size accessibility-extra-extra-extra-large
xcrun simctl terminate booted com.hieudinh.Avora
xcrun simctl launch booted com.hieudinh.Avora
xcrun simctl io booted screenshot /tmp/avora-type-axxxl.png
```

Expected: text in `/tmp/avora-type-axxxl.png` is visibly larger than in `/tmp/avora-type-medium.png` (tokens scale via `relativeTo:`). Note any clipped or overlapping text.

- [ ] **Step 3: Fix overflow if present, otherwise reset**

If a screen clips at the largest size, apply a minimal fix (e.g. `.minimumScaleFactor(0.8)` or `.lineLimit(nil)`) to the specific `Text`, rebuild, and re-screenshot. Then reset the simulator text size:

```bash
xcrun simctl ui booted content_size medium
```

- [ ] **Step 4: Commit (only if a fix was made)**

```bash
cd /Users/hieudinh/Projects/avora-ios
git add -A
git commit -m "fix: handle large Dynamic Type sizes in <view>"
```

If no fix was needed, skip this commit — verification is complete.

---

## Self-Review

**Spec coverage:**
- Font roles (serif display / sans body) → Tasks 2, 3, 4. ✓
- Full semantic token set → Task 2 (all 14 tokens incl. hero + serif accent). ✓
- Dynamic Type (`relativeTo:`) → Task 2 tokens; verified Task 5. ✓
- Lean curated 7-file bundle → Task 1 Step 4. ✓
- Hero/display tier → `avoraHero` in Task 2. ✓
- Tabular numbers → Task 4 (StylesGrid credits, Paywall price) + documented `.monospacedDigit()`. ✓
- Font registration via `INFOPLIST_KEY_UIAppFonts` + fallback → Task 1 Step 5. ✓
- Root default body font → Task 3 Step 3. ✓
- Nav-bar appearance gotcha → Task 3 Steps 1-2. ✓
- Migration of the 4 view files → Task 4. ✓
- DesignSystem/ namespace → Tasks 2, 3 create files there. ✓
- Success criteria (fonts load, all call sites tokenized, serif titles, scaling, tabular figures, clean build) → Tasks 1, 4 (grep), 3, 5. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code; every command shows expected output. ✓

**Type consistency:** `FontAudit.missingPostScriptNames()` / `requiredPostScriptNames` used identically in Tasks 1 & 3. `AppearanceConfigurator.configureNavigationBar()` defined and called consistently. Token names in Task 4 edits all exist in the Task 2 extension. ✓
