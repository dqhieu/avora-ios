# Generation Quality Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a quality picker to `CreateView` (a menu left of the Generate button) whose three options change both the image quality sent to the backend and the credits charged.

**Architecture:** A new `GenerationQuality` enum owns the UI-label → backend-value mapping (Default→`low`, High→`medium`, Ultra→`high`). Per-quality prices live in `credit_config` (new columns, 20/30/100), and `submit_generations_batch` derives cost from the client-chosen, server-validated quality. The app sends the chosen quality through `submitBatch`; the edge function validates it and forwards it to the RPC instead of the style's `default_quality`. A final cleanup commit removes the now-dead flat-priced single-image path.

**Tech Stack:** Supabase (Postgres/plpgsql, pgTAP, Deno edge functions, pgmq), Swift/SwiftUI, PhotosUI.

## Global Constraints

- Quality mapping (UI label → backend `quality` → credits): **Default → `low` → 20**, **High → `medium` → 30**, **Ultra → `high` → 100**.
- Valid backend quality values are exactly **`low`**, **`medium`**, **`high`**. Anything else is rejected (`400` in the edge function, `bad_quality` P0001 in the RPC).
- Prices are the source of truth in `credit_config` (`cost_low` / `cost_medium` / `cost_high`); the app mirrors them only as offline fallbacks and must keep them in sync (20/30/100).
- Cost is **always derived server-side** from the validated quality — never trusted from the client body.
- Batch size is **1–4** photos (unchanged).
- Insufficient credits is signaled by SQLSTATE **`P0001`** with message containing `insufficient_credits`, mapped by the edge function to **HTTP 402** (unchanged).
- Default pre-selected quality when `CreateView` opens is **Default / `low`**. `styles.default_quality` is left in place but becomes vestigial for the batch path.
- New migration file is **`supabase/migrations/000027_per_quality_cost.sql`** (next after `000026`).
- No iOS unit-test target exists; iOS tasks are verified by a successful build (and a manual sim run for the UI task). Backend RPC changes use pgTAP via `supabase test db` (with `supabase db reset` to reapply migrations). `deno` is not installed, so edge-function changes are verified by review + the end-to-end smoke path, not a local type-check.

---

### Task 1: Per-quality pricing — `credit_config` columns + `submit_generations_batch` RPC

**Files:**
- Create: `supabase/migrations/000027_per_quality_cost.sql`
- Test: `supabase/tests/031_batch_submit_test.sql` (rewrite existing)

**Interfaces:**
- Consumes: `public.credit_config` (singleton row), `public.profiles`, `public.generations`, `public.pgmq_send(text, jsonb)`.
- Produces: `submit_generations_batch(p_uid uuid, p_style_id text, p_input_paths text[], p_quality text) returns uuid[]` — same signature as today, but `v_cost` is derived from `p_quality` (`low`=`cost_low`, `medium`=`cost_medium`, `high`=`cost_high`) and an unknown `p_quality` raises `bad_quality` (P0001). New columns `credit_config.cost_low/cost_medium/cost_high` (int, 20/30/100).

- [ ] **Step 1: Rewrite the pgTAP test to expect per-quality pricing**

Replace the entire contents of `supabase/tests/031_batch_submit_test.sql` with:

