# Batch Photo Generation — Design Spec

**Date:** 2026-07-02
**Status:** Approved, ready for implementation plan

## Goal

Let a user select one style, then pick up to **4 photos**, and generate all of
them for that same style in a single action. Results appear as a grid, each cell
progressing independently.

## Decisions (locked)

- **Flow shape:** Upgrade the existing `CreateView` to multi. Single code path;
  N=1 flows through the same batch path with no special case.
- **Cap:** 4 photos per batch.
- **Billing:** Strict all-or-nothing. Either all N generations are charged and
  enqueued, or none are (new backend batch function — Option B).

## Current behavior (baseline)

Single photo only. Tap style → `CreateView` → `PhotosPicker(matching: .images)`
picks one → `ImageNormalizer.normalize` (max 1536px PNG) →
`AvoraAPI.uploadInput` (to `inputs` bucket) → `AvoraAPI.submit(styleId:inputPath:)`
calls `submit-generation` edge function → returns one `job_id` →
`GenerationPoller` polls `get-generation` every 5s → show/save the single result.

Server billing (`submit-generation/index.ts`): validates style + input file,
then `deduct_credit(p_uid)` atomically deducts a fixed **25** credits (weekly
bucket first, then extra), inserts a `generations` row storing
`charged_bucket` + `charged_amount = 25` + `quality`, enqueues one pgmq message.
Per-job refund (`refund_credit(generation_id)`) reads that row's own
`charged_bucket`/`charged_amount`, so refunds are precise per generation.

## Backend design

### New edge function: `submit-generation-batch`

`POST { style_id: string, input_paths: string[] }` where `1 <= input_paths.length <= 4`.

1. Auth via `requireUser`; else 401.
2. Reject `input_paths.length == 0 || > 4` → 400.
3. Validate style exists and is `active` (same query as `submit-generation`);
   else 400 `unknown_style`.
4. Validate **each** `input_path`:
   - Must start with `<uid>/` → else 403 `forbidden_path`.
   - Must exist via `storage.from("inputs").list(folder, { search: filename })`,
     be `image/png` or `image/jpeg`, and be ≤ 10 MB → else 400.
5. `lazy_weekly_reset(p_uid)` backstop (as today).
6. Call the new RPC (below). Map its errors:
   - `P0001` / `insufficient_credits` → 402 `insufficient_credits`.
   - any other error → 500.
7. On success → 202 `{ job_ids: string[] }` (order matches `input_paths`).

No TypeScript compensation logic: atomicity lives entirely in the RPC's single
transaction.

### New RPC: `submit_generations_batch(p_uid, p_style_id, p_input_paths text[], p_quality)`

`security definer`, service-role-only grants (revoke from public/anon/authenticated),
matching `deduct_credit`.

Single transaction:
1. `PERFORM 1 FROM profiles WHERE id = p_uid FOR UPDATE;` (serialize concurrent submits).
2. `v_count := array_length(p_input_paths, 1)`; `v_needed := v_count * 25`.
3. If `weekly_credits + extra_credits < v_needed` →
   `RAISE EXCEPTION 'insufficient_credits' USING errcode = 'P0001';`
   (nothing deducted — transaction aborts clean).
4. Allocate a bucket **per row**: fill from `weekly` first (25 each) until the
   weekly balance can't cover another 25, then from `extra`. Deduct
   `weekly_credits` / `extra_credits` accordingly in the profile.
5. For each input path, `INSERT INTO generations (user_id, style_id, status,
   charged_bucket, charged_amount, input_path, quality)` with that row's
   allocated bucket, `charged_amount = 25`, `status = 'pending'`,
   `quality = p_quality`. Collect the new `id`.
6. For each new id, enqueue via `pgmq_send('generations', { job_id })`
   (transactional — rolls back with the inserts on any failure).
7. `RETURN` the array of new `job_id`s in input order.

**Why per-row bucket matters:** a batch may straddle both buckets (e.g. weekly
covers 2 of 4, extra covers the other 2). Storing each row's own
`charged_bucket`/`charged_amount` keeps the existing per-job
`refund_credit(generation_id)` correct with **zero changes** to the worker.

