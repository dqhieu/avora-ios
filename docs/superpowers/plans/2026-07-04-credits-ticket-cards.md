# Credit Pack Ticket Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the one-time credit packs in `CreditsView` as tap-to-buy admission-ticket cards — a notched-corner yellow "stamp" with black ink, double border, and vertical stub text — arranged in a vertical list with the featured pack taller.

**Architecture:** Add a reusable `NotchedRectangle` `InsettableShape` (ported from the Steps app's `PassportStampView`) and two color tokens to the design system. Replace the two existing pack views (`FeaturedPackCard`, `PackGridCell`) with a single `CreditTicketCard` that renders both the prominent and standard variants. Swap `CreditsView`'s hero+grid block for a vertical `VStack` list. No purchasing, catalog, or data-model changes.

**Tech Stack:** SwiftUI, Xcode 26, single `Avora` target. Custom fonts via `Font.avora*` tokens.

## Global Constraints

- Solid ticket fill: `avoraTicketYellow` ≈ `#F2C12E`; ink: `avoraTicketInk` ≈ `#141414`. Both fixed across light/dark mode.
- Left vertical stub label is the fixed string `CREDIT PACK` (no pack-name data field).
- Whole ticket is a single `Button` → `onBuy`; no separate buy button.
- Numbers use existing `Font.avora*` tokens with `.monospacedDigit()`. Do not introduce system monospace fonts.
- No XCTest target exists in this project. Each task is verified by a compiling build plus a SwiftUI `#Preview` that renders the expected structure. Do **not** add a test target or fabricate unit tests.
- Follow existing design-system usage: `Spacing`, `Radius`, `Color.avora*`, `Font.avora*`.
- Build/verify command (resolves SPM packages on first run, may take a few minutes):
  `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
  (XcodeBuildMCP `build_sim` is an equivalent alternative.)

---

### Task 1: `NotchedRectangle` shape

**Files:**
- Create: `Avora/DesignSystem/NotchedRectangle.swift`

**Interfaces:**
- Produces: `struct NotchedRectangle: InsettableShape` with `var notchRadius: CGFloat` (default 12) and `var insetAmount: CGFloat` (default 0). Concave quarter-circle scooped from each corner. Consumed by `CreditTicketCard` in Task 3.

- [ ] **Step 1: Write the Preview (the failing "test")**

Create `Avora/DesignSystem/NotchedRectangle.swift` with only a Preview that exercises the not-yet-existing shape, so the build fails first:

```swift
import SwiftUI

#if DEBUG
#Preview("NotchedRectangle") {
    NotchedRectangle(notchRadius: 20)
        .fill(Color.avoraTicketYellow)
        .overlay(NotchedRectangle(notchRadius: 20).strokeBorder(Color.avoraTicketInk, lineWidth: 2))
        .frame(width: 300, height: 140)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient.avoraBackgroundGradient)
}
#endif
```

- [ ] **Step 2: Build to verify it fails**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD FAILED — "cannot find 'NotchedRectangle' in scope" (and `avoraTicketYellow`/`avoraTicketInk` unresolved; those land in Task 2).

- [ ] **Step 3: Implement the shape**

Insert above the `#if DEBUG` block in the same file:

```swift
/// A rectangle with a concave quarter-circle scooped from each corner.
/// Ported from the Steps app's PassportStampView.
struct NotchedRectangle: InsettableShape {
    var notchRadius: CGFloat = 12
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(notchRadius - insetAmount, 1)

        var path = Path()
        path.move(to: CGPoint(x: r.minX + radius, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        path.addArc(center: CGPoint(x: r.maxX, y: r.minY), radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        path.addArc(center: CGPoint(x: r.maxX, y: r.maxY), radius: radius,
                    startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
        path.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        path.addArc(center: CGPoint(x: r.minX, y: r.maxY), radius: radius,
                    startAngle: .degrees(0), endAngle: .degrees(270), clockwise: true)
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        path.addArc(center: CGPoint(x: r.minX, y: r.minY), radius: radius,
                    startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        path.closeSubpath()
        return path
    }
}
```

