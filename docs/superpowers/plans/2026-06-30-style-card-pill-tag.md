# Style Card Pill Tag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a curated, free-form pill tag (e.g. "Hot 🔥") on the top-right corner of style cards in the styles grid.

**Architecture:** Add one optional `badgeText` field to the `Style` model (backend-curated). Render it as a small adaptive capsule overlaid on the card's image tile, shown only when the text is present and non-empty.

**Tech Stack:** Swift, SwiftUI, Xcode 26, existing Avora design-system tokens.

## Global Constraints

- Use existing design tokens only — `.avoraSurface`, `.avoraTextPrimary`, `.avoraBorderHighlight`, `.avoraCaption2` (no new colors/fonts).
- `badgeText` is backend-curated free-form text; the app renders it verbatim (no enum, no per-tag color).
- Pill treatment is "style D / adaptive": light chip + dark text in light mode, flipping to dark chip + light text in dark mode via the adaptive tokens.
- Do not change the style label, grid layout, or card tap/navigation behavior.
- **No XCTest target exists in this project.** Verification is by building the `Avora` scheme and visually confirming via `#Preview` / simulator screenshot. Do not add a test target.

**Verification commands (used by multiple tasks):**

Build (must succeed with no errors):
```bash
xcodebuild build -project Avora.xcodeproj -scheme Avora \
  -destination 'platform=iOS Simulator,name=iPhone 16' -quiet
```
(Alternatively, the `XcodeBuildMCP` tools `build_sim` / `build_run_sim` / `screenshot` drive the same scheme/simulator.)

---

### Task 1: Add `badgeText` to the Style model

**Files:**
- Modify: `Avora/Models/Style.swift`

**Interfaces:**
- Produces: `Style.badgeText: String?` (stored, decoded from JSON key `badgeText`) and `Style.displayBadge: String?` (computed — returns `badgeText` only when non-nil and non-empty after trimming whitespace/newlines; otherwise `nil`).

- [ ] **Step 1: Add the stored field**

In `Avora/Models/Style.swift`, add `badgeText` as the last stored property of the struct:

```swift
struct Style: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let sampleImagePath: String?
    let active: Bool
    let sortOrder: Int
    let badgeText: String?
}
```

Because the property is optional, synthesized `Codable` decodes a missing
`badgeText` key as `nil`, so existing API responses keep decoding.

- [ ] **Step 2: Add the `displayBadge` computed property**

Add this inside the same file (extension at the bottom of `Style.swift`, or inside the struct):

```swift
extension Style {
    /// Trimmed badge text to display, or nil when there is no meaningful badge.
    var displayBadge: String? {
        guard let badgeText,
              !badgeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return badgeText
    }
}
```

- [ ] **Step 3: Build to verify it compiles and existing decoding is intact**

Run the build command from Global Constraints.
Expected: build succeeds. (Any other code constructing `Style` directly in
the codebase will now require the `badgeText` argument — search and fix:
`grep -rn "Style(" Avora` and add `badgeText: nil` to any literal initializers.
If the only construction sites are JSON decoding, no further change is needed.)

- [ ] **Step 4: Commit**

```bash
git add Avora/Models/Style.swift
git commit -m "feat: add optional badgeText to Style model"
```

---

### Task 2: Render the pill on the style card

**Files:**
- Modify: `Avora/Views/Home/StylesGridView.swift`

**Interfaces:**
- Consumes: `Style.displayBadge` from Task 1.
- Produces: `StyleBadge` (private view rendering one capsule pill); the
  `StyleCard.tile` view gains a top-trailing badge overlay.

- [ ] **Step 1: Add the `StyleBadge` view**

At the bottom of `Avora/Views/Home/StylesGridView.swift`, add:

```swift
private struct StyleBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.avoraCaption2)
            .foregroundStyle(Color.avoraTextPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.avoraSurface, in: Capsule())
            .overlay(Capsule().stroke(Color.avoraBorderHighlight, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            .allowsHitTesting(false)
    }
}
```

