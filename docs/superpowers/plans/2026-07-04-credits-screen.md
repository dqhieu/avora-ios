# Credits Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated Credits screen — reachable from a balance pill beside the Settings gear — showing the user's balance, the weekly subscription plan (1,200 credits/week), and one-time RevenueCat consumable packs to purchase.

**Architecture:** A new `credit_packs` table is the server-side source of truth mapping product ID → credits; the RevenueCat webhook reads it to grant the right amount, and the iOS app fetches it and zips it against the live RevenueCat offering (for localized prices) to render packs. The weekly plan reuses the existing subscription plumbing; the only economics change is raising the weekly grant to 1,200. The screen replaces `PaywallView`.

**Tech Stack:** SwiftUI (iOS 18+, iOS 26 Liquid Glass paths), RevenueCat SDK, Supabase (Postgres + RLS + pgTAP tests, Deno edge functions).

## Global Constraints

- **Product IDs (exact):** `com.hieudinh.Avora.credits500` (500), `com.hieudinh.Avora.credits1000` (1,000), `com.hieudinh.Avora.credits2500` (2,500), `com.hieudinh.Avora.credits4000` (4,000), `com.hieudinh.Avora.credits6000` (6,000), `com.hieudinh.Avora.weekly` (weekly plan).
- **Weekly grant:** 1,200 credits/week (was 1,000). Applies at next renewal; no retroactive top-up.
- **Bonus %:** computed client-side relative to the cheapest pack's credits-per-price. A pack whose bonus rounds to ≤ 1% shows **no badge** (keeps the $9.99 → 1,000 anchor clean). Featured (hero) pack = highest bonus. Expected results: 500 → 0, 1,000 → 0, 2,500 → +25%, 4,000 → +33%, 6,000 → +50% (featured).
- **Server is the source of truth for credit amounts.** The client never sends credit amounts to the backend.
- **Icon:** `centsign.circle` SF Symbol for the balance.
- **Theming:** adaptive light/dark via existing `Color.avora*` tokens, `Font.avora*`, and `Surfaces`/`Layout` helpers. No hardcoded hex.
- **Subscribed state:** show "Active · renews {date}", **no Manage link**.
- **Restore Purchases** stays in Settings (do not add it to the Credits screen).
- Keep files focused (project guideline: prefer < 200 lines; split subviews).

## Verification approach (read once)

This is a SwiftUI **app-only** Xcode project — there is **no unit-test target**, and RevenueCat `Offering`/`Package` cannot be constructed in isolation. So:

- **Pure logic** (`CreditsMath`) is verified by a `#if DEBUG` `#Preview` containing runtime `assert()`s over plain numbers — a real pass/fail signal without a test target.
- **Views** are verified by a `#Preview` (visual check against the approved mockup at `.superpowers/brainstorm/5541-1783154397/content/layout-with-plan.html`) plus a clean compile.
- **iOS build command** (used as the "run tests" step for every iOS task):
  ```bash
  xcodebuild -project Avora.xcodeproj -scheme Avora \
    -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build
  ```
  Expected: `** BUILD SUCCEEDED **`. (Equivalently, XcodeBuildMCP `build_sim`.)
- **Backend** uses real pgTAP tests in `supabase/tests/`, run with:
  ```bash
  supabase start   # once, if not already running
  supabase test db
  ```
  Expected: all files report `ok` / no failing assertions.

---

### Task 1: Backend — `credit_packs` table, variable extra-pack grant, weekly → 1,200

**Files:**
- Create: `supabase/migrations/000028_credit_packs.sql`
- Create: `supabase/tests/060_credit_packs_test.sql`
- Modify: `supabase/tests/050_apply_purchase_test.sql` (weekly assertion 1000 → 1200)

**Interfaces:**
- Produces (SQL):
  - Table `public.credit_packs(product_id text pk, credits int, active bool default true, sort_order int default 0)`, RLS read-only for `authenticated`/`anon`, seeded with the 5 packs.
  - `public.apply_purchase(p_tx text, p_uid uuid, p_kind text, p_period_end timestamptz, p_credits int default null) returns text` — the `extra_pack` branch grants `coalesce(p_credits, credit_config.extra_pack)`. Callers passing 4 args still resolve (default).
  - `credit_config.weekly_amount` = 1200.

- [ ] **Step 1: Update the existing apply_purchase test's weekly expectation**

In `supabase/tests/050_apply_purchase_test.sql`, change the two `1000` references to `1200`:

```sql
-- initial purchase sets weekly to config weekly_amount (1200) and activates
select is(apply_purchase('tx1','66666666-6666-6666-6666-666666666666','initial', now() + interval '7 days'),
          'applied', 'initial purchase applied');
select is((select weekly_credits from public.profiles where id='66666666-6666-6666-6666-666666666666'),
          1200, 'weekly set to config weekly_amount (1200)');
```

