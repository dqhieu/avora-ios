# Avora — Backend + iOS Implementation Design

**Date:** 2026-06-28
**Status:** Approved design, ready for implementation planning
**Source spec:** `avora-tech-spec.md` v0.1
**Scope:** Supabase backend + iOS app. **No web app.** The `getavora-app` Next.js repo is untouched by this plan.

---

## 1. Overview

Avora is an AI photo generator for iOS. A user picks a style, picks a photo, and the app produces a restyled image via OpenAI's `gpt-image-2` edits endpoint. Generation is asynchronous and fully server-side: submit returns a `job_id`, the client polls for the result, and the collection reads from the database. Usage is metered with a credit system backed by a weekly subscription and a non-expiring credit pack, with credits granted only from server-verified RevenueCat webhooks.

This document records the architecture and decisions agreed during brainstorming, layering concrete product/UX and economic decisions on top of the source spec.

---

## 2. Decisions log

| Decision | Choice | Notes |
|---|---|---|
| Architecture | Supabase backend per spec (Edge Functions + pgmq + pg_cron) | No standalone server, no web app |
| Backend code home | `supabase/` directory **inside the `avora-ios` repo** | Mixes Swift + Deno/SQL tooling; kept separate via `.gitignore`/CI |
| Web app / `getavora-app` | Untouched | Apple-required Privacy/Support URLs deferred to a separate task |
| Output image size | `size:auto` (model picks) | Cost variable, orientation not guaranteed — accepted for v1 |
| Quality | `quality:medium`, locked server-side per style | Spec §12.4 default |
| Free-tier model split | None — `gpt-image-2` for free and paid | Spec §12.3 deferred |
| Moderation block refund | **Always refund** the credit | No rate-limit counter; never auto-retried |
| Result polling | Every **5 seconds, no ceiling** | Bounded by the reaper, which makes status terminal within ~5 min |
| Reaper timeout | 5 minutes | `pending` rows older than this are refunded + failed |

---

## 3. Credit economics

Points model: each generation costs a fixed number of credits.

| Item | Credits | Generations | Price | $/generation |
|---|---|---|---|---|
| Cost per generation | **25** | 1 | — | — |
| Free starter (extra bucket) | **50** | 2 | free | — |
| Weekly subscription | **1000** | 40 | $9.99/wk | ~$0.25 |
| Extra pack | **500** | 20 | $4.99 | ~$0.25 |

- Revenue per generation is a consistent **~$0.25** across both products.
- Cost guidance (measure real `usage` tokens, keep `quality:medium`) applies **per generation (25 credits)**.
- **Two buckets:** `weekly_credits` (reset to 1000 on renewal, use-it-or-lose-it, no rollover) and `extra_credits` (non-expiring, starts at 50).
- **Consumption priority:** weekly first, then extra (spend the expiring bucket first).
- **Single-bucket charge:** a generation charges the full 25 from one bucket (weekly preferred); never split across buckets, so `charged_bucket` stays single-valued and refunds are clean. All grants are multiples of 25 (50/500/1000), so a bucket never strands below 25.
- **Charged amount stored on the row** (`generations.charged_amount`) so a future price change cannot corrupt in-flight refunds.

---

## 4. Architecture

### Components
- **iOS app** (SwiftUI, iOS 26.5): Sign in with Apple, styles grid, create/generate, collection, paywall.
- **Supabase:** Postgres (data, RLS), Auth (Sign in with Apple), Storage (input + output images), Edge Functions (API + worker + webhook), pgmq (queue), pg_cron (worker pump + reaper).
- **OpenAI:** `gpt-image-2` edits endpoint, server-side key only.
- **RevenueCat:** subscription + consumable verification, credit-granting webhooks.

### Request flow
```
iOS → submit-generation (Edge Fn)
  - verify JWT
  - re-validate input (format/dims/size) server-side
  - deduct_credit RPC (atomic, single bucket, 25 credits) → charged_bucket
  - insert generations row (status=pending, charged_bucket, charged_amount=25)
  - enqueue job to pgmq
  - return 202 { job_id }

Worker (process-queue Edge Fn, pumped by pg_cron)
  - claim job from pgmq (concurrency capped to OpenAI tier IPM)
  - check daily spend cap
  - download input from Storage
  - read prompt_template (service role), compose prompt server-side
  - call images.edit (gpt-image-2, size=auto, quality=medium)
  - decode b64 result → upload to Storage (output_path)
  - update row: completed, store resolved size + input/output tokens
  - on transient failure after retries: failed + refund
  - on moderation_blocked: failed + refund (always) + generic client message

iOS → get-generation (poll every 5s, no ceiling, until terminal)
iOS → list-generations (paginated collection, RLS-scoped)

pg_cron reaper (every 1 min)
  - find pending rows older than 5 min → refund + mark failed
```

