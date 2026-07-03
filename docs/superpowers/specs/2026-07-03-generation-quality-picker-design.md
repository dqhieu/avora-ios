# Generation Quality Picker — Design

**Date:** 2026-07-03
**Status:** Approved (pending spec review)

## Summary

Add a quality picker to `CreateView`, presented as a menu to the left of the
Generate button. It offers three options that map to the OpenAI image quality
levels and cost different amounts of credits:

| UI label | Backend `quality` | Cost (credits) |
|----------|-------------------|----------------|
| Default  | `low`             | 20             |
| High     | `medium`          | 30             |
| Ultra    | `high`            | 100            |

Today quality is a per-style column (`styles.default_quality`, currently
`medium` for every style) that the app never sets, and cost is a single flat
`generation_cost` (20) that ignores quality. This feature lets the user choose
quality per generation and makes cost vary accordingly. It is a full-stack
change: iOS UI + app→backend plumbing + per-quality server-side pricing.

## Decisions (resolved during brainstorming)

- **Scope:** Full stack — app picker, send chosen quality, per-quality pricing.
- **Pricing source:** Live in `credit_config` (new per-quality columns), matching
  the existing fetch-with-fallback pattern; tunable server-side without an app release.
- **Default selection:** Always pre-select **Default / low (20)** when `CreateView`
  opens. This makes `styles.default_quality` vestigial for the batch path (the
  client always sends its own choice). The column is left in place, not removed.
- **Menu items** display `Label · cost` (e.g. `Default · 20`) so pricing is transparent.
- **Cleanup (separate commit):** Remove the dead, flat-priced single-image path
  (`submit-generation` edge function + `AvoraAPI.submit()`); leave its orphaned
  DB RPCs in place.

## Non-goals / out of scope

- Dropping the orphaned DB functions `deduct_credit` / `refund_credit_direct`
  (only the removed single-image function called them). Flagged, retained. A
  follow-up migration can drop them if desired.
- Changing `AppState.generations(for:)` (dead code; still reads `generation_cost`).
- Per-style quality restrictions or hiding options per style — all three options
  are always available.

---

## iOS changes

### 1. `GenerationQuality` enum (new file)

`Avora/Models/GenerationQuality.swift` — the single source of the
UI-label → backend-value mapping. Cost is **not** encoded here; it is read from
`CreditConfig` keyed by `backend` so the enum stays purely the mapping.

```swift
enum GenerationQuality: String, CaseIterable, Identifiable {
    case `default`, high, ultra

    var id: String { rawValue }

    /// Value sent to the backend / OpenAI images API.
    var backend: String {
        switch self {
        case .default: "low"
        case .high:    "medium"
        case .ultra:   "high"
        }
    }

    /// User-facing label.
    var label: String {
        switch self {
        case .default: "Default"
        case .high:    "High"
        case .ultra:   "Ultra"
        }
    }
}
```

### 2. `CreditConfig` (extend)

`Avora/Models/CreditConfig.swift` gains three per-quality cost fields plus a
lookup helper. Existing `generationCost` stays (still referenced by the fallback
and by dead `generations(for:)`); it is no longer used for the live generate cost.

```swift
struct CreditConfig: Codable {
    let weeklyAmount: Int
    let signupExtra: Int
    let generationCost: Int
    let extraPack: Int
    let costLow: Int
    let costMedium: Int
    let costHigh: Int

    enum CodingKeys: String, CodingKey {
        case weeklyAmount = "weekly_amount"
        case signupExtra = "signup_extra"
        case generationCost = "generation_cost"
        case extraPack = "extra_pack"
        case costLow = "cost_low"
        case costMedium = "cost_medium"
        case costHigh = "cost_high"
    }

    func cost(for quality: GenerationQuality) -> Int {
        switch quality {
        case .default: costLow
        case .high:    costMedium
        case .ultra:   costHigh
        }
    }

    static let fallback = CreditConfig(
        weeklyAmount: 1000, signupExtra: 50, generationCost: 20, extraPack: 500,
        costLow: 20, costMedium: 30, costHigh: 100
    )
}
```

Note: `fetchCreditConfig()` in `AvoraAPI` must add the three new columns to its
`.select(...)`.

### 3. `CreateView` (UI + generate)

- Add `@State private var quality: GenerationQuality = .default`.
- Selected cost per image: `app.config.cost(for: quality)`.
- Total cost: `sourceImages.count * app.config.cost(for: quality)`.

**Layout** — the `controls` "generate" branch (the `else` of `poller.allTerminal`)
becomes an `HStack` with the menu on the left and the Generate button filling the rest:

- **Quality menu:** a compact glass control (matching existing `avoraGlass` styling)
  showing `quality.label` + a chevron. It wraps a `Picker` bound to `$quality` so
  each item gets a native checkmark; item titles read `"\(q.label) · \(app.config.cost(for: q))"`.
  Disabled while `isWorking`.
