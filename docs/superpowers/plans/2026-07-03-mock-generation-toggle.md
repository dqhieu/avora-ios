# Mock Generation Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a DEBUG-only Settings toggle that makes **Generate** fake the whole generation round-trip — no backend, no OpenAI, no cost — revealing a bundled image after ~10s using the real progress + reveal animations.

**Architecture:** A local `@AppStorage` toggle sets a flag read by `AvoraConfig.isMockGenerationEnabled`. When on, the three `AvoraAPI` methods on the Generate path (`uploadInput`, `submitBatch`, `poll`) short-circuit before any network call. `poll` sleeps 10s (per-job, on its own polling `Task`) then returns `status: .completed, output_path: "mock://result"`. `ImageStore` recognizes the `mock://` scheme and returns a bundled `MockResult` asset instead of downloading. Everything mock-related is wrapped in `#if DEBUG`, so a Release build contains none of it.

**Tech Stack:** Swift, SwiftUI, `@Observable`, Supabase SDK (bypassed in mock mode), Xcode asset catalog.

**Refinement over spec:** The spec ([docs/superpowers/specs/2026-07-03-mock-generation-toggle-design.md](../specs/2026-07-03-mock-generation-toggle-design.md)) proposed a `[UUID: Date]` start-time dictionary to simulate the delay. That is impossible cleanly because `AvoraAPI` is a `struct` behind `static let shared`. This plan instead sleeps inside the mock `poll`, since the poller already runs one independent `Task` per job. Behavior is identical (~10s, per-slot); mechanism is simpler and stateless.

## Global Constraints

- All mock code lives under `#if DEBUG` — zero footprint in Release builds.
- Toggle default: **off**. Persistence: local `UserDefaults` via `@AppStorage` (no backend).
- One bundled result image, shown for every slot in a batch. No cycling.
- Fixed delay: **10 seconds** (`10_000_000_000` nanoseconds).
- Success path only — no error/failure simulation, no credit changes.
- No XCTest target exists in this project and none is created here (out of scope for a DEBUG helper). Verification is by building and running in the iOS Simulator.
- Follow existing style: 4-space indent, terse doc comments matching neighboring code.

---

### Task 1: Config flag + Settings toggle

Adds the single source of truth for the mock key/constants and the DEBUG-only toggle UI. Deliverable: in a DEBUG build, Settings shows a working **Developer → Mock generation** toggle that persists across launches.

**Files:**
- Modify: `Avora/Config/AvoraConfig.swift` (append a `#if DEBUG` extension)
- Modify: `Avora/Views/Settings/SettingsView.swift:22-32` (add a section + a property)

**Interfaces:**
- Produces (all DEBUG-only):
  - `AvoraConfig.mockGenerationKey: String` = `"mockGenerationEnabled"`
  - `AvoraConfig.isMockGenerationEnabled: Bool`
  - `AvoraConfig.mockGenerationDelayNanos: UInt64` = `10_000_000_000`
  - `AvoraConfig.mockResultPath: String` = `"mock://result"`
  - `AvoraConfig.mockResultAssetName: String` = `"MockResult"`

- [ ] **Step 1: Add the mock config extension**

Append to the end of `Avora/Config/AvoraConfig.swift` (after the closing `}` of the enum):

```swift
#if DEBUG
extension AvoraConfig {
    /// UserDefaults key backing the DEBUG-only "Mock generation" toggle.
    static let mockGenerationKey = "mockGenerationEnabled"

    /// When on, Generate fakes the whole round-trip instead of hitting the backend.
    static var isMockGenerationEnabled: Bool {
        UserDefaults.standard.bool(forKey: mockGenerationKey)
    }

    /// Simulated backend latency before the fake result is "ready".
    static let mockGenerationDelayNanos: UInt64 = 10_000_000_000

    /// Sentinel result path; `ImageStore` maps it to the bundled asset below.
    static let mockResultPath = "mock://result"
    static let mockResultAssetName = "MockResult"
}
#endif
```

- [ ] **Step 2: Add the toggle property to SettingsView**

In `Avora/Views/Settings/SettingsView.swift`, add this property just below the existing `@State private var deleteError: String?` (line 7):

```swift
#if DEBUG
@AppStorage(AvoraConfig.mockGenerationKey) private var mockGeneration = false
#endif
```

- [ ] **Step 3: Add the Developer section**

In the same file, insert this section immediately after the Sign Out `Section` (the one closing at line 32), before the Delete Account `Section`:

```swift
#if DEBUG
Section("Developer") {
    Toggle("Mock generation", isOn: $mockGeneration)
}
#endif
```

- [ ] **Step 4: Build for the simulator**

