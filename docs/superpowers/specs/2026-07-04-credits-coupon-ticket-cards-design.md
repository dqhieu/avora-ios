# Credit Pack "Ticket" Cards — Design Spec

Date: 2026-07-04
Area: `Avora/Views/Credits/`
Status: Approved, ready for implementation planning

## Goal

Restyle the one-time credit packs in `CreditsView` as **admission-ticket / passport-stamp cards** — a
notched-corner rectangle with a solid yellow fill, black ink, double border, and vertical stub text.
Each ticket is tap-to-buy. This replaces the current `FeaturedPackCard` (hero) + `PackGridCell` (grid)
pair with a single ticket view: the featured pack full-width on top, standard packs in a 2-column grid below.

Scope is limited to the one-time packs. The balance header, `WeeklyPlanCard`, "One-time packs" section
label, and load/retry states are unchanged.

## Non-goals

- No change to purchasing logic, RevenueCat wiring, or the profile-polling flow in `CreditsView.buy(_:)`.
- No change to the pack data model (`CreditPack`, `CreditPackOption`) or `CreditsCatalog` selection/bonus math.
- No pack "name" / tier field. The vertical left label is a fixed string.
- No animation or stacked-ticket decoration (a single ticket per pack).

## Visual design

### Shape — `NotchedRectangle`

A reusable `InsettableShape` with a concave quarter-circle scooped out of **all four corners** (the
corners curve inward). This is a direct port of `NotchedRectangle` from the Steps app's
`PassportStampView.swift`. It supports `.inset(by:)` so a smaller notched border can be drawn inside a
larger one (radius shrinks with the inset).

Lives in the design system: `Avora/DesignSystem/NotchedRectangle.swift`.

### Ticket appearance (all packs)

- **Fill:** solid ticket yellow. **Ink:** near-black. Both are fixed regardless of light/dark mode.
- **Outer border:** `NotchedRectangle` stroked solid, ~2pt, black.
- **Inner border:** a second `NotchedRectangle`, inset ~6pt, stroked with a **dotted** style, black at
  reduced opacity — matching the passport-stamp double border.
- **Stubs:** two dashed vertical separator lines divide the ticket into left stub / center / right stub.
  - **Left stub:** vertical text (rotated -90°) reading `CREDIT PACK` (fixed string).
  - **Right stub:** vertical text (rotated -90°) showing the localized price (e.g. `$39.99`), monospaced digits.
- **Center content** differs by prominence (below).
- The **whole ticket is a `Button`** (`.buttonStyle(.plain)`) whose action is `onBuy`. No separate CTA button.

### Center content by variant

**Featured pack (`prominent == true`, taller ticket):**
```
✦  BEST VALUE  ✦        (header, tracked)
——— dashed divider ———
      6,000             (large credit number, monospaced)
——— dashed divider ———
CREDITS · +50% BONUS    (footer, tracked)
```

**Standard pack (`prominent == false`, shorter ticket):**
```
+25% BONUS              (only shown when bonusPercent > 0)
   2,500                (credit number, monospaced)
  CREDITS               (label under the value)
```
When `bonusPercent == 0`, the top bonus line is omitted and the number + `CREDITS` label are vertically
centered.

## Component design

### `NotchedRectangle` (new)
`Avora/DesignSystem/NotchedRectangle.swift` — the `InsettableShape` above. Parameter: `notchRadius`.

### `CreditTicketCard` (new, replaces `FeaturedPackCard` + `PackGridCell`)
`Avora/Views/Credits/CreditPackCard.swift` (replace the two old views in this file).

Inputs:
- `pack: CreditPackDisplay` — existing plain display struct (`credits`, `priceString`, `bonusPercent`, `isFeatured`).
- `prominent: Bool` — drives taller height + featured center layout. Defaults from `pack.isFeatured`.
- `onBuy: () -> Void`.

