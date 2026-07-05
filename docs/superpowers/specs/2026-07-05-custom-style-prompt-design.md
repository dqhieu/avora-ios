# Custom Style Prompt — Design

**Date:** 2026-07-05
**Status:** Approved (pending spec review)

## Summary

Let the user restyle their own photos with a style they describe in their own
words, instead of only picking a curated preset. A new **"Custom" tile** pinned
first in the Styles grid opens the normal `CreateView` flow (pick 1–4 photos,
choose quality, Generate) but with a free-text field. The typed text is wrapped
server-side in a restyle scaffold and run through the **existing `images/edits`
pipeline** — the photo is preserved; the text drives the restyle. Credits and
quality work exactly as they do for presets.

This is a full-stack change: iOS UI + app→backend plumbing + a schema change so a
generation can carry a user prompt instead of a preset style. Users can also
**re-use** a custom prompt from their Collection, matching the "recreate" parity
presets already have.

## Decisions (resolved during brainstorming)

- **Core behavior:** Restyle the user's photo with their own words. Still requires
  an uploaded photo (the pipeline is `images/edits`); not text-to-image.
- **Entry point:** A dedicated **"Custom" tile** in the Styles grid. The preset
  flow is untouched. No custom field on preset screens.
- **Prompt shaping:** Wrap the user's text in a restyle scaffold **and** apply
  basic input checks (non-empty after trim, length cap). Content moderation relies
  on OpenAI's existing `moderation_blocked` path (job fails + auto-refund).
- **Data model — Option B:** Make `generations.style_id` **nullable** (keep the
  FK) and add a nullable `custom_prompt` column. A custom job is
  `style_id = NULL, custom_prompt = '<text>'`. Chosen over a sentinel `custom`
  style row because it is semantically honest (NULL = "no preset style"), keeps
  referential integrity for preset jobs, introduces no magic-string coupling
  across layers, and fits the client code that **already** treats `styleId` as
  optional.
- **Length cap:** 500 characters (server-enforced; client mirrors it).
- **Re-use in v1:** Yes. `custom_prompt` is exposed to the client (owner-only via
  existing RLS — it is the user's own text, unlike preset `prompt_template`) so a
  custom creation offers "Create with this prompt".

## Non-goals / out of scope

- Text-to-image with no input photo.
- A custom-instructions field layered on preset styles.
- Example-prompt suggestions, prompt history, or a saved "my styles" library.
- Server-side keyword/banned-word filtering beyond length/non-empty — OpenAI
  moderation is the content boundary for v1.
- Showing the prompt text on the Collection detail screen (only the re-use button
  uses it; the text itself is not displayed).

---

## Data model — Option B

The heart of the change. `generations.style_id` is currently
`text not null references public.styles(id)`. A custom job has no preset style, so
the column becomes nullable (the FK stays — NULLs are exempt from the FK check),
and a new column carries the user's words.

### 1. Migration — `supabase/migrations/000031_custom_prompt.sql`

```sql
-- Custom jobs have no preset style. Keep the FK: NULLs skip the FK check, so
-- preset jobs are still validated against styles(id).
alter table public.generations
  alter column style_id drop not null;

-- The user's own words for custom jobs; NULL for preset jobs.
alter table public.generations
  add column custom_prompt text;

-- A job is EITHER a preset (style_id, no custom_prompt) OR custom (custom_prompt,
-- no style_id) — never both, never neither.
alter table public.generations
  add constraint generations_style_xor_prompt check (
    (style_id is not null and custom_prompt is null) or
    (style_id is null and custom_prompt is not null)
  );
```

### 2. RPC — `submit_generations_batch` (same migration)

The function gains a `p_custom_prompt` parameter and stores both columns on each
inserted row (one is always NULL). For a custom batch, the edge function passes
`p_style_id => NULL, p_custom_prompt => '<text>'`; the one prompt applies to all
N photos, mirroring how one preset style applies to a batch.

```sql
create or replace function public.submit_generations_batch(
  p_uid uuid,
  p_style_id text,
  p_input_paths text[],
  p_quality text,
  p_custom_prompt text default null   -- NEW; NULL for preset batches
)
returns uuid[]
language plpgsql
security definer set search_path = public
as $$
-- ...unchanged declarations, batch-size check, cost lookup, credit lock...
begin
  -- ...
  foreach v_path in array p_input_paths loop
    -- ...unchanged bucket split...
    insert into public.generations
      (user_id, style_id, custom_prompt, status, charged_bucket,
       charged_amount, input_path, quality)
      values (p_uid, p_style_id, p_custom_prompt, 'pending', v_bucket,
              v_cost, v_path, p_quality)
      returning id into v_id;
    perform public.pgmq_send('generations', jsonb_build_object('job_id', v_id));
    v_ids := array_append(v_ids, v_id);
  end loop;
  -- ...unchanged profile update, return...
end;
$$;

revoke all on function
  public.submit_generations_batch(uuid, text, text[], text, text)
  from public, anon, authenticated;
```

Everything else in the RPC is unchanged: the per-quality cost lookup, per-row
bucket split (weekly first, then extra), each row storing its own
`charged_amount`, the insufficient-credits check, and enqueue. Because each row
records its own `charged_amount`, per-job refunds stay correct.

Note: adding a defaulted parameter changes the function signature, so the old
`(uuid, text, text[], text)` overload is replaced. The `revoke` must reference the
new 5-arg signature.

### 3. RLS — no change

The existing `generations_select_own` policy is row-level and exposes every
column to the owner, so `custom_prompt` is readable by the user who created it and
invisible to everyone else. No new policy or column grant is needed. (This is
deliberately unlike preset `prompt_template`, which stays hidden behind
`styles_public` as product IP.)

---

## Backend — request path

### 4. Edge function — `submit-generation-batch/index.ts`

The function today requires `style_id` (string) and validates it exists + is
active. It now accepts **either** a preset `style_id` **or** a `custom_prompt`,
and branches:

- Read `custom_prompt` from the body. **Custom mode** = `custom_prompt` is a
  non-empty string; otherwise **preset mode**.
- **Common validation (both modes), unchanged:** `input_paths` is an array of
  1–4 strings, every path starts with `${uid}/`, `quality ∈ {low, medium, high}`,
  and each input file passes the Storage format/size check.
- **Preset mode:** `style_id` must be a string; the style must exist and be
  `active` (existing check). `custom_prompt` must be absent.
- **Custom mode:** `style_id` must be absent/null. Trim `custom_prompt`; require
  `1 ≤ length ≤ 500` after trim, else `400 { error: "bad_request" }`. **Skip the
  style lookup entirely.** This is the server-side re-validation of the client's
  input checks — the client is never trusted.
- Call the RPC with the mode's arguments:
  - preset: `p_style_id => style_id, p_custom_prompt => null`
  - custom: `p_style_id => null, p_custom_prompt => trimmed`

The `403 forbidden_path` / `400 bad_batch_size` / input-file checks are shared and
run before the mode branch.

### 5. Worker — `process-queue/index.ts`

The worker currently selects `prompt_template, default_size` from `styles` keyed
by `gen.style_id`, then calls `runEdit` with that prompt. It now branches on
whether the job is custom:

- Add `custom_prompt` to the generation select
  (`id,user_id,style_id,custom_prompt,input_path,quality,status`).
- **Custom job** (`gen.custom_prompt` present / `gen.style_id` null): build the
  final prompt by **wrapping** the user's text, and use size `"auto"` (the same
  default `styles.default_size` carries). Do **not** fetch a style row.