Note: this Preview also depends on the Task 2 color tokens. If running tasks strictly in order, temporarily fill with `.yellow`/`.black` to build Task 1 alone, then revert once Task 2 lands — or implement Task 2 first. Either order is fine.

- [ ] **Step 4: Build to verify it passes** (after Task 2, or with temporary system colors)

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED. Open the Preview in Xcode: a yellow rounded panel whose four corners curve inward (concave), with a black outline.

- [ ] **Step 5: Commit**

```bash
git add Avora/DesignSystem/NotchedRectangle.swift
git commit -m "feat: add NotchedRectangle shape"
```

---

### Task 2: Ticket color tokens

**Files:**
- Modify: `Avora/DesignSystem/Colors.swift:47-48` (add after `avoraError` / `avoraSuccess`)

**Interfaces:**
- Produces: `Color.avoraTicketYellow`, `Color.avoraTicketInk`. Consumed by Task 1's Preview and `CreditTicketCard` in Task 3.

- [ ] **Step 1: Add the tokens**

In `Avora/DesignSystem/Colors.swift`, inside the `extension Color`, add two lines just after `static let avoraSuccess = Color(hex: 0x4FB286)`:

```swift
    static let avoraTicketYellow    = Color(hex: 0xF2C12E)
    static let avoraTicketInk       = Color(hex: 0x141414)
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED. Task 1's `NotchedRectangle` Preview now renders yellow with black ink.

- [ ] **Step 3: Commit**

```bash
git add Avora/DesignSystem/Colors.swift
git commit -m "feat: add credit ticket color tokens"
```

---

### Task 3: `CreditTicketCard` view

**Files:**
- Modify (replace contents below `CreditPackDisplay`): `Avora/Views/Credits/CreditPackCard.swift`

**Interfaces:**
- Consumes: `NotchedRectangle` (Task 1); `Color.avoraTicketYellow`, `Color.avoraTicketInk` (Task 2); existing `struct CreditPackDisplay { let credits: Int; let priceString: String; let bonusPercent: Int; let isFeatured: Bool }`.
- Produces: `struct CreditTicketCard: View` with initializer `CreditTicketCard(pack: CreditPackDisplay, prominent: Bool, onBuy: @escaping () -> Void)`. Consumed by `CreditsView` in Task 4.
- Removes: `BonusBadge`, `FeaturedPackCard`, `PackGridCell` (confirm no references remain — grep in Step 1).

- [ ] **Step 1: Confirm the old views are only used in CreditsView**

Run: `grep -rn "FeaturedPackCard\|PackGridCell\|BonusBadge" Avora`
Expected: references only in `CreditPackCard.swift` (definitions + `#Preview`) and `CreditsView.swift`. Task 4 updates `CreditsView`; this task removes the definitions.

- [ ] **Step 2: Replace the view code**

In `Avora/Views/Credits/CreditPackCard.swift`, **keep** the `import SwiftUI` line and the `struct CreditPackDisplay { ... }` declaration. **Delete** everything from `private struct BonusBadge` through the end of the file (including the old `#Preview`), and replace it with:

```swift
/// A thin straight line (horizontal or vertical) for dashed ticket rules/separators.
private struct TicketRule: Shape {
    var horizontal: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if horizontal {
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        } else {
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        return p
    }
}

/// Admission-ticket card for a consumable credit pack. The whole card is a buy button.
struct CreditTicketCard: View {
    let pack: CreditPackDisplay
    var prominent: Bool
    let onBuy: () -> Void

    private let notch: CGFloat = 14
    private var height: CGFloat { prominent ? 168 : 128 }

    var body: some View {
        Button(action: onBuy) { ticket }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
    }

    private var ticket: some View {
        HStack(spacing: 0) {
            verticalText("CREDIT PACK", bold: false)
                .frame(width: 34)
            separator
            centerContent
                .frame(maxWidth: .infinity)
            separator
            verticalText(pack.priceString, bold: true)
                .frame(width: 46)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .foregroundStyle(Color.avoraTicketInk)
        .background(Color.avoraTicketYellow, in: NotchedRectangle(notchRadius: notch))
        .overlay(NotchedRectangle(notchRadius: notch).strokeBorder(Color.avoraTicketInk, lineWidth: 2))
        .overlay(
            NotchedRectangle(notchRadius: notch - 2)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                .foregroundStyle(Color.avoraTicketInk.opacity(0.55))
                .padding(6)
        )
    }

    @ViewBuilder private var centerContent: some View {
        if prominent {
            VStack(spacing: Spacing.xs) {
                Text("✦  BEST VALUE  ✦").font(.avoraCaption2).tracking(3)
                rule
                Text(pack.credits, format: .number).font(.avoraLargeTitle.monospacedDigit())
                rule
                Text(footerText).font(.avoraCaption2).tracking(1)
            }
            .padding(.horizontal, Spacing.sm)
        } else {
            VStack(spacing: Spacing.xs) {
                if pack.bonusPercent > 0 {
                    Text("+\(pack.bonusPercent)% BONUS").font(.avoraCaption2).tracking(2)
                }
                Text(pack.credits, format: .number).font(.avoraTitle.monospacedDigit())
                Text("CREDITS").font(.avoraCaption2).tracking(2)
            }
        }
    }

    private var rule: some View {
        TicketRule(horizontal: true)
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            .foregroundStyle(Color.avoraTicketInk.opacity(0.35))
            .frame(width: 160, height: 1)
    }

    private var separator: some View {
        TicketRule(horizontal: false)
            .stroke(style: StrokeStyle(lineWidth: 1.4, dash: [4, 5]))
            .foregroundStyle(Color.avoraTicketInk.opacity(0.45))
            .frame(width: 1)
            .padding(.vertical, Spacing.lg)
    }

    private func verticalText(_ text: String, bold: Bool) -> some View {
        Text(text)
            .font(bold ? .avoraSubheadline.monospacedDigit() : .avoraCaption2)
            .tracking(bold ? 0 : 2)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .frame(maxHeight: .infinity)
    }

    private var footerText: String {
        pack.bonusPercent > 0 ? "CREDITS · +\(pack.bonusPercent)% BONUS" : "CREDITS"
    }

    private var accessibilityText: String {
        var parts = ["Credit pack", "\(pack.credits) credits"]
        if pack.bonusPercent > 0 { parts.append("\(pack.bonusPercent) percent bonus") }
        parts.append(pack.priceString)
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Credit ticket cards") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            CreditTicketCard(pack: .init(credits: 6000, priceString: "$39.99",
                                         bonusPercent: 50, isFeatured: true), prominent: true) {}
            CreditTicketCard(pack: .init(credits: 2500, priceString: "$19.99",
                                         bonusPercent: 25, isFeatured: false), prominent: false) {}
            CreditTicketCard(pack: .init(credits: 1000, priceString: "$9.99",
                                         bonusPercent: 0, isFeatured: false), prominent: false) {}
            CreditTicketCard(pack: .init(credits: 500, priceString: "kr 99,00",
                                         bonusPercent: 0, isFeatured: false), prominent: false) {}
        }
        .padding(Spacing.lg)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LinearGradient.avoraBackgroundGradient)
}
#endif
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD FAILED — `CreditsView.swift` still references `FeaturedPackCard`/`PackGridCell` ("cannot find 'FeaturedPackCard' in scope"). This is expected; Task 4 fixes `CreditsView`. The new `CreditPackCard.swift` file itself must have no errors — if the compiler reports errors inside `CreditPackCard.swift`, fix those before moving on.

- [ ] **Step 4: Inspect the Preview**

In Xcode, open the "Credit ticket cards" Preview in `CreditPackCard.swift`. Confirm: featured "6,000" ticket taller with `✦ BEST VALUE ✦` header and `CREDITS · +50% BONUS` footer; "2,500" shows `+25% BONUS` / number / `CREDITS`; "1,000" shows number / `CREDITS`; the long price (`kr 99,00`) fits the right stub without clipping. Corners concave, double border, vertical side text.

- [ ] **Step 5: Commit**

```bash
git add Avora/Views/Credits/CreditPackCard.swift
git commit -m "feat: replace pack cards with CreditTicketCard"
```

---

### Task 4: `CreditsView` vertical-list layout

**Files:**
- Modify: `Avora/Views/Credits/CreditsView.swift:14-18` (remove `cols`, `featured`, `gridPacks`) and `:33-43` (replace the hero+grid block)

**Interfaces:**
- Consumes: `CreditTicketCard(pack:prominent:onBuy:)` (Task 3); existing `packOptions: [CreditPackOption]`, `buy(_:)`, `sectionLabel`, `retry`.

- [ ] **Step 1: Remove the grid plumbing**

In `Avora/Views/Credits/CreditsView.swift`, delete these three declarations:

```swift
    private let cols = [GridItem(.flexible(), spacing: Spacing.sm),
                        GridItem(.flexible(), spacing: Spacing.sm)]

    private var featured: CreditPackOption? { packOptions.first { $0.display.isFeatured } }
    private var gridPacks: [CreditPackOption] { packOptions.filter { !$0.display.isFeatured } }