### Repo layout
```
avora-ios/
├── Avora/                       ← SwiftUI app
│   ├── App / Auth / Home (styles) / Create / Collection / Paywall / Settings
│   ├── Networking/              ← Supabase client + API calls + RevenueCat
│   └── Models/                  ← Profile, Style, Generation
├── supabase/                    ← backend
│   ├── migrations/              ← schema, RLS, RPCs, pgmq, pg_cron
│   ├── functions/
│   │   ├── submit-generation/
│   │   ├── get-generation/
│   │   ├── list-generations/
│   │   ├── process-queue/       ← worker
│   │   └── revenuecat-webhook/
│   └── config.toml
└── docs/superpowers/specs/      ← this document
```

---

## 5. Data model

### `profiles`
```sql
create table profiles (
  id                       uuid primary key references auth.users(id) on delete cascade,
  created_at               timestamptz not null default now(),
  weekly_credits           int  not null default 0,      -- reset to 1000 on renewal
  extra_credits            int  not null default 50,      -- 50 free starter, never expire
  subscription_period_end  timestamptz,
  subscription_active      boolean not null default false
);
```
- 50 starter credits via column default → granted exactly once at row creation (retried onboarding cannot double-grant).
- `handle_new_user` trigger creates the `profiles` row when an `auth.users` row is inserted.
- **RLS:** owner can `select` own row; no client `update` (credits mutated only by service-role RPCs).

### `styles`
```sql
create table styles (
  id                text primary key,
  name              text not null,
  prompt_template   text not null,              -- SERVER-ONLY
  sample_image_path text,                       -- thumbnail for 2-col grid
  default_size      text not null default 'auto',
  default_quality   text not null default 'medium',
  active            boolean not null default true
);
```
- **Protecting `prompt_template`:** RLS denies client `select` on `styles`; clients read a column-limited view `styles_public (id, name, sample_image_path, active)`. Only the worker (service role) reads `prompt_template`. The view is required because RLS is row-level, not column-level.

### `generations`
```sql
create table generations (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  style_id       text not null references styles(id),
  status         text not null default 'pending'
                   check (status in ('pending','completed','failed')),
  charged_bucket text not null check (charged_bucket in ('weekly','extra')),
  charged_amount int  not null,                 -- credits deducted (25 in v1)
  input_path     text not null,
  output_path    text,
  size           text,                          -- resolved size from API response
  quality        text not null,
  input_tokens   int,                           -- usage logging for cost pilot
  output_tokens  int,                           -- usage logging for cost pilot
  error_code     text,                          -- e.g. moderation_blocked, timeout
  created_at     timestamptz not null default now(),
  completed_at   timestamptz
);

create index on generations (user_id, created_at desc);          -- collection pagination
create index on generations (status) where status = 'pending';   -- reaper sweep
```
- **RLS:** owner can `select` own rows; inserts/updates only via service-role Edge Functions.

### `purchases` (idempotency ledger)
```sql
create table purchases (
  transaction_id text primary key,              -- from RevenueCat, dedupes webhooks
  user_id        uuid not null references auth.users(id),
  kind           text not null check (kind in ('renewal','extra_pack','initial')),
  processed_at   timestamptz not null default now()
);
```
- **RLS:** service-role only (webhook). Clients never read it.

### Supporting infrastructure
- **`pgmq`** creates its own queue table via the extension.
- **`daily_spend (day date primary key, total_tokens bigint, est_cost_usd numeric)`** — enforces the global daily spend ceiling (spec §11); the worker increments it per call and refuses new work past the cap.

---

## 6. Credit RPCs (server-authoritative)

- **`deduct_credit(uid)`** — single transaction, row-locked, cost = 25:
  ```sql
  update profiles set weekly_credits = weekly_credits - 25
    where id = :uid and weekly_credits >= 25 returning 'weekly';
  -- if no row updated:
  update profiles set extra_credits = extra_credits - 25
    where id = :uid and extra_credits >= 25 returning 'extra';
  -- if neither: raise insufficient_credits (caller returns 402, no job enqueued)
  ```
  Returns the charged bucket; caller writes `charged_bucket` + `charged_amount=25` onto the row.