- **Preset job:** unchanged — fetch the style, use `prompt_template` and
  `default_size`.

**Wrap format:**

```
Restyle this photo: {user text}. Preserve the subject's likeness and pose. Do not add text or watermarks.
```

Everything downstream (JPEG re-encode, output upload, completion update, spend
bump, retry/refund on `OpenAIError`) is identical for both modes. A
`moderation_blocked` prompt therefore fails and auto-refunds through the existing
non-retryable path — no new failure handling.

---

## iOS changes

### 6. `Style` sentinel — `Avora/Models/Style.swift`

Add a client-only sentinel so the existing `CreateRoute` (which carries a
non-optional `Style`) and the navigation title work without a special route type:

```swift
extension Style {
    /// Client-only navigation token for the custom-prompt flow. Never sent to the
    /// backend — custom generations submit `style_id: nil`. Its id existing here
    /// does NOT reintroduce a cross-layer magic string; it never crosses the wire.
    static let custom = Style(
        id: "custom", name: "Custom", sampleImagePath: nil,
        active: false, sortOrder: -1, badgeText: nil
    )
}
```

`CreateView` uses `style.id == Style.custom.id` purely as the client-side "am I in
custom mode?" discriminator.

### 7. `StylesGridView` — pin the Custom tile first

Prepend a distinct, hardcoded card (not from `app.styles`) that links to
`CreateRoute(style: .custom, placeholder: nil)`. It reads e.g. "Write your own"
with a pencil/wand icon and matches the existing `StyleCard` glass styling. The
preset `ForEach(app.styles)` grid follows unchanged.

### 8. `CreateRoute` — seed text for re-use

```swift
struct CreateRoute: Hashable {
    let style: Style
    var placeholder: RemoteImageRef?
    var customPrompt: String? = nil   // NEW: seeds the field when re-using; nil = fresh
}
```

### 9. `CreateView` — text field + custom submit

- `private var isCustom: Bool { style.id == Style.custom.id }`.
- `@State private var promptText: String` seeded from `route.customPrompt ?? ""`.
- **When `isCustom`:** show a multiline "Describe your style…" `TextField`
  (`.avoraGlass` styled) with a `promptText.count / 500` counter. There is no
  sample placeholder for custom (the style has none) — the empty surface plus the
  field guides the user.
- **Prompt validity:** `let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)`,
  valid = `!trimmed.isEmpty && trimmed.count <= 500`.
- **Generate gating:** disabled unless photos are picked **and** (for custom) the
  prompt is valid: `sourceImages.isEmpty || isWorking || (isCustom && !promptValid)`.