(Leave the `extra_pack` → 550 assertions unchanged: a 4-arg call passes `p_credits = null` and falls back to config `extra_pack` = 500.)

- [ ] **Step 2: Write the new pgTAP test for `credit_packs` + variable grant**

Create `supabase/tests/060_credit_packs_test.sql`:

```sql
begin;
select plan(6);

select has_table('public', 'credit_packs', 'credit_packs exists');
select table_privs_are('public', 'credit_packs', 'anon', ARRAY['SELECT'], 'anon can read credit_packs');
select is((select count(*)::int from public.credit_packs), 5, 'five packs seeded');
select is((select credits from public.credit_packs where product_id='com.hieudinh.Avora.credits6000'),
          6000, 'credits6000 pack maps to 6000 credits');

-- variable extra-pack grant: explicit p_credits overrides the config default
insert into auth.users (id, email) values ('77777777-7777-7777-7777-777777777777','g@test.dev');
select is(apply_purchase('tx-var','77777777-7777-7777-7777-777777777777','extra_pack', null, 2500),
          'applied', 'extra_pack with explicit credits applied');
select is((select extra_credits from public.profiles where id='77777777-7777-7777-7777-777777777777'),
          2550, 'extra_pack grants explicit p_credits (50 starter + 2500)');

select * from finish();
rollback;
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `supabase test db`
Expected: FAIL — `060_credit_packs_test.sql` errors (`credit_packs` does not exist / function has no 5th arg), and `050` fails on the 1200 assertion.

- [ ] **Step 4: Write the migration**

Create `supabase/migrations/000028_credit_packs.sql`:

```sql
-- One-time consumable credit packs. product_id → credits is the authoritative
-- mapping the RevenueCat webhook grants from and the app reads to display.
create table public.credit_packs (
  product_id text primary key,
  credits    int  not null,
  active     bool not null default true,
  sort_order int  not null default 0
);

insert into public.credit_packs (product_id, credits, sort_order) values
  ('com.hieudinh.Avora.credits500',  500,  0),
  ('com.hieudinh.Avora.credits1000', 1000, 1),
  ('com.hieudinh.Avora.credits2500', 2500, 2),
  ('com.hieudinh.Avora.credits4000', 4000, 3),
  ('com.hieudinh.Avora.credits6000', 6000, 4);

-- Client-readable (prices come from RevenueCat; only credit amounts live here).
alter table public.credit_packs enable row level security;
revoke all on public.credit_packs from authenticated, anon;
create policy credit_packs_read on public.credit_packs
  for select to authenticated, anon using (true);
grant select on public.credit_packs to authenticated, anon;

-- Raise the weekly grant. Renewal/initial and lazy_weekly_reset already read
-- this value, so subscribers land on 1,200 at their next renewal/reset.
update public.credit_config set weekly_amount = 1200;

-- apply_purchase gains an optional per-purchase credit amount for the
-- extra-pack branch. Unknown/missing amount falls back to config extra_pack.
drop function if exists public.apply_purchase(text, uuid, text, timestamptz);

create or replace function public.apply_purchase(
  p_tx         text,
  p_uid        uuid,
  p_kind       text,          -- 'initial' | 'renewal' | 'extra_pack'
  p_period_end timestamptz,   -- for renewal/initial (ignored for extra_pack)
  p_credits    int default null  -- credits to grant for extra_pack; null → config
)
returns text                  -- 'applied' | 'deduped'
language plpgsql
security definer set search_path = public
as $$
declare
  v_inserted boolean := false;
begin
  insert into public.purchases(transaction_id, user_id, kind)
    values (p_tx, p_uid, p_kind)
    on conflict (transaction_id) do nothing;

  get diagnostics v_inserted = row_count;

  if not v_inserted then
    return 'deduped';
  end if;

  if p_kind in ('renewal', 'initial') then
    update public.profiles
      set weekly_credits          = (select weekly_amount from public.credit_config),
          subscription_period_end = p_period_end,
          subscription_active     = true
      where id = p_uid;
  elsif p_kind = 'extra_pack' then
    update public.profiles
      set extra_credits = extra_credits
        + coalesce(p_credits, (select extra_pack from public.credit_config))
      where id = p_uid;
  end if;

  return 'applied';
end;
$$;