- **`refund_credit(generation_id)`** — idempotent, guarded by the `pending → failed` transition; returns `charged_amount` to `charged_bucket` exactly. Runs at most once per generation.
- **`lazy_weekly_reset(uid)`** — at submit time, if `now > subscription_period_end` and entitlement active, reset weekly to 1000 (webhook backstop, spec §5).

---

## 7. Edge Functions

All verify the Supabase JWT except the webhook (which verifies a RevenueCat signature).

| Function | Job |
|---|---|
| `submit-generation` | Validate `input_path` ownership + re-check format/dims/size; `lazy_weekly_reset`; `deduct_credit`; insert `pending` row; enqueue pgmq; return `202 { job_id }`. On zero credits → `402`. |
| `get-generation` | Return `{ status, output_path?, error_code? }` for the user's job. |
| `list-generations` | Paginated collection, RLS-scoped to the user. |
| `process-queue` (worker) | Claim job, check spend cap, download input, compose prompt from `prompt_template`, call `images.edit` (`gpt-image-2`, `size:auto`, `quality:medium`), store output, mark `completed` with resolved size + tokens. Transient failure after retries → `failed` + refund. `moderation_blocked` → `failed` + refund (always) + generic message. |
| `revenuecat-webhook` | Idempotent on `transaction_id` via `purchases`. `INITIAL_PURCHASE`/`RENEWAL` → `weekly_credits = 1000` + store `subscription_period_end`. `NON_RENEWING_PURCHASE` → `extra_credits += 500`. |

### Scheduled (pg_cron)
- **Worker pump:** invoke `process-queue` frequently; since pg_cron's floor is 1 min, the worker loops internally (~50s) pulling jobs continuously. Concurrency capped to stay under OpenAI tier IPM (spec §11).
- **Reaper:** every 1 min, refund + fail `pending` rows older than 5 min.

---

## 8. Image model configuration (`gpt-image-2`)

- Edits endpoint, server-side key. `model="gpt-image-2"`, `size="auto"`, `quality="medium"`.
- Returns base64 (`b64_json`); worker decodes and persists to Storage.
- Resolved size read from the response and stored on the row for cost tracking, along with `input_tokens` / `output_tokens` from the `usage` block.
- Token-billed: image input $8/M, image output $30/M, text input $5/M. Edits always process the reference image at high fidelity → image input tokens on every call. Price credits against measured real usage, not published per-image estimates.
- Prompts live in `prompt_template`, server-side; client sends only a `style_id`. Tune each style directly against `images.edit` (the ChatGPT app is not a fair benchmark).
- No masking in v1 — all styles are whole-image transforms.
- Handle `error.code = "moderation_blocked"`: show generic safety message, log details for support/analytics, always refund (no retry).

---

## 9. Image input handling

