# Custom Style Prompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users restyle their own photos with a style they describe in free text, via a "Custom" tile that reuses the existing generate flow and image-edit pipeline.

**Architecture:** A generation becomes either *preset* (`style_id` set) or *custom* (`custom_prompt` set) — enforced by making `generations.style_id` nullable (FK kept) and adding a `custom_prompt` column with an XOR check. The submit edge function branches on which was sent; the worker wraps custom text in a restyle scaffold and skips the style lookup. iOS adds a Custom tile, a text field in `CreateView`, and re-use from the Collection detail.

**Tech Stack:** Supabase (Postgres + pgTAP tests + Deno edge functions), SwiftUI (iOS), OpenAI `images/edits` (`gpt-image-2`).

## Global Constraints

- **Data model:** `generations` is EITHER preset (`style_id` non-null, `custom_prompt` null) OR custom (`style_id` null, `custom_prompt` non-null) — never both, never neither. Enforced by CHECK `generations_style_xor_prompt`.
- **Prompt length cap:** custom prompt is `1..=1000` characters after trim. Enforced server-side (edge function) and mirrored client-side.
- **Prompt wrap (worker, verbatim):** `Restyle this photo: {user text}. Preserve the subject's likeness and pose. Do not add text or watermarks.`
- **Custom size:** worker uses size `"auto"` for custom jobs (matches `styles.default_size` default).
- **Moderation:** no custom banned-word list. Rely on OpenAI `moderation_blocked` → existing fail + auto-refund path.
- **Client sentinel:** `Style.custom` (id `"custom"`) is a client-only navigation token; it is NEVER sent to the backend. Custom submits send `style_id: nil`.
- **RLS:** unchanged. `custom_prompt` is owner-readable via the existing `generations_select_own` policy; preset `prompt_template` stays hidden.
- **Cost:** unaffected by custom — quality drives cost exactly as today.
- **Testing:** backend tasks use pgTAP red/green (`supabase test db`) and `deno check`; iOS tasks have no XCTest target in this repo, so they verify via XcodeBuild compile + manual UI checks (matching the quality-picker precedent). Do not add an iOS test target.

**Spec:** `docs/superpowers/specs/2026-07-05-custom-style-prompt-design.md`

---

## File Structure

**Backend**
- `supabase/migrations/000031_custom_prompt.sql` (create) — nullable `style_id`, add `custom_prompt`, XOR check, replace `submit_generations_batch` with a `p_custom_prompt` parameter.
- `supabase/tests/032_custom_prompt_test.sql` (create) — pgTAP coverage for the RPC + XOR check.
- `supabase/functions/submit-generation-batch/index.ts` (modify) — preset-vs-custom branch + custom validation.
- `supabase/functions/process-queue/index.ts` (modify) — wrap custom prompt, skip style fetch.

**iOS**
- `Avora/Models/Style.swift` (modify) — `Style.custom` sentinel.
- `Avora/Models/Generation.swift` (modify) — `customPrompt` field.
- `Avora/Models/CreateRoute.swift` (modify) — `customPrompt` seed field.
- `Avora/Services/AvoraAPI.swift` (modify) — `submitBatch` optional prompt + optional `styleId`; `listGenerations` select.
- `Avora/Views/Home/StylesGridView.swift` (modify) — pinned Custom tile.
- `Avora/Views/Create/CreateView.swift` (modify) — text field, gating, custom submit.
- `Avora/Views/Collection/CollectionView.swift` (modify) — `CreationDetailView` re-use path.

Tasks are ordered backend → iOS so the data model exists before anything sends to it. Each task compiles/passes on its own.

---

## Task 1: Schema migration + RPC + pgTAP test

**Files:**
- Create: `supabase/migrations/000031_custom_prompt.sql`
- Test: `supabase/tests/032_custom_prompt_test.sql`