revoke all on function public.apply_purchase(text, uuid, text, timestamptz, int)
  from public, anon, authenticated;
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `supabase db reset && supabase test db`
Expected: `050` and `060` report `ok` for all assertions (`db reset` re-applies migrations including 000028).

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/000028_credit_packs.sql supabase/tests/060_credit_packs_test.sql supabase/tests/050_apply_purchase_test.sql
git commit -m "feat: credit_packs table, variable extra-pack grant, weekly 1200"
```

---

### Task 2: Backend — webhook maps product → credits

**Files:**
- Modify: `supabase/functions/revenuecat-webhook/index.ts` (the `NON_RENEWING_PURCHASE` branch)

**Interfaces:**
- Consumes: `apply_purchase(..., p_credits int)` from Task 1; `credit_packs` table.
- Produces: consumable purchases now grant the pack's mapped credits (fallback to config when the product is unknown).

- [ ] **Step 1: Replace the `NON_RENEWING_PURCHASE` branch**

In `supabase/functions/revenuecat-webhook/index.ts`, replace the existing `NON_RENEWING_PURCHASE` block with:

```ts
  } else if (type === "NON_RENEWING_PURCHASE") {
    // Look up how many credits this product grants. Server is the source of
    // truth; the client never tells us the amount. Unknown product → null,
    // and apply_purchase falls back to config extra_pack.
    const productId: string | undefined = ev.product_id;
    let credits: number | null = null;
    if (productId) {
      const { data: pack } = await db
        .from("credit_packs")
        .select("credits")
        .eq("product_id", productId)
        .eq("active", true)
        .maybeSingle();
      credits = pack?.credits ?? null;
    }

    const { data: result, error: rpcErr } = await db.rpc("apply_purchase", {
      p_tx:          txId,
      p_uid:         uid,
      p_kind:        "extra_pack",
      p_period_end:  null,
      p_credits:     credits,
    });
    if (rpcErr) return json({ error: "purchase_failed" }, 500);
    if (result === "deduped") return json({ ok: true, deduped: true });
    return json({ ok: true });
```

- [ ] **Step 2: Type-check the function**

Run: `deno check supabase/functions/revenuecat-webhook/index.ts`
Expected: no type errors. (Credit-mapping behavior itself is covered by the pgTAP test in Task 1, since the mapping is DB-driven.)

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/revenuecat-webhook/index.ts
git commit -m "feat: webhook grants per-product credits from credit_packs"
```

---

### Task 3: iOS — `CreditPack` model, Profile subscription fields, API reads

**Files:**
- Create: `Avora/Models/CreditPack.swift`
- Modify: `Avora/Models/Profile.swift`
- Modify: `Avora/Services/AvoraAPI.swift` (`fetchProfile` select + new `fetchCreditPacks`)

**Interfaces:**
- Produces:
  - `struct CreditPack: Codable, Identifiable { let productId: String; let credits: Int; let sortOrder: Int; var id: String { productId } }`
  - `Profile.subscriptionActive: Bool`, `Profile.subscriptionPeriodEnd: Date?`
  - `AvoraAPI.fetchCreditPacks() async throws -> [CreditPack]`

- [ ] **Step 1: Create the `CreditPack` model**

Create `Avora/Models/CreditPack.swift`:

```swift
import Foundation

struct CreditPack: Codable, Identifiable {
    let productId: String
    let credits: Int
    let sortOrder: Int

    var id: String { productId }

    enum CodingKeys: String, CodingKey {
        case productId = "product_id"
        case credits
        case sortOrder = "sort_order"
    }
}
```

- [ ] **Step 2: Add subscription fields to `Profile`**

Replace the body of `Avora/Models/Profile.swift` with:

```swift
import Foundation

struct Profile: Codable {
    let weeklyCredits: Int
    let extraCredits: Int
    let subscriptionActive: Bool
    let subscriptionPeriodEnd: Date?
    var totalCredits: Int { weeklyCredits + extraCredits }

    enum CodingKeys: String, CodingKey {
        case weeklyCredits = "weekly_credits"
        case extraCredits = "extra_credits"
        case subscriptionActive = "subscription_active"
        case subscriptionPeriodEnd = "subscription_period_end"
    }
}
```

- [ ] **Step 3: Extend the API reads**

In `Avora/Services/AvoraAPI.swift`, update the `fetchProfile` select to include the subscription columns, and add `fetchCreditPacks`:

```swift
    func fetchProfile() async throws -> Profile {
        let uid = try await currentUserId()
        return try await db.from("profiles")
            .select("weekly_credits,extra_credits,subscription_active,subscription_period_end")
            .eq("id", value: uid.uuidString)
            .single()
            .execute()
            .value
    }

    func fetchCreditPacks() async throws -> [CreditPack] {
        try await db.from("credit_packs")
            .select("product_id,credits,sort_order")
            .eq("active", value: true)
            .order("sort_order")
            .execute()
            .value
    }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build`
Expected: `** BUILD SUCCEEDED **`. (The added non-optional `Bool` decodes from the DB default; `subscription_period_end` is optional so a null is fine.)

- [ ] **Step 5: Commit**

```bash
git add Avora/Models/CreditPack.swift Avora/Models/Profile.swift Avora/Services/AvoraAPI.swift
git commit -m "feat: CreditPack model and subscription-aware profile reads"
```

---

### Task 4: iOS — `CreditsMath` pure economics (bonus %, featured)

**Files:**
- Create: `Avora/Views/Credits/CreditsMath.swift`

**Interfaces:**
- Produces:
  - `struct Priced { let credits: Int; let price: Double }`
  - `CreditsMath.bonusPercents(_ items: [Priced]) -> [Int]` — bonus per item (same order); ≤ 1% → 0.
  - `CreditsMath.featuredIndex(_ items: [Priced]) -> Int?` — index of highest-bonus item (tie → higher credits); nil if no item has a bonus.

- [ ] **Step 1: Write the pure logic + a self-checking preview**

Create `Avora/Views/Credits/CreditsMath.swift`:

```swift
import SwiftUI

/// Pure credit-pack economics — no RevenueCat/SwiftUI dependencies so it can be
/// exercised by the preview asserts below (this project has no unit-test target).
enum CreditsMath {
    struct Priced {
        let credits: Int
        let price: Double
    }

    /// Bonus percent per item vs the cheapest item's credits-per-price.
    /// A bonus that rounds to ≤ 1% is reported as 0 (no badge).
    static func bonusPercents(_ items: [Priced]) -> [Int] {
        guard let base = items.min(by: { $0.price < $1.price }), base.price > 0 else {
            return Array(repeating: 0, count: items.count)
        }
        let baseRate = Double(base.credits) / base.price   // credits per unit price
        return items.map { item in
            let expected = baseRate * item.price
            guard expected > 0 else { return 0 }
            let pct = (Double(item.credits) - expected) / expected * 100
            let rounded = Int(pct.rounded())
            return rounded <= 1 ? 0 : rounded
        }
    }

    /// Index of the featured item: highest bonus, ties broken by higher credits.
    /// Returns nil when no item has a bonus.
    static func featuredIndex(_ items: [Priced]) -> Int? {
        let bonuses = bonusPercents(items)
        var best: Int? = nil
        for i in items.indices where bonuses[i] > 0 {
            if best == nil
                || bonuses[i] > bonuses[best!]
                || (bonuses[i] == bonuses[best!] && items[i].credits > items[best!].credits) {
                best = i
            }
        }
        return best
    }
}

#if DEBUG
#Preview("CreditsMath checks") {
    let packs = [
        CreditsMath.Priced(credits: 500,  price: 4.99),
        CreditsMath.Priced(credits: 1000, price: 9.99),
        CreditsMath.Priced(credits: 2500, price: 19.99),
        CreditsMath.Priced(credits: 4000, price: 29.99),
        CreditsMath.Priced(credits: 6000, price: 39.99),
    ]
    let bonuses = CreditsMath.bonusPercents(packs)
    assert(bonuses == [0, 0, 25, 33, 50], "unexpected bonuses: \(bonuses)")
    assert(CreditsMath.featuredIndex(packs) == 4, "featured should be the 6,000 pack")

    return VStack(alignment: .leading, spacing: 8) {
        Text("✓ bonuses == [0, 0, 25, 33, 50]")
        Text("✓ featured == 6,000 pack")
    }
    .font(.avoraSubheadline)
    .padding()
}
#endif
```

- [ ] **Step 2: Build, and open the preview to confirm the asserts pass**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build`
Expected: `** BUILD SUCCEEDED **`. Open the "CreditsMath checks" preview in Xcode — it renders the two ✓ lines (a failing assert would trap instead).

- [ ] **Step 3: Commit**

```bash
git add Avora/Views/Credits/CreditsMath.swift
git commit -m "feat: pure credit-pack bonus/featured math"
```

---

### Task 5: iOS — balance pill component

**Files:**
- Create: `Avora/Views/Credits/CreditsBalancePill.swift`

**Interfaces:**
- Produces: `CreditsBalancePill(credits: Int, action: () -> Void)` — a toolbar-friendly button showing `centsign.circle` + the formatted balance.

- [ ] **Step 1: Write the pill view + preview**

Create `Avora/Views/Credits/CreditsBalancePill.swift`:

```swift
import SwiftUI

/// Tappable balance chip for the toolbar: credits icon + live balance.
struct CreditsBalancePill: View {
    let credits: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "centsign.circle")
                Text(credits, format: .number).monospacedDigit()
            }
            .font(.avoraSubheadline)
            .foregroundStyle(Color.avoraTextPrimary)
        }
        .accessibilityLabel("Credits: \(credits). Buy more.")
    }
}