- **Generate button:** unchanged `AvoraPrimaryButton`; its stacked credits line
  becomes `"\(sourceImages.count * app.config.cost(for: quality)) credits"`, keeping
  the existing `.contentTransition(.numericText())` and animating on `quality`
  change as well as `sourceImages.count`.

The done-state controls (Save all / Generate again) are unchanged. The menu only
appears in the pre-result state.

### 4. `AvoraAPI.submitBatch` (add quality)

```swift
func submitBatch(styleId: String, inputPaths: [String], quality: String) async throws -> [UUID]
```

- Add `let quality: String` to the encodable `Body` (JSON key `quality`).
- `CreateView.generate()` passes `quality.backend`.
- Mock path (`AvoraConfig.isMockGenerationEnabled`) unchanged — still returns
  random UUIDs, ignoring quality.

---

## Backend changes

### 5. Migration — `supabase/migrations/000027_per_quality_cost.sql`

- Add `cost_low int not null default 20`, `cost_medium int not null default 30`,
  `cost_high int not null default 100` to `credit_config` and backfill the singleton
  row to `20 / 30 / 100`.
- Leave `generation_cost` (20) untouched — the (about-to-be-removed) single path
  and dead `generations(for:)` estimate still read it. Do not depend on removal
  ordering; this migration is self-contained.
- Replace `submit_generations_batch` so `v_cost` is derived from `p_quality`:

```sql
-- inside submit_generations_batch, replacing the flat lookup:
if p_quality not in ('low', 'medium', 'high') then
  raise exception 'bad_quality' using errcode = 'P0001';
end if;

select case p_quality
         when 'low'    then cost_low
         when 'medium' then cost_medium
         when 'high'   then cost_high
       end
  into v_cost
  from public.credit_config;
```

Everything else in the RPC is unchanged: per-row bucket split (weekly first,
then extra), each row storing its own `charged_amount = v_cost`, enqueue, and the
insufficient-credits check (`v_weekly + v_extra < v_needed`). Because each row
records its own `charged_amount`, per-job refunds remain correct at the new prices.

### 6. Edge function — `submit-generation-batch/index.ts`

- Read `quality` from the request body.
- **Validate** it is one of `low` / `medium` / `high`; otherwise return
  `400 { error: "bad_request" }`. This is the security boundary: cost is derived
  server-side from the validated quality, so a client cannot request `high` while
  being charged for `low`.
- Pass the validated `quality` to `submit_generations_batch` **instead of**
  `style.default_quality`. (The `select` of `default_quality` from `styles` can be
  dropped from this function; `active` is still needed.)

---

## Cleanup (separate commit)

### 7. Remove dead single-image path

- Delete directory `supabase/functions/submit-generation/`.
- Delete `AvoraAPI.submit(styleId:inputPath:)`.
- Verified dead: no Swift call sites, no `.ts` / `.sql` / `config.toml` / cron
  references. The batch path (1–4 images) subsumes it.
- **Retain** DB RPCs `deduct_credit` and `refund_credit_direct` (now orphaned).
  Dropping them is higher-risk and out of scope; flagged for an optional follow-up.

---

## Verification

**iOS**
- Build via XcodeBuild MCP (no compile errors).
- Manually: open `CreateView`, confirm menu defaults to **Default**; switching to
  **High** / **Ultra** updates the credits label to `count × 30` / `count × 100`
  with the numeric transition; menu disabled while generating.
- Paywall gate: with credits between two tiers (e.g. 25 credits, 1 photo),
  Default proceeds, Ultra opens the paywall.

**Backend**
- Apply migration locally (`supabase db reset` or migrate up).
- SQL check: `submit_generations_batch` charges `20 / 30 / 100` for
  `low / medium / high`, and raises `bad_quality` for anything else.
- Edge function: a request with `quality: "ultra"` (or missing) returns `400`;
  `quality: "high"` succeeds and the resulting `generations` rows have
  `quality = 'high'` and `charged_amount = 100`.
- End-to-end (mock off): a real Ultra generation deducts 100 credits per image
  and the worker passes `high` to `runEdit`.

## Risks

- **Price tampering** — mitigated: quality is validated server-side and cost is
  derived from `credit_config`, never trusted from the client.
- **Config/model drift** — the app's `CreditConfig.fallback` must mirror the seed
  values (20/30/100); this is the same discipline already noted in
  `CreditConfig.swift`. Keep them in sync.
- **`default_quality` left vestigial** — harmless (still read by the retained
  single-image DB path); documented so a future reader isn't confused.

## Files touched

**Create**
- `Avora/Models/GenerationQuality.swift`
- `supabase/migrations/000027_per_quality_cost.sql`

**Modify**
- `Avora/Models/CreditConfig.swift`
- `Avora/Services/AvoraAPI.swift` (`fetchCreditConfig` select, `submitBatch` signature, remove `submit`)
- `Avora/Views/Create/CreateView.swift`
- `supabase/functions/submit-generation-batch/index.ts`

**Delete**
- `supabase/functions/submit-generation/` (cleanup commit)