**Interfaces:**
- Produces: `submit_generations_batch(p_uid uuid, p_style_id text, p_input_paths text[], p_quality text, p_custom_prompt text default null) returns uuid[]`. Column `generations.custom_prompt text` (nullable); `generations.style_id` now nullable. CHECK `generations_style_xor_prompt`.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/000031_custom_prompt.sql`:

```sql
-- Custom generations describe their style in free text instead of pointing at a
-- preset. style_id becomes nullable (FK kept: NULLs skip the FK check, so preset
-- jobs are still validated against styles(id)); custom_prompt carries the words.

alter table public.generations
  alter column style_id drop not null;

alter table public.generations
  add column custom_prompt text;

-- A job is EITHER preset (style_id, no custom_prompt) OR custom (custom_prompt,
-- no style_id) — never both, never neither.
alter table public.generations
  add constraint generations_style_xor_prompt check (
    (style_id is not null and custom_prompt is null) or
    (style_id is null and custom_prompt is not null)
  );

-- Adding a defaulted parameter creates a NEW overload rather than replacing, so
-- drop the old 4-arg function first to avoid an ambiguous call.
drop function if exists public.submit_generations_batch(uuid, text, text[], text);

create or replace function public.submit_generations_batch(
  p_uid uuid,
  p_style_id text,
  p_input_paths text[],
  p_quality text,
  p_custom_prompt text default null
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
      (user_id, style_id, custom_prompt, status, charged_bucket,
       charged_amount, input_path, quality)
      values (p_uid, p_style_id, p_custom_prompt, 'pending', v_bucket,
              v_cost, v_path, p_quality)
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

revoke all on function
  public.submit_generations_batch(uuid, text, text[], text, text)
  from public, anon, authenticated;
```

> Note: the per-quality cost lookup and `bad_quality` check are copied verbatim from the current function body (migration `000027_per_quality_cost.sql`) so this migration is self-contained. Only the signature, the `custom_prompt` insert column, and the drop are new.

- [ ] **Step 2: Write the failing pgTAP test**

Create `supabase/tests/032_custom_prompt_test.sql`:

```sql
begin;
select plan(8);

insert into auth.users (id, email) values ('66666666-6666-6666-6666-666666666666','c@test.dev');
insert into public.styles (id, name, prompt_template) values ('cs1','CS1','x');
-- credit_config seeds cost_low=20

update public.profiles set weekly_credits = 100, extra_credits = 0
  where id = '66666666-6666-6666-6666-666666666666';

-- CUSTOM: null style_id + custom_prompt, charged like any low batch.
select is(
  array_length(
    submit_generations_batch('66666666-6666-6666-6666-666666666666', null,
      array['66666666-6666-6666-6666-666666666666/a.png',
            '66666666-6666-6666-6666-666666666666/b.png'],
      'low', 'make it a watercolor sunset'), 1),
  2, 'custom: returns 2 job ids');
select is((select weekly_credits from public.profiles where id='66666666-6666-6666-6666-666666666666'),
          60, 'custom: weekly 100 -> 60 (2 x 20)');
select is((select count(*)::int from public.generations
             where user_id='66666666-6666-6666-6666-666666666666'
               and style_id is null
               and custom_prompt='make it a watercolor sunset'),
          2, 'custom: rows have null style_id and stored prompt');

-- PRESET regression: 4-arg call still resolves (p_custom_prompt defaults null).
delete from public.generations where user_id='66666666-6666-6666-6666-666666666666';
update public.profiles set weekly_credits = 100, extra_credits = 0
  where id = '66666666-6666-6666-6666-666666666666';
select is(
  array_length(
    submit_generations_batch('66666666-6666-6666-6666-666666666666', 'cs1',
      array['66666666-6666-6666-6666-666666666666/a.png'], 'low'), 1),
  1, 'preset: 4-arg call still works');
select is((select count(*)::int from public.generations
             where user_id='66666666-6666-6666-6666-666666666666'
               and style_id='cs1' and custom_prompt is null),
          1, 'preset: row has style_id and null custom_prompt');

-- XOR check rejects malformed rows (23514 = check_violation).
select throws_ok(
  $$ insert into public.generations
       (user_id, style_id, custom_prompt, status, charged_bucket, charged_amount, input_path, quality)
     values ('66666666-6666-6666-6666-666666666666','cs1','both','pending','weekly',20,'p','low') $$,
  '23514', null, 'XOR: rejects both style_id and custom_prompt set');
select throws_ok(
  $$ insert into public.generations
       (user_id, style_id, custom_prompt, status, charged_bucket, charged_amount, input_path, quality)
     values ('66666666-6666-6666-6666-666666666666',null,null,'pending','weekly',20,'p','low') $$,
  '23514', null, 'XOR: rejects neither set');

-- Old 4-arg overload must be gone (exactly one function of this name).
select is((select count(*)::int from pg_proc where proname = 'submit_generations_batch'),
          1, 'exactly one submit_generations_batch overload exists');

select * from finish();
rollback;
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `supabase test db`
Expected: FAIL — before applying the migration, `custom_prompt` doesn't exist and the 5-arg call is undefined (errors / failed assertions).

> If `supabase test db` requires a running local stack, start it first with `supabase start`.

- [ ] **Step 4: Apply the migration**

Run: `supabase db reset`
Expected: all migrations apply cleanly through `000031`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `supabase test db`
Expected: PASS — `032_custom_prompt_test.sql` reports `ok` for all 8 assertions, and the existing `031_batch_submit_test.sql` still passes (regression: 4-arg calls unaffected).

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/000031_custom_prompt.sql supabase/tests/032_custom_prompt_test.sql
git commit -m "feat: nullable style_id and custom_prompt column for custom generations"
```

---

## Task 2: Edge function — preset vs custom branch

**Files:**
- Modify: `supabase/functions/submit-generation-batch/index.ts`

**Interfaces:**
- Consumes: `submit_generations_batch(..., p_custom_prompt)` from Task 1.
- Produces: request contract — body is `{ input_paths, quality, style_id? , custom_prompt? }`. Custom mode = `custom_prompt` non-empty string (then `style_id` must be absent); preset mode = `style_id` string of an active style (then `custom_prompt` must be absent). Custom prompt validated `1..=1000` chars after trim.

- [ ] **Step 1: Rewrite the validation + branch**

In `supabase/functions/submit-generation-batch/index.ts`, replace the body from the `const { style_id, ... }` destructure through the style existence check with the following. The `input_paths` array/size/ownership checks and the per-file Storage validation are unchanged and stay where they are (the custom branch only changes style handling and adds prompt validation):

```ts
  const { style_id, custom_prompt, input_paths, quality } = body;

  // input_paths + quality are validated the same way in both modes.
  if (!Array.isArray(input_paths)) {
    return json({ error: "bad_request" }, 400);
  }
  if (typeof quality !== "string" || !["low", "medium", "high"].includes(quality)) {
    return json({ error: "bad_request" }, 400);
  }
  if (input_paths.length < 1 || input_paths.length > 4 ||
      !input_paths.every((p) => typeof p === "string")) {
    return json({ error: "bad_batch_size" }, 400);
  }
  if (!input_paths.every((p) => (p as string).startsWith(`${uid}/`))) {
    return json({ error: "forbidden_path" }, 403);
  }

  // Mode: custom when a non-empty custom_prompt is present, else preset.
  const isCustom = typeof custom_prompt === "string" &&
    custom_prompt.trim().length > 0;

  let styleIdArg: string | null = null;
  let customPromptArg: string | null = null;

  if (isCustom) {
    if (typeof style_id === "string") {
      return json({ error: "bad_request" }, 400); // custom must not carry a style
    }
    const trimmed = (custom_prompt as string).trim();
    if (trimmed.length < 1 || trimmed.length > 1000) {
      return json({ error: "bad_request" }, 400);
    }
    customPromptArg = trimmed;
  } else {
    if (typeof style_id !== "string") {
      return json({ error: "bad_request" }, 400);
    }
    const db0 = serviceClient();
    const { data: style } = await db0.from("styles")
      .select("id, active").eq("id", style_id).single();
    if (!style || !style.active) return json({ error: "unknown_style" }, 400);
    styleIdArg = style_id;
  }

  const db = serviceClient();
```

> If `serviceClient()` was already called once below, keep a single `const db = serviceClient();` and use it for both the preset style check and the rest — do not create two clients. The snippet above names the preset-check client `db0` only to keep the diff local; collapse to one `db` if you prefer.

- [ ] **Step 2: Pass the branch args to the RPC**

Update the RPC call (the `db.rpc("submit_generations_batch", { ... })` block) to pass both new args:

```ts
  const { data: jobIds, error: rpcErr } = await db.rpc("submit_generations_batch", {
    p_uid: uid,
    p_style_id: styleIdArg,
    p_input_paths: input_paths,
    p_quality: quality,
    p_custom_prompt: customPromptArg,
  });
```

The `lazy_weekly_reset` call, the per-file Storage validation loop, and the error handling (`P0001` insufficient_credits → 402, else 500) are unchanged.

- [ ] **Step 3: Type-check the function**

Run: `deno check supabase/functions/submit-generation-batch/index.ts`
Expected: no type errors.

> If `deno` resolves remote imports slowly the first time, that's expected; a clean exit code is the pass signal.

- [ ] **Step 4: Manual verification (local functions serve)**

With `supabase start` running, serve functions (`supabase functions serve submit-generation-batch`) and confirm by reasoning through the branch:
- custom body `{ input_paths:[".../a.png"], quality:"low", custom_prompt:"x" }` → reaches the RPC with `p_style_id:null, p_custom_prompt:"x"`.
- empty `custom_prompt:"   "` → falls to preset mode; with no `style_id` → `400 bad_request`.
- `custom_prompt` of 501 chars → `400 bad_request`.
- preset body with valid active `style_id` and no prompt → unchanged behavior.

(End-to-end auth/storage make a full curl heavy; the pgTAP RPC test in Task 1 already proves the DB side. Validating the branch logic here is sufficient.)

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/submit-generation-batch/index.ts
git commit -m "feat: accept custom_prompt in submit-generation-batch"
```

---

## Task 3: Worker — wrap custom prompt

**Files:**
- Modify: `supabase/functions/process-queue/index.ts`

**Interfaces:**
- Consumes: `generations.custom_prompt` from Task 1.
- Produces: for a custom job the worker calls `runEdit` with the wrapped prompt and size `"auto"`, without fetching a style.

- [ ] **Step 1: Select custom_prompt and branch prompt/size**

In `supabase/functions/process-queue/index.ts`, add `custom_prompt` to the generation select and replace the style fetch + `runEdit` prompt/size wiring:

```ts
      const { data: gen } = await db.from("generations")
        .select("id,user_id,style_id,custom_prompt,input_path,quality,status").eq("id", jobId).single();
      if (!gen || gen.status !== "pending") { await archive(db, msgId); continue; }

      // Custom jobs carry their own words (no preset row); preset jobs load the
      // curated template. size "auto" matches styles.default_size for custom.
      let prompt: string;
      let size: string;
      if (gen.custom_prompt) {
        prompt = `Restyle this photo: ${gen.custom_prompt}. Preserve the subject's likeness and pose. Do not add text or watermarks.`;
        size = "auto";
      } else {
        const { data: style } = await db.from("styles")
          .select("prompt_template,default_size").eq("id", gen.style_id).single();
        prompt = style!.prompt_template;
        size = style!.default_size;
      }

      const { data: blob } = await db.storage.from("inputs").download(gen.input_path);
      const bytes = new Uint8Array(await blob!.arrayBuffer());
      const contentType = blob!.type || "image/png";
      const filename = contentType === "image/jpeg" ? "input.jpg" : "input.png";

      const result = await runEdit({
        imageBytes: bytes, filename, contentType,
        prompt, size, quality: gen.quality,
      });