#if DEBUG
#Preview("Balance pill") {
    NavigationStack {
        Color.avoraBackground
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CreditsBalancePill(credits: 1240) {}
                }
            }
    }
}
#endif
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Avora/Views/Credits/CreditsBalancePill.swift
git commit -m "feat: credits balance pill"
```

---

### Task 6: iOS — weekly plan card (state-aware)

**Files:**
- Create: `Avora/Views/Credits/WeeklyPlanCard.swift`

**Interfaces:**
- Produces: `WeeklyPlanCard(priceString: String?, isActive: Bool, renewsOn: Date?, onSubscribe: () -> Void)`.
  - Inactive → "1,200 credits / week", "Auto-renews · cancel anytime", primary `Subscribe · {price}/week` CTA (disabled/omitted CTA when `priceString == nil`).
  - Active → "✓ Weekly plan · Active", "1,200 credits / week", "Renews {date}", **no CTA, no Manage link**.

- [ ] **Step 1: Write the card + previews (both states)**

Create `Avora/Views/Credits/WeeklyPlanCard.swift`:

```swift
import SwiftUI

/// Primary weekly-subscription card. State-aware: subscribe CTA when inactive,
/// active status (no manage link) when the user already subscribes.
struct WeeklyPlanCard: View {
    let priceString: String?
    let isActive: Bool
    let renewsOn: Date?
    let onSubscribe: () -> Void