```sql
begin;
select plan(14);

insert into auth.users (id, email) values ('55555555-5555-5555-5555-555555555555','e@test.dev');
insert into public.styles (id, name, prompt_template) values ('bs1','BS1','x');
-- credit_config seeds cost_low=20, cost_medium=30, cost_high=100

-- LOW: 20/img. weekly 100, batch of 2 low = 40 -> weekly 60.
update public.profiles set weekly_credits = 100, extra_credits = 0
  where id = '55555555-5555-5555-5555-555555555555';
select is(
  array_length(
    submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
      array['55555555-5555-5555-5555-555555555555/a.png',
            '55555555-5555-5555-5555-555555555555/b.png'], 'low'), 1),
  2, 'low: returns 2 job ids');
select is((select weekly_credits from public.profiles where id='55555555-5555-5555-5555-555555555555'),
          60, 'low: weekly 100 -> 60 (2 x 20)');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555'
               and charged_amount=20 and quality='low'),
          2, 'low: each row charged 20 and stored quality low');

-- MEDIUM: 30/img. reset weekly 100, batch of 2 medium = 60 -> weekly 40.
delete from public.generations where user_id='55555555-5555-5555-5555-555555555555';
update public.profiles set weekly_credits = 100, extra_credits = 0
  where id = '55555555-5555-5555-5555-555555555555';
select is(
  array_length(
    submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
      array['55555555-5555-5555-5555-555555555555/a.png',
            '55555555-5555-5555-5555-555555555555/b.png'], 'medium'), 1),
  2, 'medium: returns 2 job ids');
select is((select weekly_credits from public.profiles where id='55555555-5555-5555-5555-555555555555'),
          40, 'medium: weekly 100 -> 40 (2 x 30)');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555'
               and charged_amount=30 and quality='medium'),
          2, 'medium: each row charged 30 and stored quality medium');

-- HIGH: 100/img. reset weekly 100, batch of 1 high = 100 -> weekly 0.
delete from public.generations where user_id='55555555-5555-5555-5555-555555555555';
update public.profiles set weekly_credits = 100, extra_credits = 0
  where id = '55555555-5555-5555-5555-555555555555';
select is(
  array_length(
    submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
      array['55555555-5555-5555-5555-555555555555/a.png'], 'high'), 1),
  1, 'high: returns 1 job id');
select is((select weekly_credits from public.profiles where id='55555555-5555-5555-5555-555555555555'),
          0, 'high: weekly 100 -> 0 (1 x 100)');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555'
               and charged_amount=100 and quality='high'),
          1, 'high: row charged 100 and stored quality high');

-- STRADDLE at medium: weekly 30 + extra 30, batch of 2 medium = 60 -> one weekly, one extra.
delete from public.generations where user_id='55555555-5555-5555-5555-555555555555';
update public.profiles set weekly_credits = 30, extra_credits = 30
  where id = '55555555-5555-5555-5555-555555555555';
perform submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
  array['55555555-5555-5555-5555-555555555555/a.png',
        '55555555-5555-5555-5555-555555555555/b.png'], 'medium');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555' and charged_bucket='weekly'),
          1, 'straddle: one row charged to weekly');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555' and charged_bucket='extra'),
          1, 'straddle: one row charged to extra');

-- BAD QUALITY: raises before any credit math (fires even with 0 credits).
select throws_ok(
  $$ select submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
       array['55555555-5555-5555-5555-555555555555/c.png'], 'ultra') $$,
  'P0001', 'bad_quality', 'unknown quality raises bad_quality');

-- INSUFFICIENT: high needs 100, only 50 available -> raises and deducts nothing.
delete from public.generations where user_id='55555555-5555-5555-5555-555555555555';
update public.profiles set weekly_credits = 50, extra_credits = 0
  where id = '55555555-5555-5555-5555-555555555555';
select throws_ok(
  $$ select submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
       array['55555555-5555-5555-5555-555555555555/d.png'], 'high') $$,
  'P0001', 'insufficient_credits', 'high raises when total < needed');
select is((select weekly_credits from public.profiles where id='55555555-5555-5555-5555-555555555555'),
          50, 'weekly untouched after failed high batch (all-or-nothing)');

select * from finish();
rollback;
```

Note: pgTAP runs inside a `begin/rollback`, so `perform` must be wrapped — replace the bare `perform ...` line with a `do $$ begin perform ...; end $$;` block if your pgTAP version rejects top-level `perform`. Equivalent form:

```sql
do $$ begin
  perform submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
    array['55555555-5555-5555-5555-555555555555/a.png',
          '55555555-5555-5555-5555-555555555555/b.png'], 'medium');
end $$;
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `supabase db reset && supabase test db`
Expected: FAIL — `031_batch_submit_test.sql` fails on the LOW/MEDIUM/HIGH cost assertions (current RPC charges a flat 20 and has no `cost_*` columns / no `bad_quality` check).

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/000027_per_quality_cost.sql`:

```sql
-- Per-quality generation pricing. credit_config gains one column per quality
-- level; submit_generations_batch derives cost from the (validated) quality the
-- client chose instead of the flat generation_cost. Costs: low=20, medium=30, high=100.
-- generation_cost is left in place (still read by the single-image path).

alter table public.credit_config
  add column cost_low    int not null default 20,
  add column cost_medium int not null default 30,
  add column cost_high   int not null default 100;

-- Backfill the singleton row explicitly (defaults already cover it; explicit is clearer).
update public.credit_config set cost_low = 20, cost_medium = 30, cost_high = 100;

create or replace function public.submit_generations_batch(
  p_uid uuid,
  p_style_id text,
  p_input_paths text[],
  p_quality text
)
returns uuid[]
language plpgsql
security definer set search_path = public
as $$
declare
  v_cost   int;
  v_count  int := coalesce(array_length(p_input_paths, 1), 0);
  v_needed int;
  v_weekly int;
  v_extra  int;
  v_path   text;
  v_bucket text;
  v_id     uuid;
  v_ids    uuid[] := '{}';
begin
  if v_count < 1 or v_count > 4 then
    raise exception 'bad_batch_size' using errcode = 'P0001';
  end if;

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

  v_needed := v_count * v_cost;

  -- lock the profile so concurrent submits serialize on this row
  select weekly_credits, extra_credits into v_weekly, v_extra
    from public.profiles where id = p_uid for update;

  if v_weekly + v_extra < v_needed then
    raise exception 'insufficient_credits' using errcode = 'P0001';
  end if;

  foreach v_path in array p_input_paths loop
    if v_weekly >= v_cost then
      v_weekly := v_weekly - v_cost;
      v_bucket := 'weekly';
    else
      v_extra := v_extra - v_cost;
      v_bucket := 'extra';
    end if;

    insert into public.generations
      (user_id, style_id, status, charged_bucket, charged_amount, input_path, quality)
      values (p_uid, p_style_id, 'pending', v_bucket, v_cost, v_path, p_quality)
      returning id into v_id;

    perform public.pgmq_send('generations', jsonb_build_object('job_id', v_id));
    v_ids := array_append(v_ids, v_id);
  end loop;

  update public.profiles
    set weekly_credits = v_weekly, extra_credits = v_extra
    where id = p_uid;

  return v_ids;
end;
$$;

revoke all on function public.submit_generations_batch(uuid, text, text[], text)
  from public, anon, authenticated;
-- only the service role (used by Edge Functions) may call this.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `supabase db reset && supabase test db`
Expected: PASS — `031_batch_submit_test.sql` reports `ok 1..14` with no failures. Other test files still pass.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/000027_per_quality_cost.sql supabase/tests/031_batch_submit_test.sql
git commit -m "feat: per-quality generation pricing in credit_config and batch RPC"
```

---

### Task 2: Edge function forwards client-chosen, validated quality

**Files:**
- Modify: `supabase/functions/submit-generation-batch/index.ts`

**Interfaces:**
- Consumes: `submit_generations_batch` RPC (Task 1), `lazy_weekly_reset` RPC, `_shared/cors.ts` (`handleOptions`, `json`), `_shared/supabase.ts` (`requireUser`, `serviceClient`).
- Produces: `POST /submit-generation-batch` now also requires `quality: "low" | "medium" | "high"` in the body; returns `400 { error: "bad_request" }` if missing/invalid. On success forwards `quality` to the RPC as `p_quality` (no longer uses `style.default_quality`).

- [ ] **Step 1: Update the edge function**

Replace the entire contents of `supabase/functions/submit-generation-batch/index.ts` with:

```ts
import { handleOptions, json } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pre = handleOptions(req); if (pre) return pre;
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let uid: string;
  try { uid = await requireUser(req); } catch { return json({ error: "unauthorized" }, 401); }

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* leave empty */ }
  const { style_id, input_paths, quality } = body;
  if (typeof style_id !== "string" || !Array.isArray(input_paths)) {
    return json({ error: "bad_request" }, 400);
  }
  // Cost is derived server-side from this value, so it must be validated here.
  if (typeof quality !== "string" || !["low", "medium", "high"].includes(quality)) {
    return json({ error: "bad_request" }, 400);
  }
  if (input_paths.length < 1 || input_paths.length > 4 ||
      !input_paths.every((p) => typeof p === "string")) {
    return json({ error: "bad_batch_size" }, 400);
  }
  // every path must belong to this user: "<uid>/<file>"
  if (!input_paths.every((p) => (p as string).startsWith(`${uid}/`))) {
    return json({ error: "forbidden_path" }, 403);
  }

  const db = serviceClient();

  // style must exist and be active
  const { data: style } = await db.from("styles")
    .select("id, active").eq("id", style_id).single();
  if (!style || !style.active) return json({ error: "unknown_style" }, 400);

  // validate each input file (format/size) via Storage list + metadata
  for (const path of input_paths as string[]) {
    const slashIndex = path.indexOf("/");
    const folder = path.slice(0, slashIndex);
    const filename = path.slice(slashIndex + 1);
    const { data: fileList, error: listErr } = await db.storage
      .from("inputs").list(folder, { search: filename });
    const fileMeta = fileList?.find((f) => f.name === filename);
    if (listErr || !fileMeta) return json({ error: "input_not_found" }, 400);
    const contentType = fileMeta.metadata?.mimetype ?? "";
    const size = fileMeta.metadata?.size ?? Infinity;
    if (!["image/png", "image/jpeg"].includes(contentType) || size > 10 * 1024 * 1024) {
      return json({ error: "invalid_input" }, 400);
    }
  }

  // webhook backstop, then atomic all-or-nothing batch submit
  await db.rpc("lazy_weekly_reset", { p_uid: uid });
  const { data: jobIds, error: rpcErr } = await db.rpc("submit_generations_batch", {
    p_uid: uid,
    p_style_id: style_id,
    p_input_paths: input_paths,
    p_quality: quality,
  });
  if (rpcErr) {
    if (rpcErr.code === "P0001" && rpcErr.message.includes("insufficient_credits"))
      return json({ error: "insufficient_credits" }, 402);
    return json({ error: "submit_failed" }, 500);
  }

  return json({ job_ids: jobIds }, 202);
});
```

Changes from the current file: destructure `quality` from the body; add the `low/medium/high` validation block; drop `default_quality` from the `styles` select; pass `p_quality: quality` instead of `p_quality: style.default_quality`.

- [ ] **Step 2: Verify by review (no local deno)**

`deno` is not installed locally. Confirm by inspection that: (a) `quality` is validated against `["low","medium","high"]` before use, (b) `style` select no longer references `default_quality`, (c) the RPC call passes `p_quality: quality`. The runtime path is exercised end-to-end in Task 6's manual run and the backend smoke test.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/submit-generation-batch/index.ts
git commit -m "feat: accept and validate client-chosen quality in batch submit"
```

---

### Task 3: `GenerationQuality` enum (iOS)

**Files:**
- Create: `Avora/Models/GenerationQuality.swift`

**Interfaces:**
- Produces: `enum GenerationQuality: String, CaseIterable, Identifiable` with `case default, high, ultra`; `var backend: String` (→ `"low"`/`"medium"`/`"high"`); `var label: String` (→ `"Default"`/`"High"`/`"Ultra"`); `var id: String`.

- [ ] **Step 1: Create the enum**

Create `Avora/Models/GenerationQuality.swift`:

```swift
import Foundation

/// User-selectable generation quality. Owns the mapping from the UI-facing label
/// to the backend `quality` value sent to the image API. Cost is not encoded here
/// — it is read from `CreditConfig` keyed by `backend`.
enum GenerationQuality: String, CaseIterable, Identifiable {
    case `default`, high, ultra

