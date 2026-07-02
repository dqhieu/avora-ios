# Batch Photo Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user pick one style then up to 4 photos and generate all of them for that style in a single all-or-nothing action, showing results as an independently-progressing grid.

**Architecture:** A new `submit-generation-batch` edge function validates N inputs and calls one new `submit_generations_batch` plpgsql RPC that does the credit check, per-row bucket allocation, N inserts, and N enqueues in a single transaction (atomic all-or-nothing). iOS upgrades `CreateView` to multi-select, fans out uploads, calls the batch endpoint, and polls each returned job with a new `BatchGenerationPoller`.

**Tech Stack:** Supabase (Postgres/plpgsql, pgtap, Deno edge functions, pgmq), Swift/SwiftUI, PhotosUI.

## Global Constraints

- Batch size is **1–4** photos. Enforce in both the edge function and the RPC.
- Per-generation cost is **read live** from `credit_config.generation_cost` (currently 20) — never hardcode a cost. The RPC reads it; the client uses `app.config.generationCost`.
- Each `generations` row must store its **own** `charged_bucket` and `charged_amount` (= the live cost) so per-job `refund_credit(generation_id)` stays correct.
- Insufficient credits is signaled by SQLSTATE **`P0001`** with message containing `insufficient_credits`, mapped by the edge function to **HTTP 402**.
- Credit RPCs are `security definer` and granted to **service role only** (revoke from public/anon/authenticated), matching `deduct_credit`.
- New `.swift` files under `Avora/` are auto-included via the Xcode `PBXFileSystemSynchronizedRootGroup` — no `project.pbxproj` edits needed to add/remove files.
- No iOS unit-test target exists; iOS tasks are verified by a successful build (and manual sim run for the UI task). Backend tasks use pgtap via `supabase test db`.
- Spec: `docs/superpowers/specs/2026-07-02-batch-photo-generation-design.md`.

---

### Task 1: `submit_generations_batch` RPC + pgtap test

**Files:**
- Create: `supabase/migrations/000026_submit_generations_batch.sql`
- Test: `supabase/tests/031_batch_submit_test.sql`

**Interfaces:**
- Consumes: `public.credit_config.generation_cost`, `public.profiles(weekly_credits, extra_credits)`, `public.generations`, `public.pgmq_send(text, jsonb)`.
- Produces: `public.submit_generations_batch(p_uid uuid, p_style_id text, p_input_paths text[], p_quality text) returns uuid[]` — deducts atomically and returns the new job ids in input order.

- [ ] **Step 1: Write the failing pgtap test**

Create `supabase/tests/031_batch_submit_test.sql`:

```sql
begin;
select plan(9);

insert into auth.users (id, email) values ('55555555-5555-5555-5555-555555555555','e@test.dev');
-- profile auto-created; set a balance that forces a batch to straddle both buckets
update public.profiles set weekly_credits = 30, extra_credits = 20
  where id = '55555555-5555-5555-5555-555555555555';
insert into public.styles (id, name, prompt_template) values ('bs1','BS1','x');
-- credit_config.generation_cost defaults to 20

-- batch of 2: needed 40; weekly(30) covers one row, extra(20) covers the other
select is(
  array_length(
    submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
      array['55555555-5555-5555-5555-555555555555/a.png',
            '55555555-5555-5555-5555-555555555555/b.png'], 'medium'), 1),
  2, 'returns 2 job ids');
select is((select weekly_credits from public.profiles where id='55555555-5555-5555-5555-555555555555'),
          10, 'weekly 30 -> 10 (one row charged weekly)');
select is((select extra_credits from public.profiles where id='55555555-5555-5555-5555-555555555555'),
          0, 'extra 20 -> 0 (one row charged extra)');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555'),
          2, 'two generation rows inserted');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555' and charged_bucket='weekly'),
          1, 'one row charged to weekly bucket');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555' and charged_bucket='extra'),
          1, 'one row charged to extra bucket');
select is((select count(*)::int from public.generations
             where user_id='55555555-5555-5555-5555-555555555555' and charged_amount=20),
          2, 'each row charged the config cost (20)');

-- insufficient: total < needed raises P0001 and deducts nothing
update public.profiles set weekly_credits = 10, extra_credits = 0
  where id = '55555555-5555-5555-5555-555555555555';
select throws_ok(
  $$ select submit_generations_batch('55555555-5555-5555-5555-555555555555','bs1',
       array['55555555-5555-5555-5555-555555555555/c.png'], 'medium') $$,
  'P0001', 'insufficient_credits', 'raises when total < needed');
select is((select weekly_credits from public.profiles where id='55555555-5555-5555-5555-555555555555'),
          10, 'weekly untouched after failed batch (all-or-nothing)');

select * from finish();
rollback;
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `supabase test db`
Expected: FAIL — `031_batch_submit_test.sql` errors with `function submit_generations_batch(...) does not exist`.

- [ ] **Step 3: Write the migration/RPC**

Create `supabase/migrations/000026_submit_generations_batch.sql`:

```sql
-- Atomic batch submit: check credits for the whole batch, deduct per-row
-- (weekly first, then extra), insert N pending generations each recording its own
-- charged bucket/amount so per-job refund stays correct, enqueue each, return ids.
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

  select generation_cost into v_cost from public.credit_config;
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

