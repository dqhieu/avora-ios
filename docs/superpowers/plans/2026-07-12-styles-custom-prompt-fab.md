# Styles Custom-Prompt Floating Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the "Custom" text CTA in the Styles screen's section header with an icon-only floating glass button pinned bottom-right that opens the same custom-prompt creation flow.

**Architecture:** A single-file SwiftUI change in `StylesGridView`. Add a `NavigationLink`-wrapped glass circle as a `.overlay(alignment: .bottomTrailing)` on the existing `ScrollView`, reusing the already-registered `CreateRoute` navigation destination. Remove the old header CTA and add bottom content padding so the last grid row clears the button.

**Tech Stack:** SwiftUI, Xcode 26, the Avora design system (`avoraGlass`, `ThiingIcon`, `Spacing`, `Haptics`).

## Global Constraints

- Deployment target spans iOS 18–26; `avoraGlass(in:)` already branches Liquid Glass (26+) vs `.ultraThinMaterial` fallback (18–25). Use it — do not call `glassEffect` directly.
- No Swift unit-test target exists; verification is **build + visual inspection** in the simulator. Do not invent a test target.
- Build scheme: `Avora`. Project: `Avora.xcodeproj` (no workspace for the app target).
- Code comments explain the *why*, never reference plan/spec/phase artifacts.
- Reuse existing tokens: `Spacing.xl` (24), `ThiingIcon`, `Haptics.tap()`, `CreateRoute`, `Style.custom`.

---

### Task 1: Replace the header "Custom" CTA with a floating glass button

**Files:**
- Modify: `Avora/Views/Home/StylesGridView.swift`

**Interfaces:**
- Consumes (all pre-existing, unchanged):
  - `CreateRoute(style: Style, placeholder: RemoteImageRef?)` — navigation value; a `.navigationDestination(for: CreateRoute.self)` is already registered on line 69.
  - `Style.custom` — static `Style` for the custom-prompt flow.
  - `View.avoraGlass(in: some Shape) -> some View` — glass surface with 18–25 fallback.
  - `ThiingIcon(name: String, size: CGFloat)` — asset icon view.
  - `Spacing.xl` == `24`; `Haptics.tap()`.
- Produces: none (leaf UI change; no new public symbols).

- [ ] **Step 1: Remove the "Custom" CTA from the section header**

In `Avora/Views/Home/StylesGridView.swift`, the `Section`'s `header:` closure (currently lines 24–39) is:

```swift
                } header: {
                    HStack {
                        Text("All styles")
                            .font(.avoraTitle2)
                        Spacer()
                        NavigationLink(value: CreateRoute(style: .custom, placeholder: nil)) {
                            Text("Custom")
                                .font(.avoraSubheadline)
                                .foregroundStyle(Color.avoraAccent)
                        }
                        .contentShape(.rect)
                        .buttonStyle(AvoraCustomButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                    }
                    .padding(.horizontal, Spacing.xl)
                }
```

Replace that entire `header:` closure with:

```swift
                } header: {
                    Text("All styles")
                        .font(.avoraTitle2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Spacing.xl)
                }
```

- [ ] **Step 2: Add bottom clearance so the last row scrolls clear of the button**

The `LazyVStack(spacing: 0)` opens on line 12 and closes on line 51 (the `}` immediately before the `ScrollView`'s closing `}` on line 52). Add a bottom padding modifier to that `LazyVStack`. Change:

```swift
            LazyVStack(spacing: 0) {
                Section {
```

...leave the body unchanged, and at the `LazyVStack`'s closing brace add the modifier. The closing looks like:

```swift
                }
            }
        }
        .avoraSoftScrollEdge()
```

Change it to (add `.padding(.bottom, 80)` on the `LazyVStack`, i.e. after its closing brace, before the `ScrollView` closes):

```swift
                }
            }
            .padding(.bottom, 80)
        }
        .avoraSoftScrollEdge()
```

Rationale to include as a code comment on that line: the floating button is 56pt tall inset by `Spacing.xl` (24) = 80pt, so the last grid row must clear it. Write it as:

```swift
            .padding(.bottom, 80) // clear the floating custom-prompt button (56pt + 24pt inset)
```

- [ ] **Step 3: Attach the floating button as an overlay on the ScrollView**

The `ScrollView { … }` closes on line 52 followed by `.avoraSoftScrollEdge()` on line 53. Insert an `.overlay(alignment: .bottomTrailing)` between the `ScrollView`'s closing brace and `.avoraSoftScrollEdge()`. The region currently reads:

```swift
        }
        .avoraSoftScrollEdge()
        .navigationTitle("Avora")
```

Change it to:

```swift
        }
        .overlay(alignment: .bottomTrailing) { customPromptButton }
        .avoraSoftScrollEdge()
        .navigationTitle("Avora")
```

- [ ] **Step 4: Add the `customPromptButton` view**

Add this computed property to `StylesGridView` (place it immediately after the `body` property's closing brace, before `private func load`):

```swift
    // Floating entry point to the custom-prompt creation flow. Reuses the
    // CreateRoute destination already registered on this stack, so tapping it
    // pushes CreateView with Style.custom.
    private var customPromptButton: some View {
        NavigationLink(value: CreateRoute(style: .custom, placeholder: nil)) {
            ThiingIcon(name: "ActionGenerate", size: 28)
                .frame(width: 56, height: 56)
                .avoraGlass(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Custom prompt")
        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
        .padding(Spacing.xl)
    }
```

- [ ] **Step 5: Build to verify it compiles (both glass paths)**

Run:

```bash
xcodebuild -project Avora.xcodeproj -scheme Avora \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`. If the named simulator is unavailable, run `xcrun simctl list devices available | grep iPhone` and substitute an available iPhone name.

- [ ] **Step 6: Visual verification in the simulator**

Launch the app (via the running scheme or `xcodebuild … build` then boot/install, or Xcode Run) and open the first tab (Create → Styles screen). Confirm all of:

1. A round glass button with the `ActionGenerate` icon floats at the bottom-right, above the tab bar, not clipped by it.
2. The old "Custom" text link is gone from the "All styles" header; the title is left-aligned.
3. Scrolling to the bottom, the last row of style cards clears the button (not hidden underneath).
4. Tapping the button pushes the custom-prompt `CreateView` (title "Custom", prompt field visible).
5. Optional (VoiceOver on): the button announces "Custom prompt".

If any check fails, fix and re-run Steps 5–6 before committing.

- [ ] **Step 7: Commit**

```bash
git add Avora/Views/Home/StylesGridView.swift
git commit -m "feat: replace styles Custom CTA with floating custom-prompt button"
```

---

## Notes

- **Unused after this change:** `AvoraCustomButtonStyle` (in `Avora/DesignSystem/Surfaces.swift`) is no longer referenced once the header CTA is removed. It is pre-existing shared design-system code — leave it in place; do not delete it as part of this task. Flag it to the reviewer only.

## Self-Review

- **Spec coverage:** Placement/overlay (Step 3), appearance/glass circle + `ActionGenerate` (Step 4), accessibility label (Step 4), behavior/NavigationLink + haptic (Step 4), content clearance (Step 2), remove old CTA (Step 1), `AvoraCustomButtonStyle` flagged not deleted (Notes), iOS 18–26 build (Step 5) — all present.
- **Placeholders:** none; every code step shows exact before/after.
- **Type consistency:** `CreateRoute(style:placeholder:)`, `Style.custom`, `avoraGlass(in:)`, `ThiingIcon(name:size:)`, `Spacing.xl` all match their definitions in the codebase.