- [ ] **Step 2: Overlay the badge on the tile**

In `StyleCard.tile`, wrap the iOS-version branch in a `Group` and attach the
badge as a top-trailing overlay so it sits on top of the finished tile in both
the iOS 26 glass and the fallback paths. Replace the existing
`if #available(iOS 26.0, *) { ... } else { ... }` tail of `tile` with:

```swift
        Group {
            if #available(iOS 26.0, *) {
                content.glassEffect(in: shape)
            } else {
                content
                    .background(colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : .white, in: shape)
                    .overlay(shape.stroke(Color.secondary.opacity(0.5), lineWidth: 0.5))
            }
        }
        .overlay(alignment: .topTrailing) {
            if let badge = style.displayBadge {
                StyleBadge(text: badge)
                    .padding(8)
            }
        }
```

(The `let shape` / `let content` lines at the top of `tile` are unchanged.)

- [ ] **Step 3: Add a preview that exercises both badge states**

Add a `#Preview` at the bottom of the file (inside `#if DEBUG` if the file uses
that convention; otherwise plain) so the pill can be verified visually:

```swift
#if DEBUG
#Preview("Style cards — badge states") {
    let cols = [GridItem(.flexible()), GridItem(.flexible())]
    return LazyVGrid(columns: cols, spacing: 12) {
        StyleCard(style: Style(id: "1", name: "Vintage Film", sampleImagePath: nil, active: true, sortOrder: 0, badgeText: "Hot 🔥"))
        StyleCard(style: Style(id: "2", name: "Watercolor", sampleImagePath: nil, active: true, sortOrder: 1, badgeText: nil))
        StyleCard(style: Style(id: "3", name: "Trending One", sampleImagePath: nil, active: true, sortOrder: 2, badgeText: "Trending 🔥"))
        StyleCard(style: Style(id: "4", name: "Blank Badge", sampleImagePath: nil, active: true, sortOrder: 3, badgeText: "   "))
    }
    .padding()
}
#endif
```

- [ ] **Step 4: Build and verify visually**

Run the build command from Global Constraints. Expected: build succeeds.
Then open the `"Style cards — badge states"` preview (or run the app in the
simulator and capture a screenshot of the Styles grid).
Expected:
- Card 1 shows a "Hot 🔥" pill at the top-right of the image tile.
- Card 2 (nil) shows no pill.
- Card 3 shows a "Trending 🔥" pill.
- Card 4 (whitespace-only) shows no pill.
- Tapping a card still navigates to the create screen (badge does not block taps).

- [ ] **Step 5: Verify dark mode**

Toggle the preview / simulator to dark mode.
Expected: the pill flips to a dark chip with light text and stays legible over
the tile in both light and dark appearance.

- [ ] **Step 6: Commit**

```bash
git add Avora/Views/Home/StylesGridView.swift
git commit -m "feat: show curated badge pill on style cards"
```

---

## Self-Review

**Spec coverage:**
- Data model (`badgeText: String?`, optional decode) → Task 1, Steps 1 & 3.
- Free-form / single fixed style / no color field → Task 2, Step 1 (`StyleBadge` uses fixed tokens).
- Render on image tile, top-right, 8pt inset → Task 2, Step 2.
- Visibility only when non-nil and non-empty (trimmed) → Task 1 `displayBadge` + Task 2 Step 2 guard.
- `.allowsHitTesting(false)` / tap still navigates → Task 2, Step 1 + Step 4 check.
- Adaptive light/dark → Task 2, Step 1 (adaptive tokens) + Step 5 check.
- Existing responses without key still decode → Task 1, Step 1 (optional) + Step 3.

**Placeholders:** none — every code step shows complete code.

**Type consistency:** `badgeText: String?` and `displayBadge: String?` defined in Task 1 are the exact names consumed in Task 2. `StyleBadge(text:)` defined and used consistently. `Style(...)` initializer in the preview includes all six stored properties in declaration order.