Run (XcodeBuildMCP): `build_sim` for scheme `Avora` on an iOS simulator (confirm the scheme name first with `list_schemes` if unsure). Or in Xcode: ⌘B.
Expected: build succeeds, no warnings about `mockGeneration`.

- [ ] **Step 5: Verify the toggle in the simulator**

Run the app, open Settings (gear icon on the styles grid). Confirm a **Developer** section with a **Mock generation** switch appears. Toggle it on, force-quit, relaunch, reopen Settings — the switch is still on. Toggle it back off.
Expected: switch renders, persists, defaults off on a fresh install.

- [ ] **Step 6: Commit**

```bash
git add Avora/Config/AvoraConfig.swift Avora/Views/Settings/SettingsView.swift
git commit -m "feat: add DEBUG-only mock generation toggle in settings"
```

---

### Task 2: Short-circuit AvoraAPI on the Generate path

Makes the three network methods return instantly-fake data when the flag is on. Deliverable: with the toggle on, tapping Generate performs zero network calls and drives the poller to completion after ~10s. (The revealed image will fail to load until Task 3 — expected.)

**Files:**
- Modify: `Avora/Services/AvoraAPI.swift` — `uploadInput` (line 44), `submitBatch` (line 68), `poll` (line 84)

**Interfaces:**
- Consumes: `AvoraConfig.isMockGenerationEnabled`, `AvoraConfig.mockGenerationDelayNanos`, `AvoraConfig.mockResultPath` (Task 1).
- Consumes: `GenerationResult(status:outputPath:errorCode:)` — memberwise init of the struct in `Avora/Models/Generation.swift:20`; `GenStatus.completed`.
- Produces: `poll` returns `GenerationResult(status: .completed, outputPath: "mock://result", errorCode: nil)` after the delay; `submitBatch` returns one fresh `UUID` per input path; `uploadInput` returns `"mock://input"`.

- [ ] **Step 1: Mock `uploadInput`**

In `Avora/Services/AvoraAPI.swift`, make `uploadInput` return early. Replace the body's first line so the function reads:

```swift
func uploadInput(_ data: Data) async throws -> String {
    #if DEBUG
    if AvoraConfig.isMockGenerationEnabled { return "mock://input" }
    #endif
    let uid = try await currentUserId()
    let path = "\(uid.uuidString.lowercased())/\(UUID().uuidString).png"
    try await db.storage.from("inputs")
        .upload(path, data: data, options: FileOptions(contentType: "image/png"))
    return path
}
```

- [ ] **Step 2: Mock `submitBatch`**

Insert the early return at the top of `submitBatch`, before the `struct Body` line:

```swift
func submitBatch(styleId: String, inputPaths: [String]) async throws -> [UUID] {
    #if DEBUG
    if AvoraConfig.isMockGenerationEnabled { return inputPaths.map { _ in UUID() } }
    #endif
    struct Body: Encodable { let style_id: String; let input_paths: [String] }
    // ...rest unchanged...
```

- [ ] **Step 3: Mock `poll`**

Insert the early return at the top of `poll`, before the `try await db.functions.invoke` line:

```swift
func poll(jobId: UUID) async throws -> GenerationResult {
    #if DEBUG
    if AvoraConfig.isMockGenerationEnabled {
        try await Task.sleep(nanoseconds: AvoraConfig.mockGenerationDelayNanos)
        return GenerationResult(status: .completed, outputPath: AvoraConfig.mockResultPath, errorCode: nil)
    }
    #endif
    return try await db.functions.invoke(
        "get-generation",
        options: .init(
            method: .get,
            query: [URLQueryItem(name: "id", value: jobId.uuidString)]
        )
    )
}
```

Note: the current `poll` body is `try await db.functions.invoke(...)` returned implicitly. Add the explicit `return` shown above so the function has two return statements.

- [ ] **Step 4: Build for the simulator**

Run (XcodeBuildMCP): `build_sim` for scheme `Avora`. Or ⌘B.
Expected: build succeeds.

- [ ] **Step 5: Verify the flow drives to completion**