    private static let renews: Date.FormatStyle =
        .dateTime.month(.abbreviated).day()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if isActive {
                Label("Weekly plan · Active", systemImage: "checkmark.seal.fill")
                    .font(.avoraCaption)
                    .foregroundStyle(Color.avoraSuccess)
            } else {
                Text("Weekly plan")
                    .font(.avoraCaption)
                    .foregroundStyle(Color.avoraTextSecondary)
            }

            (Text("1,200 credits").font(.avoraTitle2)
             + Text(" / week").font(.avoraSubheadline).foregroundColor(.avoraTextSecondary))
                .foregroundStyle(Color.avoraTextPrimary)

            if isActive {
                if let renewsOn {
                    Text("Renews \(renewsOn.formatted(Self.renews))")
                        .font(.avoraFootnote)
                        .foregroundStyle(Color.avoraTextSecondary)
                }
            } else {
                Text("Auto-renews · cancel anytime")
                    .font(.avoraFootnote)
                    .foregroundStyle(Color.avoraTextSecondary)
                if let priceString {
                    AvoraPrimaryButton(action: onSubscribe) {
                        Text("Subscribe · \(priceString)/week")
                    }
                    .padding(.top, Spacing.xs)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .avoraElevatedSurface(cornerRadius: Radius.lg)
    }
}

#if DEBUG
#Preview("Weekly plan — states") {
    VStack(spacing: Spacing.lg) {
        WeeklyPlanCard(priceString: "$4.99", isActive: false, renewsOn: nil) {}
        WeeklyPlanCard(priceString: "$4.99", isActive: true,
                       renewsOn: .now.addingTimeInterval(7 * 86_400)) {}
    }
    .padding(Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LinearGradient.avoraBackgroundGradient)
}
#endif
```

- [ ] **Step 2: Build + eyeball both preview states against the mockup**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build`
Expected: `** BUILD SUCCEEDED **`. Preview shows subscribe CTA (inactive) and "Active · Renews …" with no Manage link (active).

- [ ] **Step 3: Commit**

```bash
git add Avora/Views/Credits/WeeklyPlanCard.swift
git commit -m "feat: state-aware weekly plan card"
```

---

### Task 7: iOS — pack cards (featured hero + grid cell)

**Files:**
- Create: `Avora/Views/Credits/CreditPackCard.swift`

**Interfaces:**
- Produces:
  - `struct CreditPackDisplay { let credits: Int; let priceString: String; let bonusPercent: Int; let isFeatured: Bool }`
  - `FeaturedPackCard(pack: CreditPackDisplay, onBuy: () -> Void)` — hero with "Best value · +N%" badge and a primary buy button.
  - `PackGridCell(pack: CreditPackDisplay, onBuy: () -> Void)` — compact tappable cell with an optional `+N%` badge.

Views take **primitive display data only** (no RevenueCat types) so they preview cleanly.

- [ ] **Step 1: Write the cards + preview**

Create `Avora/Views/Credits/CreditPackCard.swift`:

```swift
import SwiftUI

/// Plain display data for a consumable pack (no RevenueCat types → previewable).
struct CreditPackDisplay {
    let credits: Int
    let priceString: String
    let bonusPercent: Int
    let isFeatured: Bool
}

/// Small green "+N%" badge (hidden when bonus is 0).
private struct BonusBadge: View {
    let percent: Int
    let prominent: Bool
    var body: some View {
        Text(prominent ? "Best value · +\(percent)%" : "+\(percent)%")
            .font(.avoraCaption2)
            .foregroundStyle(Color.avoraOnAccent)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(Color.avoraSuccess, in: Capsule())
    }
}

/// Featured hero pack: badge + large credit amount + primary buy button.
struct FeaturedPackCard: View {
    let pack: CreditPackDisplay
    let onBuy: () -> Void

    var body: some View {
        VStack(spacing: Spacing.sm) {
            if pack.bonusPercent > 0 {
                BonusBadge(percent: pack.bonusPercent, prominent: true)
            }
            Text(pack.credits, format: .number)
                .font(.avoraLargeTitle.monospacedDigit())
                .foregroundStyle(Color.avoraTextPrimary)
            Text("credits")
                .font(.avoraFootnote)
                .foregroundStyle(Color.avoraTextSecondary)
            AvoraPrimaryButton(action: onBuy) {
                Text("Buy · \(pack.priceString)")
            }
            .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .avoraElevatedSurface(cornerRadius: Radius.lg)
    }
}

/// Compact grid cell for a non-featured pack.
struct PackGridCell: View {
    let pack: CreditPackDisplay
    let onBuy: () -> Void

    var body: some View {
        Button(action: onBuy) {
            VStack(spacing: Spacing.xs) {
                Text(pack.credits, format: .number)
                    .font(.avoraTitle3.monospacedDigit())
                    .foregroundStyle(Color.avoraTextPrimary)
                Text(pack.priceString)
                    .font(.avoraFootnote)
                    .foregroundStyle(Color.avoraTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .avoraElevatedSurface(cornerRadius: Radius.md)
            .overlay(alignment: .topTrailing) {
                if pack.bonusPercent > 0 {
                    BonusBadge(percent: pack.bonusPercent, prominent: false)
                        .padding(Spacing.sm)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Pack cards") {
    let cols = [GridItem(.flexible(), spacing: Spacing.sm),
                GridItem(.flexible(), spacing: Spacing.sm)]
    return VStack(spacing: Spacing.sm) {
        FeaturedPackCard(pack: .init(credits: 6000, priceString: "$39.99",
                                     bonusPercent: 50, isFeatured: true)) {}
        LazyVGrid(columns: cols, spacing: Spacing.sm) {
            PackGridCell(pack: .init(credits: 500, priceString: "$4.99", bonusPercent: 0, isFeatured: false)) {}
            PackGridCell(pack: .init(credits: 1000, priceString: "$9.99", bonusPercent: 0, isFeatured: false)) {}
            PackGridCell(pack: .init(credits: 2500, priceString: "$19.99", bonusPercent: 25, isFeatured: false)) {}
            PackGridCell(pack: .init(credits: 4000, priceString: "$29.99", bonusPercent: 33, isFeatured: false)) {}
        }
    }
    .padding(Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(LinearGradient.avoraBackgroundGradient)
}
#endif
```

- [ ] **Step 2: Build + compare preview to the mockup**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build`
Expected: `** BUILD SUCCEEDED **`. Featured card shows the "Best value · +50%" badge; the two larger grid cells show `+25%`/`+33%`; 500 and 1,000 show no badge.

- [ ] **Step 3: Commit**

```bash
git add Avora/Views/Credits/CreditPackCard.swift
git commit -m "feat: featured and grid credit pack cards"
```

---

### Task 8: iOS — `CreditsCatalog` + `CreditsView` (assembly, purchase, poll)

**Files:**
- Create: `Avora/Views/Credits/CreditsCatalog.swift`
- Create: `Avora/Views/Credits/CreditsView.swift`

**Interfaces:**
- Consumes: `AvoraPurchases.currentOffering()/purchase(_:)`, `AvoraAPI.fetchCreditPacks()`, `CreditsMath`, `CreditPackDisplay`, `WeeklyPlanCard`, `FeaturedPackCard`, `PackGridCell`, `AppState.profile/refreshProfile()`.
- Produces:
  - `CreditsCatalog.weeklyProductId` constant + `weeklyPackage(offering:)` + `packOptions(packs:offering:)`.
  - `struct CreditPackOption { let display: CreditPackDisplay; let package: Package }`.
  - `CreditsView()` — the screen presented as a sheet.

- [ ] **Step 1: Write the catalog (zips DB packs with the live offering)**

Create `Avora/Views/Credits/CreditsCatalog.swift`:

```swift
import Foundation
import RevenueCat

/// One purchasable consumable pack: display data + the RevenueCat package.
struct CreditPackOption: Identifiable {
    let productId: String
    let display: CreditPackDisplay
    let package: Package
    var id: String { productId }
}

enum CreditsCatalog {
    static let weeklyProductId = "com.hieudinh.Avora.weekly"