    var id: String { rawValue }

    /// Value sent to the backend (maps to the OpenAI images `quality` field).
    var backend: String {
        switch self {
        case .default: "low"
        case .high:    "medium"
        case .ultra:   "high"
        }
    }

    /// User-facing label shown in the picker.
    var label: String {
        switch self {
        case .default: "Default"
        case .high:    "High"
        case .ultra:   "Ultra"
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `** BUILD SUCCEEDED **`. (Equivalent: XcodeBuildMCP `build_sim` with the session's project/scheme/simulator defaults.)

- [ ] **Step 3: Commit**

```bash
git add Avora/Models/GenerationQuality.swift
git commit -m "feat: add GenerationQuality enum"
```

---

### Task 4: Per-quality cost on `CreditConfig` (iOS)

**Files:**
- Modify: `Avora/Models/CreditConfig.swift`
- Modify: `Avora/Services/AvoraAPI.swift:36-42` (`fetchCreditConfig` select)

**Interfaces:**
- Consumes: `GenerationQuality` (Task 3).
- Produces: `CreditConfig` gains `costLow`, `costMedium`, `costHigh: Int` (JSON keys `cost_low`/`cost_medium`/`cost_high`) and `func cost(for quality: GenerationQuality) -> Int`. `AvoraAPI.fetchCreditConfig()` selects the three new columns.

- [ ] **Step 1: Extend `CreditConfig`**

Replace the entire contents of `Avora/Models/CreditConfig.swift` with:

```swift
import Foundation

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

    /// Credits charged per image for the given quality.
    func cost(for quality: GenerationQuality) -> Int {
        switch quality {
        case .default: costLow
        case .high:    costMedium
        case .ultra:   costHigh
        }
    }

    /// Baked-in defaults so the app works offline and before the first fetch.
    /// Must mirror the seed row in migrations 000020_credit_config.sql and
    /// 000027_per_quality_cost.sql.
    static let fallback = CreditConfig(
        weeklyAmount: 1000, signupExtra: 50, generationCost: 20, extraPack: 500,
        costLow: 20, costMedium: 30, costHigh: 100
    )
}
```

- [ ] **Step 2: Add the new columns to the fetch select**

In `Avora/Services/AvoraAPI.swift`, update `fetchCreditConfig()` (currently selecting `"weekly_amount,signup_extra,generation_cost,extra_pack"`):

```swift
    func fetchCreditConfig() async throws -> CreditConfig {
        try await db.from("credit_config")
            .select("weekly_amount,signup_extra,generation_cost,extra_pack,cost_low,cost_medium,cost_high")
            .single()
            .execute()
            .value
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Avora/Models/CreditConfig.swift Avora/Services/AvoraAPI.swift
git commit -m "feat: per-quality cost lookup on CreditConfig"
```

---

### Task 5: `submitBatch` sends quality (iOS)

**Files:**
- Modify: `Avora/Services/AvoraAPI.swift:71-88` (`submitBatch`)

**Interfaces:**
- Produces: `func submitBatch(styleId: String, inputPaths: [String], quality: String) async throws -> [UUID]` — adds `quality` to the JSON body (`quality` key). Mock path unchanged (returns random UUIDs).

- [ ] **Step 1: Add the `quality` parameter**

In `Avora/Services/AvoraAPI.swift`, replace `submitBatch(styleId:inputPaths:)` with:

```swift
    func submitBatch(styleId: String, inputPaths: [String], quality: String) async throws -> [UUID] {
        #if DEBUG
        if AvoraConfig.isMockGenerationEnabled { return inputPaths.map { _ in UUID() } }
        #endif
        struct Body: Encodable { let style_id: String; let input_paths: [String]; let quality: String }
        struct Resp: Decodable { let job_ids: [UUID] }
        do {
            let resp: Resp = try await db.functions.invoke(
                "submit-generation-batch",
                options: .init(body: Body(style_id: styleId, input_paths: inputPaths, quality: quality))
            )
            return resp.job_ids
        } catch let FunctionsError.httpError(code: code, data: _) where code == 402 {
            throw AvoraError.insufficientCredits
        } catch let FunctionsError.httpError(code: code, data: _) {
            throw AvoraError.server(code)
        }
    }
```

Note: this makes `CreateView.swift:247` a compile error until Task 6 (it calls `submitBatch` without `quality`). If executing tasks strictly one-at-a-time with a build gate, do this step and Task 6 Step 1 together before building; otherwise proceed to Task 6.

- [ ] **Step 2: Commit**

```bash
git add Avora/Services/AvoraAPI.swift
git commit -m "feat: submitBatch forwards selected quality"
```

---

### Task 6: Quality menu in `CreateView` (iOS)

**Files:**
- Modify: `Avora/Views/Create/CreateView.swift`

**Interfaces:**
- Consumes: `GenerationQuality` (Task 3), `CreditConfig.cost(for:)` (Task 4), `submitBatch(styleId:inputPaths:quality:)` (Task 5), `avoraGlass(in:)` and `AvoraPrimaryButton` (`DesignSystem/Surfaces.swift`), `Spacing`, `Radius`, `Color.avoraTextPrimary`, `Color.avoraOnAccent`, `.avoraButton` / `.avoraCaption` fonts.
- Produces: a `quality` state and a `qualityMenu` view; the generate controls become an `HStack` of `[qualityMenu, AvoraPrimaryButton]`; cost display and `generate()` use `app.config.cost(for: quality)`.

- [ ] **Step 1: Add quality state**

In `Avora/Views/Create/CreateView.swift`, add to the `@State` block (near line 13):

```swift
    @State private var quality: GenerationQuality = .default
```

- [ ] **Step 2: Replace the generate-controls branch**

In the `controls` computed property, replace the `else` branch (the `AvoraPrimaryButton { Task { await generate() } } ...` block currently at lines 182–201) with:

```swift
        } else {
            HStack(spacing: Spacing.md) {
                qualityMenu
                AvoraPrimaryButton { Task { await generate() } } label: {
                    if isWorking {
                        HStack(spacing: Spacing.sm) {
                            ProgressView().tint(Color.avoraOnAccent)
                            GeneratingLabel(isActive: isWorking)
                        }
                    } else {
                        VStack(spacing: Spacing.xs) {
                            Label("Generate", systemImage: "wand.and.stars")
                            Text("\(sourceImages.count * app.config.cost(for: quality)) credits")
                                .font(.avoraCaption)
                                .opacity(0.85)
                                .contentTransition(.numericText())
                                .animation(.snappy, value: sourceImages.count)
                                .animation(.snappy, value: quality)
                        }
                    }
                }
                .disabled(sourceImages.isEmpty || isWorking)
            }
        }
```

- [ ] **Step 3: Add the `qualityMenu` view**

Add this computed property to `CreateView` (e.g. directly above `controls`):

```swift
    // Compact glass menu, left of the Generate button. Each option shows its
    // per-image credit cost so pricing is transparent before choosing.
    private var qualityMenu: some View {
        Menu {
            Picker("Quality", selection: $quality) {
                ForEach(GenerationQuality.allCases) { q in
                    Text("\(q.label) · \(app.config.cost(for: q))").tag(q)
                }
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Text(quality.label)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.avoraCaption)
            }
            .font(.avoraButton)
            .foregroundStyle(Color.avoraTextPrimary)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 56)
            .avoraGlass(in: Capsule())
        }
        .disabled(isWorking)
    }
```

- [ ] **Step 4: Use the selected quality in `generate()`**

In `generate()`, update the cost line (currently `let cost = imgs.count * app.config.generationCost` at line 225) and the submit call (line 247):

```swift
        let cost = imgs.count * app.config.cost(for: quality)
```

```swift
            let jobIds = try await AvoraAPI.shared.submitBatch(
                styleId: style.id, inputPaths: paths, quality: quality.backend)
```

- [ ] **Step 5: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual sim verification**

Run the app in the simulator (XcodeBuildMCP `build_run_sim`). In a style's `CreateView`:
- The menu sits to the left of Generate and defaults to **Default**.
- Pick a photo: Generate shows `20 credits`. Switch the menu to **High** → `30 credits`; **Ultra** → `100 credits`, animating with the numeric transition. With N photos the number is `N ×` the per-image cost.
- The menu items read `Default · 20`, `High · 30`, `Ultra · 100` with a checkmark on the selected one.
- While generating, the menu is disabled.
- (Optional, with mock generation off and a real account) A generation started at Ultra deducts 100 credits per image after completion (`refreshProfile`).

- [ ] **Step 7: Commit**

```bash
git add Avora/Views/Create/CreateView.swift
git commit -m "feat: quality picker menu in CreateView"
```

---

### Task 7: Remove the dead single-image submit path (cleanup)

**Files:**
- Delete: `supabase/functions/submit-generation/` (whole directory)
- Modify: `Avora/Services/AvoraAPI.swift:55-69` (remove `submit(styleId:inputPath:)`)

**Interfaces:**
- Removes `AvoraAPI.submit(styleId:inputPath:)` and the `submit-generation` edge function. Both verified to have zero call sites (no Swift, `.ts`, `.sql`, `config.toml`, or cron references). The batch path (1–4 images) subsumes them.
- Leaves DB RPCs `deduct_credit` and `refund_credit_direct` in place (now orphaned; dropping them is out of scope).

- [ ] **Step 1: Delete the edge function**

```bash
git rm -r supabase/functions/submit-generation
```

- [ ] **Step 2: Remove the Swift method**

In `Avora/Services/AvoraAPI.swift`, delete the entire `submit(styleId:inputPath:)` method (the block starting `func submit(styleId: String, inputPath: String) async throws -> UUID {` through its closing `}` — currently lines 55–69, including the `submit-generation` invoke and its two `catch` clauses).

- [ ] **Step 3: Build to verify nothing referenced it**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: remove dead single-image submit path"
```

---

## Self-Review

**Spec coverage:**
- iOS §1 `GenerationQuality` → Task 3. ✅
- iOS §2 `CreditConfig` per-quality cost → Task 4. ✅
- iOS §3 `CreateView` menu + cost display + generate wiring → Task 6. ✅
- iOS §4 `submitBatch` quality param → Task 5 (+ mock path preserved). ✅
- Backend §5 migration (columns + RPC) → Task 1. ✅
- Backend §6 edge-function validation + forward → Task 2. ✅
- Cleanup §7 remove single-image path → Task 7. ✅
- Verification §: pgTAP (Task 1 Step 4), build gates (Tasks 3–7), manual sim (Task 6 Step 6). ✅
- `fetchCreditConfig` select update (implied by §2) → Task 4 Step 2. ✅

**Placeholder scan:** No TBD/TODO; every code step shows complete code; test bodies are full.

**Type consistency:** `GenerationQuality` cases (`default`/`high`/`ultra`) and `backend` values (`low`/`medium`/`high`) are consistent across the enum (Task 3), `CreditConfig.cost(for:)` (Task 4), `qualityMenu`/`generate()` (Task 6), the RPC's `p_quality` allowlist (Task 1), and the edge-function validation array (Task 2). `submitBatch(styleId:inputPaths:quality:)` signature matches its call site in Task 6 Step 4. `credit_config` column names (`cost_low`/`cost_medium`/`cost_high`) match between the migration (Task 1), the `fetchCreditConfig` select (Task 4), and the `CodingKeys` (Task 4).

**Cross-task build note:** Task 5 changes `submitBatch`'s signature, which breaks `CreateView`'s existing call until Task 6 Step 4 updates it. Flagged in Task 5 Step 1 — build the two together, or run the build gate at the end of Task 6.