Run the app, enable **Mock generation** in Settings, pick a photo, tap **Generate**. Confirm: the Generate button enters its working/spinner state immediately, and after ~10s the slot leaves the working state (the reveal will show a broken/empty image — that's fixed in Task 3). Optionally confirm no network by watching Xcode's network activity or that it works in Airplane Mode.
Expected: no crash, poller reaches a terminal phase after ~10s with the toggle on.

- [ ] **Step 6: Commit**

```bash
git add Avora/Services/AvoraAPI.swift
git commit -m "feat: short-circuit generation API calls in mock mode"
```

---

### Task 3: Bundled image + `mock://` resolution in ImageStore

Adds the result asset and teaches `ImageStore` to serve it for `mock://` paths. Deliverable: `mock://result` resolves to the bundled `MockResult` image with no network.

**Files:**
- Create: `Avora/Assets.xcassets/MockResult.imageset/Contents.json` (+ a PNG)
- Modify: `Avora/Services/ImageStore.swift` — `image(for:source:)` (line 34)

**Interfaces:**
- Consumes: `AvoraConfig.mockResultAssetName` (Task 1); the `"mock://"` scheme produced by `poll` (Task 2).

- [ ] **Step 1: Add the MockResult image set**

Easiest path in Xcode: open `Assets.xcassets`, add a new Image Set named `MockResult`, and drag any representative PNG into the 1x/universal slot (a screenshot of a real generated result is ideal). Confirm the asset is a member of the Avora target.

If adding by hand, create `Avora/Assets.xcassets/MockResult.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "mock-result.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    { "idiom" : "universal", "scale" : "2x" },
    { "idiom" : "universal", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

Then place a PNG at `Avora/Assets.xcassets/MockResult.imageset/mock-result.png`.

- [ ] **Step 2: Resolve `mock://` in ImageStore**

In `Avora/Services/ImageStore.swift`, add the DEBUG branch at the very top of `image(for:source:)`, before the `cacheKey` line (line 35):

```swift
func image(for path: String, source: Source = .output) async throws -> UIImage {
    #if DEBUG
    if path.hasPrefix("mock://") {
        if let img = UIImage(named: AvoraConfig.mockResultAssetName) { return img }
        throw Failure.decode
    }
    #endif
    let cacheKey = "\(source):\(path)"
    // ...rest unchanged...
```

- [ ] **Step 3: Build for the simulator**

Run (XcodeBuildMCP): `build_sim` for scheme `Avora`. Or ⌘B.
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Avora/Assets.xcassets/MockResult.imageset Avora/Services/ImageStore.swift
git commit -m "feat: serve bundled asset for mock:// image paths"
```

---

### Task 4: End-to-end verification

No code change — proves the feature works together and that Release excludes it. Deliverable: a verified mock flow and a clean Release build.

**Files:** none.

- [ ] **Step 1: Full mock flow in the simulator**

`build_run_sim` for scheme `Avora`. In the app: Settings → enable **Mock generation**. Return to Create, pick 2 photos, tap **Generate**.
Expected: both slots show the working state, then after ~10s each cross-fades to the `MockResult` image using the normal focus-pull reveal. No credits are spent (credit count unchanged). Works in Airplane Mode.

- [ ] **Step 2: Toggle-off sanity check**

Disable **Mock generation**. Confirm the Generate button again shows the real credit cost and the real code path is taken (a real tap will attempt upload/submit — no need to complete a paid generation; just confirm no `mock://` behavior).
Expected: default behavior restored when off.

- [ ] **Step 3: Release build excludes mock code**

Build the `Avora` scheme with the **Release** configuration (Xcode: Product → Scheme → Edit Scheme → Run → Release, then ⌘B; or `xcodebuild -scheme Avora -configuration Release build`).
Expected: builds cleanly. The `#if DEBUG` guards mean `isMockGenerationEnabled`, the toggle, the API branches, and the `mock://` handler are all compiled out.

- [ ] **Step 4: Final commit (if any tidy-ups)**

```bash
git add -A
git commit -m "chore: verify mock generation flow end-to-end" --allow-empty
```

---

## Self-Review

**Spec coverage:**
- Toggle (`@AppStorage`, DEBUG Developer section) → Task 1 ✅
- Centralized flag `isMockGenerationEnabled` (false in Release via `#if DEBUG`) → Task 1 ✅
- Intercept `uploadInput` / `submitBatch` / `poll` → Task 2 ✅
- 10s delay → Task 2 (`mockGenerationDelayNanos`, sleep in `poll`) ✅
- Bundled `MockResult` asset + `mock://` handling in `ImageStore` → Task 3 ✅
- One image for every slot → Tasks 2–3 (single sentinel path, single asset) ✅
- No credit change / no error sim / zero Release footprint → Global Constraints + Task 4 Step 3 ✅
- Spec's start-time-dict mechanism → intentionally superseded (documented in Refinement note); behavior preserved ✅

**Type consistency:** `GenerationResult(status:outputPath:errorCode:)` matches `Avora/Models/Generation.swift:20`; `GenStatus.completed` matches. Poller maps `.completed` + non-empty `outputPath` → `.done` (`BatchGenerationPoller.swift:38-40`), so `mock://result` flows through unchanged. Config symbol names (`mockGenerationKey`, `isMockGenerationEnabled`, `mockGenerationDelayNanos`, `mockResultPath`, `mockResultAssetName`) are used identically across Tasks 1–3.

**Placeholder scan:** none — every code step shows complete code.