Structure:
- Root `Button(action: onBuy)` → content → `.buttonStyle(.plain)`.
- Content: yellow-filled `NotchedRectangle` background + solid outer border + inset dotted inner border.
- Layout: an `HStack` of [left vertical label] · [center `VStack`] · [right vertical price], with the two
  dashed separators drawn as an overlay aligned to the stub boundaries.
- Vertical text: `Text(...).rotationEffect(.degrees(-90)).fixedSize()` inside a fixed-width stub column.
- Featured vs standard height controlled by a min-height constant; center `VStack` swaps layout on `prominent`.

`CreditPackDisplay` struct is retained as-is. `BonusBadge` is **removed** (its `+N%` role is now baked into the ticket center); confirm no other references before deleting.

### `CreditsView` changes
`Avora/Views/Credits/CreditsView.swift`:
- Featured pack renders full-width and prominent as `CreditTicketCard(pack:prominent: true, onBuy:)` at the top.
- Standard packs render below in the 2-column `LazyVGrid` (`cols`), each a non-prominent
  `CreditTicketCard(pack:prominent: false, onBuy:)`, in the catalog's existing credits-ascending order.
- Keep `featuredPack` / `standardPacks` computed properties to split the two groups.
- `sectionLabel`, `balanceHeader`, `WeeklyPlanCard`, `retry`, `load()`, and `buy(_:)` unchanged.

### Color tokens
`Avora/DesignSystem/Colors.swift`: add
- `avoraTicketYellow` — solid ticket yellow (approx `#F2C12E`), same in light/dark.
- `avoraTicketInk` — near-black ink (approx `#141414`), same in light/dark.

Exact hex values finalized during implementation against the running app; the mock used `#F2C12E` / `#141414`.

## States & edge cases

- **Bonus == 0:** omit bonus line (both variants). Standard centers number + `CREDITS`.
- **Long localized price:** the right vertical stub must apply `minimumScaleFactor` / `lineLimit(1)` so long
  currency strings don't overflow the stub height.
- **Busy / disabled:** the existing `.disabled(busy)` on the scroll content still applies; tickets should
  read as disabled during a purchase (inherit the current behavior).
- **Load failure / empty:** unchanged `retry` `ContentUnavailableView`.

## Accessibility

- Each ticket is a single button. Provide an `accessibilityLabel` combining pack name, credits, bonus, and
  price (e.g. "Credit pack, 6,000 credits, 50% bonus, $39.99") and an `.isButton` trait, so VoiceOver does
  not read the rotated stub text awkwardly.
- **Dynamic Type:** rotated stub text can clip at large accessibility sizes. Cap stub text scaling
  (`minimumScaleFactor`) and verify at AX sizes; the ticket height may need to grow with the center content.

## Testing / verification

- SwiftUI `#Preview`s in `CreditPackCard.swift` covering: featured (with bonus), standard with bonus,
  standard without bonus, and a long-price locale — on the app background gradient.
- Manual check in the running app (Credits screen): featured taller at top, standard packs below, tap-to-buy
  triggers purchase, disabled state during purchase, light & dark background.
- Confirm no remaining references to `FeaturedPackCard`, `PackGridCell`, or `BonusBadge` after the swap.

## Files touched

- `Avora/DesignSystem/NotchedRectangle.swift` — new shape.
- `Avora/DesignSystem/Colors.swift` — add `avoraTicketYellow`, `avoraTicketInk`.
- `Avora/Views/Credits/CreditPackCard.swift` — replace `FeaturedPackCard`/`PackGridCell` with
  `CreditTicketCard`; remove `BonusBadge`; keep `CreditPackDisplay`.
- `Avora/Views/Credits/CreditsView.swift` — vertical list layout; remove grid plumbing.

## Risks

- Rotated vertical stub text + Dynamic Type clipping (mitigation above).
- Long localized prices in the narrow right stub (mitigation above).
- Solid yellow is a brand color not used elsewhere in Avora — intentional: credit packs read as special.
  If it clashes, `avoraTicketYellow`/`avoraTicketInk` are single points of change.