- Client normalizes before upload: re-encode HEIC → PNG/JPEG, clamp max dimension (smaller input = fewer image-input tokens = lower cost).
- Upload to Storage first via signed upload URL; submit sends the storage path + style id, never base64 in the body.
- Server re-validates format/dimensions/file size on submit (don't trust client normalization alone).

---

## 10. Storage

- Supabase Storage with RLS so a user reads only their own input/output objects.
- Outputs ~1–3 MB each. Retention policy is an accepted open growth item for v1.
- Account deletion cascades: remove the user's Storage objects + `generations` rows + `profiles` row.

---

## 11. Monetization (RevenueCat)

- **Weekly plan:** $9.99/week auto-renewable subscription → 1000 weekly credits.
- **Extra pack:** $4.99 consumable → 500 extra credits.
- Credits granted **only** from RevenueCat webhooks (client purchase callback is spoofable).
- All webhook handling idempotent on `transaction_id` via `purchases`.
- Honor entitlement until Apple's expiry on cancellation; weekly drops to 0 at period end, extra survives.

---

## 12. iOS app design

### Navigation (tab-based, after login gate)

**Tab 1 — Home (Styles)**
- 2-column grid of all active styles (from `styles_public`).
- Credit balance in the header; settings/account reachable from here.
- Tap a style → push **Create** (carries the chosen `style_id`).

**Create screen**
- User selects a photo (`PhotosPicker`).
- Taps **Generate** → photo view switches to a loading state in place.
- Pipeline: normalize → signed-URL upload → `submit-generation` → poll `get-generation` every 5s until terminal.
- On `completed`, the loading view switches in place to the result image. Primary actions:
  - **Save** → export to the device Photos library (`NSPhotoLibraryAddUsageDescription`); the result is in the server-side Collection regardless.
  - **Generate again** → reset to photo-pick state, keep the same style.
- On `failed`, show a generic message and note the credit was refunded.

**Tab 2 — Collection**
- Paginated grid of the user's past generations (RLS-scoped), tap for full image.

**Paywall** — modal, shown on server `402` (out of credits) or from settings; RevenueCat-driven (weekly sub + extra pack).
**Login** — Sign in with Apple → Supabase Auth native flow (existing button wired up).
**Settings** — credit balance, restore purchases, account deletion (cascade).

### Networking & models
- **Supabase Swift SDK** (SPM): Auth session, Storage, Postgrest reads for `styles_public`/`generations`/`profiles` (RLS), Edge Function invocation.
- **RevenueCat SDK** (SPM): purchases + entitlement.
- Credits never granted client-side; the client only displays the server balance.
- Models: `Profile`, `Style`, `Generation`.

---

## 13. Operational concerns

- **OpenAI rate limits (IPM):** Tier 1 = 5/min, Tier 3 = 50/min ($100 + 7 days), Tier 5 = 250/min ($1000 + 30 days). Cap worker concurrency to the active tier; the queue converts bursts into a controlled drain. ~100 concurrent users realistically needs Tier 3+.
- **Daily spend cap:** global ceiling independent of per-user credits (`daily_spend` table).
- **Free-credit abuse:** a new Apple ID grants another 50 free credits (2 generations). Accepted v1 gap.
- **Idempotency:** generation submits and purchase webhooks use idempotency keys / ledger.
- **Privacy/GDPR:** account deletion cascades to all user images and rows.

---

## 14. Build sequence (phases)

1. **Supabase project + schema** — tables, RLS, Storage buckets + policies, `styles_public` view, seed styles with `prompt_template`s. *Verify:* RLS blocks cross-user reads.
2. **Credit RPCs** — `deduct_credit` (25, single-bucket), `refund_credit` (idempotent), `lazy_weekly_reset`. *Verify:* N parallel submits on a 25-credit account → exactly one succeeds.
3. **Queue + worker + reaper** — pgmq, `process-queue` calling `gpt-image-2`, pg_cron pump + reaper, `daily_spend` cap. *Verify:* reaper refunds an orphaned `pending` row.
4. **API Edge Functions** — `submit-generation`, `get-generation`, `list-generations`. *Verify:* end-to-end generation completes into Storage + DB.
5. **RevenueCat webhook** — `revenuecat-webhook`, idempotent on `transaction_id`. *Verify:* replay a `RENEWAL` (→1000) and an `extra_pack` (→+500) with no double grant.
6. **iOS foundation** — SPM deps (Supabase, RevenueCat), Sign in with Apple wired, tab-bar shell, models.
7. **iOS Home + Create** — styles grid, Create screen (photo pick → normalize → upload → submit → poll → inline result), Save to Photos, Generate again, Paywall on `402`.
8. **iOS Collection + Settings** — paginated collection tab, settings, account deletion cascade.
9. **Monetization wiring + pre-launch checklist** — RevenueCat products + paywall, then run §15.

---

## 15. Pre-launch checklist

- [ ] One-week cost pilot: log `usage` tokens from real edit calls at `size:auto`/`medium`, confirm ~$0.25/generation margin.
- [ ] Verify atomic deduction under concurrent load (fire N parallel submits on a 25-credit account).
- [ ] Verify reaper refunds orphaned `pending` jobs.
- [ ] Verify webhook idempotency (replay `RENEWAL` and `extra_pack`).
- [ ] Verify RLS blocks cross-user reads of generations and Storage objects.
- [ ] Confirm OpenAI tier IPM headroom for expected peak.
- [ ] Confirm Apple Privacy Policy + Support URLs are live (deferred web task).

---

## 16. Out of scope for v1

Masked/region edits, 4K output, multi-turn editing, Android, web client, admin dashboard.