### Untouched backend

- `submit-generation` (single) stays deployed and unchanged.
- `get-generation`, `process-queue`, `refund_credit`, `deduct_credit` unchanged.
- New migration file adds `submit_generations_batch` + grants only.

## iOS design

### `AvoraAPI`

Add:
```
func submitBatch(styleId: String, inputPaths: [String]) async throws -> [UUID]
```
Invokes `submit-generation-batch`, decodes `{ job_ids: [UUID] }`, maps HTTP 402 →
`AvoraError.insufficientCredits` (same pattern as `submit`). `uploadInput` and
`poll` (`get-generation`) are reused unchanged.

### New `BatchGenerationPoller` (`@MainActor @Observable`)

- Per-job state: an ordered list of `Item { id: UUID (jobId); phase }` where
  `phase ∈ { working, done(outputPath), failed(code) }`.
- `start(jobIds:, poll:)` spawns one poll loop per job (≤4), each reusing
  `AvoraAPI.poll(jobId:)` and updating only its own item; same 5s interval and
  transient-error retry logic as `GenerationPoller`.
- Exposes `items` (for the grid) and `allTerminal: Bool`.
- `stop()` cancels every loop.
- The single-job `GenerationPoller` is orphaned by this change → **remove it**.

### `CreateView` (upgraded to multi)

State changes:
- `pickerItems: [PhotosPickerItem]` (was `pickerItem: PhotosPickerItem?`)
- `sourceImages: [UIImage]` (was `sourceImage: UIImage?`)
- `poller = BatchGenerationPoller()` (was `GenerationPoller`)
- drop `resultPath: String?` (results now come from `poller.items`)

Picker: `PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images)`.

Preview area becomes a **grid** (up to 2×2):
- Before generate: thumbnails of the picked images.
- During/after generate: one cell per job — spinner while `working`, result image
  on `done`, and a "Couldn't generate — credit refunded" state on `failed`.

Controls:
- Cost label: `\(count * app.config.generationCost) credits`.
- `generate()`:
  1. Client pre-check: `app.profile.totalCredits >= count * app.config.generationCost`
     → else show paywall (server remains authoritative via 402).
  2. Normalize + `uploadInput` all images **in parallel** (task group, N≤4).
  3. If **any upload fails, abort before submitting** — show a generic error,
     nothing charged.
  4. `submitBatch(styleId:inputPaths:)` → `poller.start(jobIds:)`.
  5. Catch `insufficientCredits` → paywall; other errors → generic message.
- Results: per-cell **Save** (to Photos), plus **Save all** for completed cells.
- **Generate again** resets picker + poller.
- `refreshProfile()` when the batch reaches terminal (`allTerminal`).

`CollectionView`'s "Create with this style" link now lands on the same multi flow
(N can be 1) — no change needed beyond navigating to the upgraded `CreateView`.

## Edge cases

- **N=1:** identical batch path, grid of one.
- **Partial outcome:** each cell reflects its own job; failed jobs are
  auto-refunded server-side per-job; successful jobs remain usable.
- **Upload failure mid-batch:** abort before submit so billing stays
  all-or-nothing; nothing is charged.
- **Insufficient credits:** caught at the RPC before any deduction → 402 → paywall;
  no partial generations.

## Out of scope

- No change to per-generation cost (fixed 25 server-side).
- No change to the queue worker or refund logic.
- No mixing of multiple styles in one batch.

## Files touched

**Create**
- `supabase/functions/submit-generation-batch/index.ts`
- `supabase/migrations/0000XX_submit_generations_batch.sql`
- `Avora/Services/BatchGenerationPoller.swift`

**Modify**
- `Avora/Services/AvoraAPI.swift` (add `submitBatch`)
- `Avora/Views/Create/CreateView.swift` (multi-select + results grid)

**Remove**
- `Avora/Services/GenerationPoller.swift` (orphaned by the batch poller)