- **`generate()`:** for custom, call
  `submitBatch(styleId: nil, inputPaths: paths, quality: quality.backend, customPrompt: trimmed)`;
  for preset, the existing `submitBatch(styleId: style.id, ...)` call is unchanged.

The quality menu, credits label, batch photo UI, and done-state controls are all
unchanged and shared between modes.

### 10. `AvoraAPI.submitBatch` — optional custom prompt

```swift
func submitBatch(
    styleId: String?, inputPaths: [String], quality: String,
    customPrompt: String? = nil
) async throws -> [UUID]
```

- `styleId` becomes optional. The encodable `Body` carries optional `style_id` and
  `custom_prompt`. Either omitting the nil key or sending it as JSON `null` is
  fine — the edge function's mode branch keys off `typeof style_id === "string"`
  and `custom_prompt` being a non-empty string, so a `null` reads as "absent".
- Existing preset call sites pass `styleId: style.id` (still compiles — `String`
  binds to `String?`).
- Mock path (`AvoraConfig.isMockGenerationEnabled`) unchanged — returns random
  UUIDs, ignoring both fields.

### 11. `Generation` model — carry the prompt back

```swift
struct Generation: Codable, Identifiable, Hashable {
    let id: UUID
    let styleId: String?        // already optional — no change
    let customPrompt: String?   // NEW
    let status: GenStatus
    let outputPath: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case styleId = "style_id"
        case customPrompt = "custom_prompt"   // NEW
        case outputPath = "output_path"
        case createdAt = "created_at"
    }
}
```

`AvoraAPI.listGenerations` must add `custom_prompt` to its `.select(...)`.

### 12. `CreationDetailView` (in `CollectionView.swift`) — re-use

`resolveStyle()` already returns early when `styleId` is nil, so a custom creation
currently shows the image + Save with title "Creation". Add the re-use path:

- When `generation.styleId == nil` and `generation.customPrompt` is present, show
  **"Create with this prompt"** linking to
  `CreateRoute(style: .custom, placeholder: <output>, customPrompt: <text>)`.
- The preset branch (`if let style { "Create with this style" }`) is unchanged.

The user lands on the custom Create screen with their words pre-filled, picks new
photos, and generates again.

---

## Verification

**Backend**
- Apply the migration locally (`supabase db reset`). Confirm `generations.style_id`
  is nullable, `custom_prompt` exists, and the XOR check rejects a row with both or
  neither set.
- RPC: `submit_generations_batch` with `p_style_id => null, p_custom_prompt => 'x'`
  inserts custom rows; with a `style_id` and null prompt inserts preset rows;
  per-quality cost and per-row refund still correct.
- Edge function: a custom request (`{ custom_prompt: "watercolor sunset", input_paths, quality }`,
  no `style_id`) succeeds and produces rows with `style_id = null` and the trimmed
  prompt. A blank or >500-char prompt returns `400`. A preset request is unaffected.
- Worker (mock off): a custom job wraps the text, calls `runEdit` with size `auto`,
  and completes; a `moderation_blocked` prompt fails and refunds.

**iOS**
- Build via XcodeBuild MCP (no compile errors).
- Manually: the Custom tile appears first; tapping it opens Create with a text
  field. Generate stays disabled until a photo is picked **and** the prompt is
  non-empty; the counter caps at 500.
- End-to-end (mock on): generate a custom batch of 2 photos; both slots reveal.
- Collection: the custom creation opens to "Create with this prompt", pre-filled
  with the original text; a preset creation still shows "Create with this style".

## Risks

- **Prompt tampering / cost bypass** — mitigated: quality (hence cost) is validated
  and priced server-side exactly as today; `custom_prompt` does not affect cost.
- **Malformed job rows** — mitigated by the `generations_style_xor_prompt` CHECK:
  the DB rejects any row that isn't cleanly preset-or-custom.
- **Off-product / disallowed prompts** — the wrap scaffold nudges toward faithful
  restyles; OpenAI moderation blocks disallowed content with an auto-refund. No
  custom banned-word list in v1 (explicit non-goal).
- **`custom_prompt` exposure** — intentional and owner-scoped by existing RLS; it
  is the user's own input, not preset IP. Preset `prompt_template` stays hidden.
- **Client sentinel id `"custom"`** — client-only navigation token; it never
  reaches the backend (custom jobs send `style_id: nil`), so Option B's
  no-magic-string property holds on the wire.

## Files touched

**Create**
- `supabase/migrations/000031_custom_prompt.sql`

**Modify**
- `Avora/Models/Style.swift` (add `.custom` sentinel)
- `Avora/Models/Generation.swift` (add `customPrompt`)
- `Avora/Models/CreateRoute.swift` (add `customPrompt`)
- `Avora/Views/Home/StylesGridView.swift` (pin Custom tile)
- `Avora/Views/Create/CreateView.swift` (text field, custom submit, gating)
- `Avora/Views/Collection/CollectionView.swift` (`CreationDetailView` re-use path)
- `Avora/Services/AvoraAPI.swift` (`submitBatch` signature, `listGenerations` select)
- `supabase/functions/submit-generation-batch/index.ts` (custom vs preset branch)
- `supabase/functions/process-queue/index.ts` (wrap custom prompt; skip style fetch)