```

Everything after `runEdit` (JPEG encode, upload, completion update, spend bump, archive) and the `catch` (retry/refund, `moderation_blocked`) is unchanged.

- [ ] **Step 2: Type-check the function**

Run: `deno check supabase/functions/process-queue/index.ts`
Expected: no type errors.

- [ ] **Step 3: Manual verification (reasoning)**

Confirm: a row with `custom_prompt` set and `style_id` null takes the wrap branch (no `styles` query, size `"auto"`); a preset row (null `custom_prompt`) is byte-for-byte the old path. A `moderation_blocked` result still hits the existing non-retryable catch → fail + `refund_credit`.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/process-queue/index.ts
git commit -m "feat: wrap custom prompt in restyle scaffold in worker"
```

---

## Task 4: iOS models — sentinel, prompt field, route seed

**Files:**
- Modify: `Avora/Models/Style.swift`
- Modify: `Avora/Models/Generation.swift`
- Modify: `Avora/Models/CreateRoute.swift`

**Interfaces:**
- Produces: `Style.custom` static; `Generation.customPrompt: String?` (JSON key `custom_prompt`); `CreateRoute.customPrompt: String?` (defaults nil).

- [ ] **Step 1: Add the `Style.custom` sentinel**

In `Avora/Models/Style.swift`, extend the existing `extension Style`:

```swift
extension Style {
    /// Client-only navigation token for the custom-prompt flow. Never sent to the
    /// backend — custom generations submit `style_id: nil`. Provides the non-optional
    /// `Style` that `CreateRoute` and the navigation title need.
    static let custom = Style(
        id: "custom", name: "Custom", sampleImagePath: nil,
        active: false, sortOrder: -1, badgeText: nil
    )
}
```

- [ ] **Step 2: Add `customPrompt` to `Generation`**

In `Avora/Models/Generation.swift`, add the field and coding key:

```swift
struct Generation: Codable, Identifiable, Hashable {
    let id: UUID
    let styleId: String?
    let customPrompt: String?
    let status: GenStatus
    let outputPath: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case styleId = "style_id"
        case customPrompt = "custom_prompt"
        case outputPath = "output_path"
        case createdAt = "created_at"
    }
}
```

- [ ] **Step 3: Add `customPrompt` to `CreateRoute`**

In `Avora/Models/CreateRoute.swift`:

```swift
struct CreateRoute: Hashable {
    let style: Style
    var placeholder: RemoteImageRef?
    var customPrompt: String? = nil
}
```

The default `= nil` keeps existing `CreateRoute(style:placeholder:)` call sites compiling.

- [ ] **Step 4: Build to verify compile**