    /// The weekly subscription package in the current offering, if present.
    static func weeklyPackage(offering: Offering) -> Package? {
        offering.availablePackages.first {
            $0.storeProduct.productIdentifier == weeklyProductId
        }
    }

    /// Zip DB packs with RevenueCat packages (matched by product id), compute
    /// bonus %, mark the featured pack, and sort by price ascending.
    static func packOptions(packs: [CreditPack], offering: Offering) -> [CreditPackOption] {
        let byId = Dictionary(
            offering.availablePackages.map { ($0.storeProduct.productIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        struct Row { let pack: CreditPack; let package: Package; let price: Double }
        let rows: [Row] = packs.compactMap { pack in
            guard let pkg = byId[pack.productId] else { return nil }
            let price = NSDecimalNumber(decimal: pkg.storeProduct.price).doubleValue
            guard price > 0 else { return nil }
            return Row(pack: pack, package: pkg, price: price)
        }
        guard !rows.isEmpty else { return [] }

        let priced = rows.map { CreditsMath.Priced(credits: $0.pack.credits, price: $0.price) }
        let bonuses = CreditsMath.bonusPercents(priced)
        let featured = CreditsMath.featuredIndex(priced)

        let options = rows.indices.map { i -> CreditPackOption in
            CreditPackOption(
                productId: rows[i].pack.productId,
                display: CreditPackDisplay(
                    credits: rows[i].pack.credits,
                    priceString: rows[i].package.storeProduct.localizedPriceString,
                    bonusPercent: bonuses[i],
                    isFeatured: i == featured
                ),
                package: rows[i].package
            )
        }
        return options.sorted { $0.display.credits < $1.display.credits }
    }
}
```

- [ ] **Step 2: Write `CreditsView`**

Create `Avora/Views/Credits/CreditsView.swift`:

```swift
import SwiftUI
import RevenueCat

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var app

    @State private var offering: Offering?
    @State private var packOptions: [CreditPackOption] = []
    @State private var weeklyPackage: Package?
    @State private var busy = false
    @State private var loadFailed = false

    private let cols = [GridItem(.flexible(), spacing: Spacing.sm),
                        GridItem(.flexible(), spacing: Spacing.sm)]

    private var featured: CreditPackOption? { packOptions.first { $0.display.isFeatured } }
    private var gridPacks: [CreditPackOption] { packOptions.filter { !$0.display.isFeatured } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    balanceHeader

                    WeeklyPlanCard(
                        priceString: weeklyPackage?.storeProduct.localizedPriceString,
                        isActive: app.profile?.subscriptionActive ?? false,
                        renewsOn: app.profile?.subscriptionPeriodEnd,
                        onSubscribe: { if let p = weeklyPackage { Task { await buy(p) } } }
                    )

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
                }
                .padding(Spacing.lg)
                .disabled(busy)
            }
            .background(LinearGradient.avoraBackgroundGradient.ignoresSafeArea())
            .navigationTitle("Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(busy)
                }
            }
            .task { await load() }
        }
    }

    private var balanceHeader: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "centsign.circle")
                .font(.avoraTitle2)
            Text(app.profile?.totalCredits ?? 0, format: .number)
                .font(.avoraLargeTitle.monospacedDigit())
        }
        .foregroundStyle(Color.avoraTextPrimary)
        .padding(.top, Spacing.sm)
    }

    private var sectionLabel: some View {
        Text("One-time packs")
            .font(.avoraCaption)
            .foregroundStyle(Color.avoraTextTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var retry: some View {
        ContentUnavailableView {
            Label("Couldn’t load packs", systemImage: "exclamationmark.triangle")
        } actions: {
            Button("Retry") { Task { await load() } }
        }
    }

    private func load() async {
        loadFailed = false
        async let offeringTask = AvoraPurchases.currentOffering()
        async let packsTask = AvoraAPI.shared.fetchCreditPacks()
        let off = try? await offeringTask
        let packs = (try? await packsTask) ?? []
        guard let off else { loadFailed = true; return }
        offering = off
        weeklyPackage = CreditsCatalog.weeklyPackage(offering: off)
        packOptions = CreditsCatalog.packOptions(packs: packs, offering: off)
        if packOptions.isEmpty { loadFailed = true }
    }

    private func buy(_ package: Package) async {
        busy = true
        defer { busy = false }
        do {
            let before = app.profile?.totalCredits ?? 0
            let wasActive = app.profile?.subscriptionActive ?? false
            try await AvoraPurchases.purchase(package)
            // Credits/subscription arrive via the RevenueCat webhook → backend;
            // poll the profile until it reflects the purchase.
            for _ in 0..<10 {
                await app.refreshProfile()
                let now = app.profile
                if (now?.totalCredits ?? 0) > before
                    || (now?.subscriptionActive ?? false) && !wasActive { break }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            dismiss()
        } catch {
            // User cancelled or purchase failed; stay on the screen.
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Avora/Views/Credits/CreditsCatalog.swift Avora/Views/Credits/CreditsView.swift
git commit -m "feat: CreditsView with plan and consumable packs"
```

---

### Task 9: iOS — wire entry points, replace PaywallView

**Files:**
- Modify: `Avora/Views/Home/StylesGridView.swift`
- Modify: `Avora/Views/Collection/CollectionView.swift`
- Modify: `Avora/Views/Create/CreateView.swift`
- Delete: `Avora/Views/Paywall/PaywallView.swift`

**Interfaces:**
- Consumes: `CreditsView`, `CreditsBalancePill`, `AppState.profile`.

- [ ] **Step 1: Add the pill + Credits sheet to Home**

In `Avora/Views/Home/StylesGridView.swift`, add state, a leading toolbar pill, and the sheet. Add near the other `@State`:

```swift
    @State private var showCredits = false
```

Replace the `.toolbar { ... }` block with a trailing group so the pill sits
immediately left of the gear (both on the right, per spec):

```swift
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let credits = app.profile?.totalCredits {
                    CreditsBalancePill(credits: credits) { showCredits = true }
                }
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showCredits) {
            NavigationStack { CreditsView().environment(app) }
        }
```

(Leave the existing `.sheet(isPresented: $showSettings)` as-is.)

- [ ] **Step 2: Add the pill + Credits sheet to Collection**

In `Avora/Views/Collection/CollectionView.swift`, add `@State private var showCredits = false` near the other state, then mirror the same `.toolbar` leading item and `.sheet(isPresented: $showCredits)` additions as in Step 1.

- [ ] **Step 3: Point CreateView's out-of-credits path at CreditsView**

In `Avora/Views/Create/CreateView.swift`, rename the paywall flag and swap the sheet. Change:

```swift
    @State private var showPaywall = false
```
to
```swift
    @State private var showCredits = false
```

Update the two assignment sites (`showPaywall = true` at the credit pre-check and in the `catch AvoraError.insufficientCredits` branch) to `showCredits = true`, and change the sheet line:

```swift
        .sheet(isPresented: $showCredits) { CreditsView().environment(app) }
```

- [ ] **Step 4: Delete PaywallView**

```bash
git rm Avora/Views/Paywall/PaywallView.swift
```

- [ ] **Step 5: Build to confirm nothing references PaywallView**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' -quiet build`
Expected: `** BUILD SUCCEEDED **` (a leftover `PaywallView` reference would fail here).

- [ ] **Step 6: Run in the simulator and verify the flow**

Run the app (XcodeBuildMCP `build_run_sim`, or ⌘R). Verify: the balance pill appears beside the gear on Home and Collection; tapping it opens Credits showing the weekly plan card + featured pack + grid; the "Done" button dismisses; from a zero-credit generation attempt, `CreateView` opens the same Credits screen.

- [ ] **Step 7: Commit**

```bash
git add Avora/Views/Home/StylesGridView.swift Avora/Views/Collection/CollectionView.swift Avora/Views/Create/CreateView.swift
git commit -m "feat: credits pill entry points; replace paywall with CreditsView"
```

---

## Self-Review

**Spec coverage:**
- Entry-point balance pill (both screens) → Tasks 5, 9. ✓
- `centsign.circle` + balance, no generations line → Tasks 5, 8. ✓
- Weekly plan card, state-aware, no Manage link → Task 6, rendered in Task 8. ✓
- 1,200/week, next-renewal rollout → Task 1 (`weekly_amount` = 1200; reuses renewal path). ✓
- Five packs, bonus math (0/0/25/33/50), featured = highest bonus, $9.99 no badge → Tasks 4, 7, 8. ✓
- Storefront layout (featured hero + 2×2 grid), adaptive light/dark → Tasks 7, 8. ✓
- `credit_packs` source of truth; webhook grants per product; client never sends amounts → Tasks 1, 2, 8. ✓
- Product IDs recorded and seeded → Task 1. ✓
- Profile exposes subscription state → Task 3. ✓
- Replace PaywallView; CreateView routes to CreditsView → Task 9. ✓
- Restore stays in Settings (untouched) → no task needed. ✓
- Error handling: load failure retry, cancel silent, poll-timeout dismiss → Task 8. ✓

**Type consistency:** `CreditPack`(Task 3) → `CreditsMath.Priced`(4) → `CreditPackDisplay`(7) → `CreditPackOption`(8) chain is consistent; view components consume primitives; `AvoraPurchases.purchase(_:)`/`currentOffering()` and `AppState.refreshProfile()` match existing signatures.

**Placeholder scan:** no TBD/TODO; every code step is complete.
