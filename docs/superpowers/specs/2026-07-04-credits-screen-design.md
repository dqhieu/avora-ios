# Credits Screen — Design

**Date:** 2026-07-04
**Status:** Approved (design), pending implementation plan

## Summary

A dedicated Credits screen, reached from a new balance pill in the toolbar
(beside the existing Settings gear). It shows the user's live credit balance and
lets them buy more via RevenueCat consumable packs. It replaces the existing
`PaywallView`, which is deleted; the out-of-credits interrupt in `CreateView`
now routes to this screen.

Supporting five differently-priced packs (each granting a different credit
amount) requires backend work: today the webhook grants a flat 500 credits for
*any* consumable. A new `credit_packs` table becomes the single source of truth
for product → credits, read by both the webhook (to grant) and the app (to
display).

## Packs

Fixed pricing and grants (product IDs to be confirmed against RevenueCat):

| Price (USD) | Credits | Bonus vs base | Badge |
|-------------|---------|---------------|-------|
| $4.99  | 500   | base         | none              |
| $9.99  | 1,000 | ~0%          | none (intentional anchor) |
| $19.99 | 2,500 | +25%         | `+25%`            |
| $29.99 | 4,000 | +33%         | `+33%`            |
| $39.99 | 6,000 | +50%         | `Best value · +50%` (featured) |

Bonus is computed client-side from the cheapest pack's credits-per-dollar
(`500 / 4.99 ≈ 100.2`). A pack whose bonus rounds to ≤ ~1% shows no badge, so the
$9.99 anchor never displays "+0%". The featured (hero) pack is the one with the
highest bonus.

## UI / Layout

Storefront layout, adaptive light/dark using existing `Color.avora*` tokens.

- **Balance header:** `centsign.circle` SF Symbol + formatted `totalCredits`
  (tabular digits), centered. No "generations left" line.
- **Featured pack:** hero card with the "Best value" badge, large credit amount,
  and an inline `Buy · $39.99` button.
- **Remaining packs:** 2×2 grid below, sorted by price ascending, each showing
  credits + localized price, with a small bonus badge where applicable.
- Presented as a sheet inside a `NavigationStack`, with a `Done` button —
  consistent with Settings.

Reference mockups: `.superpowers/brainstorm/5541-1783154397/content/layout-final.html`

## Entry point

- A tappable **balance pill** (`centsign.circle` + formatted balance) added to
  the top-right toolbar, to the left of the gear, on **both** Home
  (`StylesGridView`) and Collection (`CollectionView`).
- Tapping presents `CreditsView` as a sheet: `NavigationStack { CreditsView().environment(app) }`.
- `CreateView` out-of-credits path (currently presents `PaywallView`) now
  presents `CreditsView`.

## Client architecture

New `Avora/Views/Credits/CreditsView.swift` (plus small subviews to keep files
focused and under the project's size guideline).

On appear, fetch and zip two sources **by product identifier**:

1. `AvoraPurchases.currentOffering()` → RevenueCat `Package` list, providing the
   localized price string and the purchasable `Package`.
2. `AvoraAPI.fetchCreditPacks()` (new) → `[CreditPack]` = `{ productId, credits, sortOrder }`,
   the authoritative credit amounts.

A pack is displayable only when it appears in **both** sources (a RevenueCat
package with a matching `credit_packs` row). Compute bonus %, pick the featured
pack, sort the rest by price.

Buy flow reuses the existing pattern from `PaywallView.buy`:
`AvoraPurchases.purchase(pkg)` → poll `app.refreshProfile()` until
`totalCredits` increases (bounded retries) → dismiss.

New model: `Avora/Models/CreditPack.swift` — `CreditPack: Codable`
(`productId`, `credits`, `sortOrder`).

## Backend architecture

**New table `credit_packs`** (new migration):

```sql
create table public.credit_packs (
  product_id text primary key,
  credits    int  not null,
  active     bool not null default true,
  sort_order int  not null default 0
);
-- RLS: read-only for authenticated/anon, mirroring credit_config.
```

Seeded with the 5 packs above (product IDs confirmed against RevenueCat).

**`apply_purchase`** gains a credits argument for the extra-pack branch:

- Add `p_credits int` (nullable). In the `extra_pack` branch, grant
  `coalesce(p_credits, (select extra_pack from credit_config))` — so an unknown
  or missing amount falls back to the current fixed behavior, nothing breaks.
- Renewal/initial branches unchanged.

**Webhook** (`revenuecat-webhook/index.ts`), `NON_RENEWING_PURCHASE` branch:

- Read `ev.product_id`, look up `credits` in `credit_packs` (active row).
- Pass it as `p_credits` to `apply_purchase`. Missing/unknown product → pass
  `null` → config fallback.
- The client never sends credit amounts; the server is the source of truth.

**Read path for the app:** a `SELECT` on `credit_packs where active` (via
PostgREST or a small RPC), exposed through `AvoraAPI.fetchCreditPacks()`.

## Error handling

- Offering or packs fail to load → show the balance and a retry affordance, no
  pack cards (never render a buy button without a confirmed price + credits).
- Purchase cancelled by user → stay on screen silently (current behavior).
- Purchase succeeds but the balance poll times out (webhook lag) → dismiss
  anyway; the balance reconciles on the next `refreshProfile()`.
- Unknown product at the webhook → config fallback grant, logged; never a failed
  grant for a real purchase.
- Restore Purchases remains in Settings (unchanged).

## Files

**Create**
- `Avora/Views/Credits/CreditsView.swift` (+ small pack/balance subviews)
- `Avora/Models/CreditPack.swift`
- `supabase/migrations/0000NN_credit_packs.sql` (table + seed + `apply_purchase` change)

**Modify**
- `Avora/Views/Home/StylesGridView.swift` — add balance pill toolbar item
- `Avora/Views/Collection/CollectionView.swift` — add balance pill toolbar item
- `Avora/Views/Create/CreateView.swift` — present `CreditsView` instead of `PaywallView`
- `Avora/Services/AvoraAPI.swift` — `fetchCreditPacks()`
- `supabase/functions/revenuecat-webhook/index.ts` — product → credits lookup

**Delete**
- `Avora/Views/Paywall/PaywallView.swift`

## Out of scope

- Changing prices, credit amounts, or the $9.99 anchor (intentional).
- Restore/subscription changes.
- Analytics on the new screen (can be a follow-up).

## Open items

- Confirm the exact RevenueCat consumable **product identifiers** for the 5 packs
  (the connected MCP key points at a different project, so they must be read from
  the Avora RevenueCat dashboard or the app's live offering).