Use XcodeBuild MCP `build_sim` (or `session_show_defaults` then `build_sim`).
Expected: build succeeds. Adding an optional Codable field is source-compatible; existing snapshot decodes tolerate a missing key (optional → nil).

- [ ] **Step 5: Commit**

```bash
git add Avora/Models/Style.swift Avora/Models/Generation.swift Avora/Models/CreateRoute.swift
git commit -m "feat: add custom style sentinel and custom_prompt model plumbing"
```

---

## Task 5: iOS API — submit optional prompt, fetch prompt back

**Files:**
- Modify: `Avora/Services/AvoraAPI.swift`

**Interfaces:**
- Consumes: `Generation.customPrompt` (Task 4).
- Produces: `submitBatch(styleId: String?, inputPaths: [String], quality: String, customPrompt: String? = nil) async throws -> [UUID]`. `listGenerations` returns rows including `custom_prompt`.

- [ ] **Step 1: Widen `submitBatch`**

In `Avora/Services/AvoraAPI.swift`, replace the `submitBatch` signature and body encoding:

```swift
    func submitBatch(styleId: String?, inputPaths: [String], quality: String,
                     customPrompt: String? = nil) async throws -> [UUID] {
        #if DEBUG
        if AvoraConfig.isMockGenerationEnabled { return inputPaths.map { _ in UUID() } }
        #endif
        struct Body: Encodable {
            let style_id: String?
            let input_paths: [String]
            let quality: String
            let custom_prompt: String?
        }
        struct Resp: Decodable { let job_ids: [UUID] }
        do {
            let resp: Resp = try await db.functions.invoke(
                "submit-generation-batch",
                options: .init(body: Body(
                    style_id: styleId, input_paths: inputPaths,
                    quality: quality, custom_prompt: customPrompt))
            )
            return resp.job_ids
        } catch let FunctionsError.httpError(code: code, data: _) where code == 402 {
            throw AvoraError.insufficientCredits
        } catch let FunctionsError.httpError(code: code, data: _) {
            throw AvoraError.server(code)
        }
    }
```