```

and add this computed property in their place (featured pack pinned to the top, remaining packs keep catalog order):

```swift
    private var orderedPacks: [CreditPackOption] {
        packOptions.filter { $0.display.isFeatured } + packOptions.filter { !$0.display.isFeatured }
    }
```

- [ ] **Step 2: Replace the hero+grid block**

In `body`, replace this block:

```swift
                    if let featured {
                        sectionLabel
                        FeaturedPackCard(pack: featured.display) { Task { await buy(featured.package) } }
                        LazyVGrid(columns: cols, spacing: Spacing.sm) {
                            ForEach(gridPacks) { opt in
                                PackGridCell(pack: opt.display) { Task { await buy(opt.package) } }
                            }
                        }
                    } else if loadFailed {
                        retry
                    }
```

with:

```swift
                    if !packOptions.isEmpty {
                        sectionLabel
                        VStack(spacing: Spacing.md) {
                            ForEach(orderedPacks) { opt in
                                CreditTicketCard(pack: opt.display,
                                                 prominent: opt.display.isFeatured) {
                                    Task { await buy(opt.package) }
                                }
                            }
                        }
                    } else if loadFailed {
                        retry
                    }
```

- [ ] **Step 3: Build to verify it passes**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Verify no stale references remain**

Run: `grep -rn "FeaturedPackCard\|PackGridCell\|BonusBadge\|gridPacks\|\\bcols\\b" Avora`
Expected: no matches.

- [ ] **Step 5: Run in the simulator and confirm behavior**

Run the Avora scheme on an iOS simulator (Xcode Run, or XcodeBuildMCP `build_run_sim`). On the Credits screen confirm: featured ticket taller at top, standard tickets below in a vertical list; tapping a ticket starts a purchase; tickets read as disabled while `busy`; check both light and dark appearance.

- [ ] **Step 6: Commit**

```bash
git add Avora/Views/Credits/CreditsView.swift
git commit -m "feat: lay out credit packs as vertical ticket list"
```

---

## Self-Review

**Spec coverage:**
- NotchedRectangle shape → Task 1. ✓
- Color tokens `avoraTicketYellow`/`avoraTicketInk` → Task 2. ✓
- `CreditTicketCard` replacing both old views, yellow/ink, double border, vertical stubs, tap-to-buy, featured vs standard center layouts (bonus above / CREDITS below on standard) → Task 3. ✓
- Remove `BonusBadge` → Task 3. ✓
- Retain `CreditPackDisplay` → Task 3 (explicitly kept). ✓
- Vertical list, featured taller, featured pinned top → Task 4. ✓
- Remove grid plumbing → Task 4. ✓
- Edge cases: bonus == 0 (Task 3 center logic), long price (Task 3 Preview + `minimumScaleFactor`). ✓
- Accessibility label + button trait → Task 3. ✓
- Unchanged balance header / WeeklyPlanCard / sectionLabel / retry / load / buy → untouched by all tasks. ✓

**Type consistency:** `CreditTicketCard(pack:prominent:onBuy:)` defined in Task 3 and called identically in Task 4. `CreditPackDisplay` fields match `CreditPackCard.swift`. `orderedPacks` returns `[CreditPackOption]`, iterated with `ForEach` (Identifiable via `productId`). Color/font token names match Tasks 1–2 and the design system.

**Placeholder scan:** No TBD/TODO; all code shown in full. Verification adapted to the no-test-target reality per Global Constraints (honest, not fabricated).