- [ ] **Step 4: Apply the migration locally and run the test**

Run: `supabase db reset && supabase test db`
Expected: PASS — `031_batch_submit_test.sql` reports `ok 1..9` with no failures.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/000026_submit_generations_batch.sql supabase/tests/031_batch_submit_test.sql
git commit -m "feat: submit_generations_batch RPC for atomic batch credit deduction"
```

---

### Task 2: `submit-generation-batch` edge function

**Files:**
- Create: `supabase/functions/submit-generation-batch/index.ts`

**Interfaces:**
- Consumes: `submit_generations_batch` RPC (Task 1), `lazy_weekly_reset` RPC, `_shared/cors.ts` (`handleOptions`, `json`), `_shared/supabase.ts` (`requireUser`, `serviceClient`).
- Produces: `POST /submit-generation-batch` accepting `{ style_id: string, input_paths: string[] }`, returning `202 { job_ids: string[] }`, `402 { error: "insufficient_credits" }`, or a 4xx validation error.

- [ ] **Step 1: Write the edge function**

Create `supabase/functions/submit-generation-batch/index.ts`:

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
  const { style_id, input_paths } = body;
  if (typeof style_id !== "string" || !Array.isArray(input_paths)) {
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
    .select("id, default_quality, active").eq("id", style_id).single();
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
    p_quality: style.default_quality,
  });
  if (rpcErr) {
    if (rpcErr.code === "P0001" && rpcErr.message.includes("insufficient_credits"))
      return json({ error: "insufficient_credits" }, 402);
    return json({ error: "submit_failed" }, 500);
  }

  return json({ job_ids: jobIds }, 202);
});
```

- [ ] **Step 2: Verify the function loads without error**

Run: `supabase functions serve submit-generation-batch --no-verify-jwt`
Expected: the local edge runtime boots and logs it is serving `submit-generation-batch` with no syntax/module errors. Stop with Ctrl-C.

- [ ] **Step 3: Manual smoke (optional but recommended)**

With `supabase start` running and a valid user JWT in `$JWT`, and a PNG already uploaded to `inputs/<uid>/a.png`:

```bash
curl -s -X POST "http://127.0.0.1:54321/functions/v1/submit-generation-batch" \
  -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d '{"style_id":"<active_style_id>","input_paths":["<uid>/a.png"]}'
```
Expected: HTTP 202 with `{"job_ids":["..."]}`. A bad batch (0 or >4 paths) returns 400; a drained account returns 402.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/submit-generation-batch/index.ts
git commit -m "feat: submit-generation-batch edge function"
```

---

### Task 3: `AvoraAPI.submitBatch`

**Files:**
- Modify: `Avora/Services/AvoraAPI.swift` (add method after `submit`, ~line 66)

**Interfaces:**
- Consumes: `submit-generation-batch` edge function (Task 2), existing `db.functions.invoke`, `AvoraError`.
- Produces: `func submitBatch(styleId: String, inputPaths: [String]) async throws -> [UUID]` — throws `AvoraError.insufficientCredits` on 402, `AvoraError.server(code)` on other HTTP errors.

- [ ] **Step 1: Add the method**

In `Avora/Services/AvoraAPI.swift`, immediately after the `submit(styleId:inputPath:)` method (ends at line 66), add:

```swift
    func submitBatch(styleId: String, inputPaths: [String]) async throws -> [UUID] {
        struct Body: Encodable { let style_id: String; let input_paths: [String] }
        struct Resp: Decodable { let job_ids: [UUID] }
        do {
            let resp: Resp = try await db.functions.invoke(
                "submit-generation-batch",
                options: .init(body: Body(style_id: styleId, input_paths: inputPaths))
            )
            return resp.job_ids
        } catch let FunctionsError.httpError(code: code, data: _) where code == 402 {
            throw AvoraError.insufficientCredits
        } catch let FunctionsError.httpError(code: code, data: _) {
            throw AvoraError.server(code)
        }
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `** BUILD SUCCEEDED **`. (Equivalent: XcodeBuildMCP `build_sim`.)

- [ ] **Step 3: Commit**

```bash
git add Avora/Services/AvoraAPI.swift
git commit -m "feat: AvoraAPI.submitBatch for batch generation"
```

---

### Task 4: `BatchGenerationPoller`

**Files:**
- Create: `Avora/Services/BatchGenerationPoller.swift`

**Interfaces:**
- Consumes: `AvoraAPI.poll(jobId:)` (passed in as a closure), `GenerationResult` (`status`, `outputPath`, `errorCode`).
- Produces: `@MainActor @Observable final class BatchGenerationPoller` with:
  - `enum Phase: Equatable { case working, done(outputPath: String), failed(code: String?) }`
  - `struct Item: Identifiable, Equatable { let id: UUID; var phase: Phase }`
  - `var items: [Item]` (read), `var allTerminal: Bool`
  - `func start(jobIds: [UUID], poll: @escaping (UUID) async throws -> GenerationResult, intervalNanos: UInt64 = 5_000_000_000)`
  - `func stop()`

- [ ] **Step 1: Write the class**

Create `Avora/Services/BatchGenerationPoller.swift`:

```swift
import Foundation

@MainActor
@Observable
final class BatchGenerationPoller {
    enum Phase: Equatable {
        case working, done(outputPath: String), failed(code: String?)
    }
    struct Item: Identifiable, Equatable {
        let id: UUID          // job id
        var phase: Phase
    }

    private(set) var items: [Item] = []
    private var tasks: [Task<Void, Never>] = []

    /// True once every job has reached a terminal phase (done or failed).
    var allTerminal: Bool {
        !items.isEmpty && items.allSatisfy {
            if case .working = $0.phase { return false }
            return true
        }
    }

    func start(jobIds: [UUID],
               poll: @escaping (UUID) async throws -> GenerationResult,
               intervalNanos: UInt64 = 5_000_000_000) {
        stop()
        items = jobIds.map { Item(id: $0, phase: .working) }
        tasks = jobIds.map { jobId in
            Task { [weak self] in
                while !Task.isCancelled {
                    do {
                        let r = try await poll(jobId)
                        switch r.status {
                        case .pending:
                            break
                        case .completed:
                            if let path = r.outputPath, !path.isEmpty {
                                self?.update(jobId, .done(outputPath: path))
                            } else {
                                self?.update(jobId, .failed(code: "no_output"))
                            }
                            return
                        case .failed:
                            self?.update(jobId, .failed(code: r.errorCode))
                            return
                        }
                    } catch {
                        // transient network error: keep polling
                    }
                    try? await Task.sleep(nanoseconds: intervalNanos)
                }
            }
        }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    private func update(_ jobId: UUID, _ phase: Phase) {
        if let idx = items.firstIndex(where: { $0.id == jobId }) {
            items[idx].phase = phase
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Avora/Services/BatchGenerationPoller.swift
git commit -m "feat: BatchGenerationPoller to track multiple generation jobs"
```

---

### Task 5: Upgrade `CreateView` to multi-select + remove single poller

**Files:**
- Modify (full rewrite): `Avora/Views/Create/CreateView.swift`
- Delete: `Avora/Services/GenerationPoller.swift`

**Interfaces:**
- Consumes: `BatchGenerationPoller` (Task 4), `AvoraAPI.submitBatch` (Task 3), `AvoraAPI.uploadInput`, `AvoraAPI.poll`, `ImageNormalizer.normalize`, `ImageStore.shared.image(for:)`, `AppState` (`profile`, `config.generationCost`, `refreshProfile()`), `RemoteImage`, `AvoraPrimaryButton`, `Spacing`/`Radius`/`Color.avora*`.
- Produces: same `CreateView(route: CreateRoute)` entry point used by `StylesGridView` and `CollectionView` — no navigation changes required.

- [ ] **Step 1: Replace `CreateView.swift` with the multi-select implementation**

Overwrite `Avora/Views/Create/CreateView.swift` with:

```swift
import SwiftUI
import PhotosUI

struct CreateView: View {
    let style: Style
    private let placeholder: RemoteImageRef?
    @Environment(AppState.self) private var app
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var sourceImages: [UIImage] = []
    @State private var poller = BatchGenerationPoller()
    @State private var showPaywall = false
    @State private var errorText: String?
    @State private var isSubmitting = false

    private let columns = [GridItem(.flexible(), spacing: Spacing.md),
                           GridItem(.flexible(), spacing: Spacing.md)]

    init(route: CreateRoute) {
        self.style = route.style
        self.placeholder = route.placeholder
    }

    /// Image shown before the user picks photos: an explicit one from the route
    /// (e.g. a prior creation), otherwise the style's own sample.
    private var effectivePlaceholder: RemoteImageRef? {
        placeholder ?? style.sampleImagePath.map { RemoteImageRef(path: $0, source: .sample) }
    }

    private var hasResults: Bool { !poller.items.isEmpty }

    private var isWorking: Bool {
        isSubmitting || (!poller.items.isEmpty && !poller.allTerminal)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if hasResults {
                    resultsGrid
                } else {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images) {
                        pickArea
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                }
                controls
            }
            .padding(Spacing.lg)
        }
        .navigationTitle(style.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) { PaywallView().environment(app) }
        .onChange(of: pickerItems) { _, items in Task { await loadPicked(items) } }
        .onChange(of: poller.allTerminal) { _, done in
            if done { Task { await app.refreshProfile() } }
        }
        .onDisappear { poller.stop() }
    }

    // Area shown before generating: thumbnails of picked photos, or a placeholder prompt.
    @ViewBuilder private var pickArea: some View {
        if sourceImages.isEmpty {
            ZStack {
                if let effectivePlaceholder {
                    RemoteImage(path: effectivePlaceholder.path, source: effectivePlaceholder.source, contentMode: .fit)
                        .opacity(0.4)
                } else {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(Color.avoraSurface)
                        .frame(height: 240)
                }
                Text("Pick up to 4 photos to start")
                    .foregroundStyle(Color.avoraTextSecondary)
                    .padding(Spacing.sm)
                    .avoraGlass(in: Capsule())
            }
            .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(Array(sourceImages.enumerated()), id: \.offset) { _, img in
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(height: 160).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
            }
        }
    }

    // Area shown after generating: one cell per job, each progressing independently.
    @ViewBuilder private var resultsGrid: some View {
        LazyVGrid(columns: columns, spacing: Spacing.md) {
            ForEach(poller.items) { item in
                resultCell(item)
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .background(Color.avoraSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
    }

    @ViewBuilder private func resultCell(_ item: BatchGenerationPoller.Item) -> some View {
        switch item.phase {
        case .working:
            ProgressView("Generating…")
        case .done(let path):
            RemoteImage(path: path, contentMode: .fill)
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    Button { Task { await saveOne(path) } } label: {
                        Image(systemName: "square.and.arrow.down")
                            .padding(Spacing.sm)
                            .avoraGlass(in: Circle())
                    }
                    .padding(Spacing.sm)
                }
        case .failed:
            Text("Couldn't generate — credit refunded")
                .font(.avoraFootnote)
                .foregroundStyle(Color.avoraTextSecondary)
                .multilineTextAlignment(.center)
                .padding(Spacing.sm)
        }
    }

    @ViewBuilder private var controls: some View {
        if hasResults {
            HStack {
                Button { Task { await saveAll() } } label: {
                    Label("Save all", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.avoraAccent)
                .disabled(isWorking)
                Button { reset() } label: {
                    Label("Generate again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .tint(Color.avoraAccent)
            }
        } else {
            AvoraPrimaryButton { Task { await generate() } } label: {
                VStack(spacing: Spacing.xs) {
                    Label("Generate", systemImage: "wand.and.stars")
                    Text("\(sourceImages.count * app.config.generationCost) credits")
                        .font(.avoraCaption)
                        .opacity(0.85)
                }
            }
            .disabled(sourceImages.isEmpty || isWorking)
        }
        if let errorText {
            Text(errorText).foregroundStyle(Color.avoraError).font(.avoraFootnote)
        }
    }

    private func loadPicked(_ newItems: [PhotosPickerItem]) async {
        var imgs: [UIImage] = []
        for item in newItems {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                imgs.append(img)
            }
        }
        sourceImages = imgs
        poller.stop()
        poller = BatchGenerationPoller()
        errorText = nil
    }

    private func generate() async {
        let imgs = sourceImages
        guard !imgs.isEmpty, !isSubmitting else { return }
        let cost = imgs.count * app.config.generationCost
        guard (app.profile?.totalCredits ?? 0) >= cost else { showPaywall = true; return }
        isSubmitting = true
        defer { isSubmitting = false }
        errorText = nil
        do {
            // Upload all inputs in parallel; if any fails, abort before submitting
            // so billing stays all-or-nothing (nothing is charged).
            let paths = try await withThrowingTaskGroup(of: (Int, String).self) { group -> [String] in
                for (i, img) in imgs.enumerated() {
                    group.addTask {
                        let data = ImageNormalizer.normalize(img)
                        let path = try await AvoraAPI.shared.uploadInput(data)
                        return (i, path)
                    }
                }
                var byIndex: [Int: String] = [:]
                for try await (i, path) in group { byIndex[i] = path }
                return imgs.indices.map { byIndex[$0]! }
            }
            let jobIds = try await AvoraAPI.shared.submitBatch(styleId: style.id, inputPaths: paths)
            poller.start(jobIds: jobIds, poll: { try await AvoraAPI.shared.poll(jobId: $0) })
        } catch AvoraError.insufficientCredits {
            showPaywall = true
        } catch {
            errorText = "Couldn't start generation. Try again."
        }
    }

    private func saveOne(_ path: String) async {
        guard let img = try? await ImageStore.shared.image(for: path) else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
    }

    private func saveAll() async {
        for item in poller.items {
            if case .done(let path) = item.phase {
                await saveOne(path)
            }
        }
    }

    private func reset() {
        poller.stop()
        poller = BatchGenerationPoller()
        pickerItems = []
        sourceImages = []
        errorText = nil
    }
}
```

- [ ] **Step 2: Delete the now-orphaned single-job poller**

Run: `git rm Avora/Services/GenerationPoller.swift`
(No other file references it — verified: only `CreateView` used it, and this rewrite drops that use.)

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: `** BUILD SUCCEEDED **` with no reference to `GenerationPoller`.

- [ ] **Step 4: Manual verification in the simulator**

Run the app (XcodeBuildMCP `build_run_sim`, or run the `Avora` scheme). Then:
1. Tap a style → the create screen shows "Pick up to 4 photos to start".
2. Pick 3 photos → 3 thumbnails appear; the Generate button reads `3 × <cost>` credits.
3. Tap Generate → a 3-cell grid appears, each showing "Generating…", then filling with results independently.
4. Confirm **Save all** writes the completed results to Photos, and **Generate again** returns to the picker.
5. With a low-credit account, picking more photos than affordable shows the paywall on Generate.

Expected: all five behave as described; failed cells (if any) show "Couldn't generate — credit refunded" and the credit is returned after `refreshProfile`.

- [ ] **Step 5: Commit**

```bash
git add Avora/Views/Create/CreateView.swift
git commit -m "feat: multi-photo batch generation in CreateView; remove single-job poller"
```

---

## Notes for the implementer

- **Run order matters:** Tasks 1→2 are backend and 3→4→5 are iOS; Task 5 depends on Tasks 3 and 4 compiling. Do them in order.
- **Simulator name:** if `iPhone 16` is not installed, substitute any booted simulator from `xcrun simctl list devices available` (or use XcodeBuildMCP `list_sims`).
- **Local Supabase:** backend steps assume `supabase start` is running; `supabase db reset` reapplies all migrations including the new one before `supabase test db`.
- **Do not** change per-generation cost, the queue worker, or `refund_credit` — per-job refunds already work because each row stores its own `charged_bucket`/`charged_amount`.
```