> The default JSON encoder emits `null` for nil optionals; the edge function reads a `null` `style_id`/`custom_prompt` as "absent" via its `typeof`/non-empty checks (Task 2), so preset and custom requests both decode correctly.

- [ ] **Step 2: Add `custom_prompt` to `listGenerations` select**

In the same file, update the `listGenerations` select string:

```swift
        let baseQuery = db.from("generations")
            .select("id,style_id,custom_prompt,status,output_path,created_at")
```

- [ ] **Step 3: Build to verify compile**

Use XcodeBuild MCP `build_sim`.
Expected: build succeeds. The existing preset call in `CreateView.generate()` — `submitBatch(styleId: style.id, inputPaths: paths, quality: quality.backend)` — still compiles: `style.id` (`String`) binds to `String?`, and `customPrompt` defaults to nil.

- [ ] **Step 4: Commit**

```bash
git add Avora/Services/AvoraAPI.swift
git commit -m "feat: submitBatch accepts optional custom prompt; fetch custom_prompt back"
```

---

## Task 6: iOS — Custom tile in the Styles grid

**Files:**
- Modify: `Avora/Views/Home/StylesGridView.swift`

**Interfaces:**
- Consumes: `Style.custom` (Task 4).
- Produces: a pinned first grid cell linking to `CreateRoute(style: .custom, placeholder: nil)`.

- [ ] **Step 1: Add the Custom card and pin it first**

In `Avora/Views/Home/StylesGridView.swift`, inside the `LazyVGrid`, add the Custom link before the `ForEach(app.styles)`:

```swift
            LazyVGrid(columns: cols, spacing: 12) {
                NavigationLink(value: CreateRoute(style: .custom, placeholder: nil)) {
                    CustomStyleCard()
                }
                .buttonStyle(.plain)

                ForEach(app.styles) { style in
                    NavigationLink(value: CreateRoute(style: style, placeholder: nil)) {
                        StyleCard(style: style)
                    }
                    .buttonStyle(.plain)
                }
            }.padding()
```

- [ ] **Step 2: Add the `CustomStyleCard` view**

Add this private view to the same file (mirrors `StyleCard`'s tile styling, with an icon + label instead of a sample image):

```swift
private struct CustomStyleCard: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(alignment: .leading) {
            let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            let content = Color.clear
                .contentShape(.rect)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "pencil.and.scribble")
                            .font(.avoraLargeTitle)
                        Text("Write your own")
                            .font(.avoraFootnote)
                    }
                    .foregroundStyle(Color.avoraTextSecondary)
                }
                .clipShape(shape)
            Group {
                if #available(iOS 26.0, *) {
                    content.glassEffect(in: shape)
                } else {
                    content
                        .background(colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : .white, in: shape)
                        .overlay(shape.stroke(Color.secondary.opacity(0.5), lineWidth: 0.5))
                }
            }
            Text("Custom")
                .font(.avoraHeadline)
                .padding(.top, Spacing.xs)
        }
    }
}
```

> If `Color.avoraTextSecondary` is not defined in the design system, use `Color.avoraTextTertiary` (used by `StyleCard`'s placeholder). Verify against `Avora/DesignSystem/Colors.swift` before building.

- [ ] **Step 3: Build to verify compile**

Use XcodeBuild MCP `build_sim`.
Expected: build succeeds.

- [ ] **Step 4: Manual verification**

Run the app (XcodeBuild MCP `build_run_sim`). On the Styles tab, the Custom card is the first cell and reads "Custom" / "Write your own". Tapping it pushes `CreateView` titled "Custom" (the destination already exists via `navigationDestination(for: CreateRoute.self)`).

- [ ] **Step 5: Commit**

```bash
git add Avora/Views/Home/StylesGridView.swift
git commit -m "feat: add Custom tile to styles grid"
```

---

## Task 7: iOS — CreateView custom mode

**Files:**
- Modify: `Avora/Views/Create/CreateView.swift`

**Interfaces:**
- Consumes: `Style.custom` (Task 4), `submitBatch(styleId:inputPaths:quality:customPrompt:)` (Task 5), `CreateRoute.customPrompt` (Task 4).
- Produces: when the route's style is `.custom`, a prompt text field; Generate gated on a valid prompt; custom submit path.

- [ ] **Step 1: Add custom state and derived flags**

In `Avora/Views/Create/CreateView.swift`, add state seeded from the route and derived validity. Update `init(route:)` to capture the seed prompt:

```swift
    @State private var promptText: String

    init(route: CreateRoute) {
        self.style = route.style
        self.placeholder = route.placeholder
        _promptText = State(initialValue: route.customPrompt ?? "")
    }

    private var isCustom: Bool { style.id == Style.custom.id }

    private var trimmedPrompt: String {
        promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var promptValid: Bool {
        !trimmedPrompt.isEmpty && trimmedPrompt.count <= 1000
    }
```

- [ ] **Step 2: Show the prompt field (custom only)**

Add a prompt field to the `controls` stack, shown only when `isCustom` and results aren't shown yet. Insert it at the top of the `body`'s `VStack` controls area — place it above the existing `controls` call in `body`:

```swift
    var body: some View {
        VStack(spacing: Spacing.lg) {
            photoArea
            if isCustom && !hasResults {
                promptField
                    .padding(.horizontal, Spacing.lg)
            }
            controls
                .padding(.horizontal, Spacing.lg)
        }
        // ...unchanged modifiers...
    }

    private var promptField: some View {
        VStack(alignment: .trailing, spacing: Spacing.xs) {
            TextField("Describe your style…", text: $promptText, axis: .vertical)
                .lineLimit(2...4)
                .font(.avoraBody)
                .padding(Spacing.md)
                .avoraGlass(in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .disabled(isWorking)
            Text("\(trimmedPrompt.count)/1000")
                .font(.avoraCaption2)
                .foregroundStyle(trimmedPrompt.count > 1000 ? Color.avoraError : Color.avoraTextTertiary)
        }
    }
```

> Verify `.avoraBody`, `.avoraCaption2`, `Radius.md`, and `avoraGlass(in:)` exist (they are used elsewhere in this file / design system). If `.avoraBody` is absent, use `.avoraFootnote`.

- [ ] **Step 3: Gate Generate on a valid prompt**

In `controls`, the generate `AvoraPrimaryButton` currently has `.disabled(sourceImages.isEmpty || isWorking)`. Extend it so custom also requires a valid prompt:

```swift
                .disabled(sourceImages.isEmpty || isWorking || (isCustom && !promptValid))
```

- [ ] **Step 4: Branch the submit call**

In `generate()`, replace the `submitBatch` call so custom sends the prompt and no style:

```swift
            let jobIds: [UUID]
            if isCustom {
                jobIds = try await AvoraAPI.shared.submitBatch(
                    styleId: nil, inputPaths: paths, quality: quality.backend,
                    customPrompt: trimmedPrompt)
            } else {
                jobIds = try await AvoraAPI.shared.submitBatch(
                    styleId: style.id, inputPaths: paths, quality: quality.backend)
            }
            poller.start(jobIds: jobIds, poll: { try await AvoraAPI.shared.poll(jobId: $0) })
```

- [ ] **Step 5: Build to verify compile**

Use XcodeBuild MCP `build_sim`.
Expected: build succeeds.

- [ ] **Step 6: Manual verification**

Run the app (`build_run_sim`), open the Custom tile:
- The prompt field appears; Generate is disabled until a photo is picked AND the prompt is non-empty.
- The counter reads `n/1000` and turns red past 1000.
- With mock generation on (`AvoraConfig.isMockGenerationEnabled`), pick 2 photos, type a prompt, Generate → both slots reveal the mock result.
- A preset style (e.g. Oil Painting) shows NO prompt field and generates as before.

- [ ] **Step 7: Commit**

```bash
git add Avora/Views/Create/CreateView.swift
git commit -m "feat: custom prompt field and submit path in CreateView"
```

---

## Task 8: iOS — re-use a custom prompt from the Collection

**Files:**
- Modify: `Avora/Views/Collection/CollectionView.swift`

**Interfaces:**
- Consumes: `Generation.customPrompt` (Task 4), `CreateRoute.customPrompt` (Task 4), `Style.custom` (Task 4).
- Produces: `CreationDetailView` shows "Create with this prompt" for custom creations, pre-filling the text.

- [ ] **Step 1: Add the re-use branch in `CreationDetailView`**

In `Avora/Views/Collection/CollectionView.swift`, in `CreationDetailView.body`, the action area currently shows the preset button only when `style` resolves. Add a custom branch. Replace the `if let style { ... }` block with:

```swift
            if let style {
                NavigationLink(value: CreateRoute(style: style, placeholder: placeholder)) {
                    Label("Create with this style", systemImage: "wand.and.stars")
                }
                .buttonStyle(AvoraPrimaryButtonStyle())
                .padding(.horizontal, Spacing.lg)
            } else if let prompt = generation.customPrompt {
                NavigationLink(value: CreateRoute(style: .custom, placeholder: placeholder, customPrompt: prompt)) {
                    Label("Create with this prompt", systemImage: "wand.and.stars")
                }
                .buttonStyle(AvoraPrimaryButtonStyle())
                .padding(.horizontal, Spacing.lg)
            }
```

`resolveStyle()` is unchanged: for a custom creation `styleId` is nil, so `guard let styleId … else { return }` returns early, `style` stays nil, and the `else if` branch renders. The navigation title stays `style?.name ?? "Creation"`.

- [ ] **Step 2: Build to verify compile**

Use XcodeBuild MCP `build_sim`.
Expected: build succeeds.

- [ ] **Step 3: Manual verification**

Run the app (`build_run_sim`). After generating a custom creation (Task 7), open it from the Collection tab:
- The detail shows "Create with this prompt".
- Tapping it pushes `CreateView` titled "Custom" with the original text already in the field and the finished image as the placeholder.
- A preset creation still shows "Create with this style".

- [ ] **Step 4: Commit**

```bash
git add Avora/Views/Collection/CollectionView.swift
git commit -m "feat: re-use a custom prompt from the collection detail"
```

---

## Self-Review

**Spec coverage:**
- Nullable `style_id` + `custom_prompt` + XOR check → Task 1. ✅
- RPC gains `p_custom_prompt` → Task 1. ✅
- RLS unchanged (owner reads `custom_prompt`) → no task needed; verified by `listGenerations` returning it (Task 5) under existing `generations_select_own`. ✅
- Edge function preset/custom branch + 1..1000 validation → Task 2. ✅
- Worker wrap + size "auto" + skip style fetch → Task 3. ✅
- `Style.custom`, `Generation.customPrompt`, `CreateRoute.customPrompt` → Task 4. ✅
- `submitBatch` optional prompt + `listGenerations` select → Task 5. ✅
- Custom tile pinned first → Task 6. ✅
- CreateView text field + gating + custom submit → Task 7. ✅
- Collection re-use ("Create with this prompt", pre-fill) → Task 8. ✅
- Moderation via OpenAI (no new list) → unchanged worker catch, noted in Task 3. ✅

**Type consistency:** `submitBatch(styleId: String?, inputPaths:, quality:, customPrompt: String? = nil)` defined in Task 5 and called with `styleId: nil, customPrompt:` (custom) / `styleId: style.id` (preset) in Task 7 — consistent. `custom_prompt` JSON key used in the migration (Task 1), edge function (Task 2), worker select (Task 3), `Generation` coding key (Task 4), and `listGenerations` select (Task 5) — consistent. `Style.custom` / `style.id == Style.custom.id` used in Tasks 4/6/7/8 — consistent. `CreateRoute(style:placeholder:customPrompt:)` matches the Task 4 definition.

**Placeholder scan:** No TBD/TODO; every code step shows complete code. Two "verify this symbol exists" notes (design-system color/font/`Radius`) include a concrete fallback each, not a blank.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-05-custom-style-prompt.md`.
