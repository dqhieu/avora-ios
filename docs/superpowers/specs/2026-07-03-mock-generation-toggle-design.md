# Mock Generation Toggle (DEBUG-only) — Design

**Date:** 2026-07-03
**Status:** Approved, ready for implementation plan

## Problem

Testing the app currently triggers real image generation, which calls OpenAI via the
backend and costs money on every tap of **Generate**. We want a way to exercise the full
create → generate → reveal UX during testing without spending money or touching the backend.

## Key finding

The app never calls OpenAI directly. When **Generate** is tapped, [CreateView.swift:222](../../../Avora/Views/Create/CreateView.swift)
does three things through `AvoraAPI.shared`:

1. `uploadInput(data)` — upload each photo to Supabase storage → path
2. `submitBatch(styleId:inputPaths:)` — queue the jobs → `[UUID]`
3. `poll(jobId:)` — poll each job until phase becomes `.done(outputPath:)`

The result path is then downloaded by `ImageStore` and cross-faded in by `FocusReveal`.
The OpenAI cost lives *behind* `submitBatch`, on the backend. Therefore the cheapest way to
eliminate cost is to **intercept on the client** so the request never reaches the backend —
no mock server, no network, works offline, $0.

## Approach

Client-side interception (chosen over an injected mock-service protocol or a real staging
mock server — both are more work for a test-only feature). A local toggle short-circuits the
three `AvoraAPI` methods. The **real poller and reveal animation are left intact**, so testing
still exercises the genuine progress spinner, the delay, and the focus-pull reveal — only the
network and the result image are faked.

Everything mock-related is wrapped in `#if DEBUG` so it compiles out of release builds. Zero
production footprint; no real user can trigger it.

## Design

### 1. Toggle

- `@AppStorage("mockGenerationEnabled")` bool, defaults `false`. First `@AppStorage` in the app;
  local UserDefaults only, no backend.
- New **Developer** section in [SettingsView.swift](../../../Avora/Views/Settings/SettingsView.swift)
  containing a single `Toggle("Mock generation")`. The whole section is wrapped in `#if DEBUG`.

### 2. Centralized flag

- `AvoraConfig.isMockGenerationEnabled` in [AvoraConfig.swift](../../../Avora/Config/AvoraConfig.swift):
  - DEBUG: returns `UserDefaults.standard.bool(forKey: "mockGenerationEnabled")`
  - RELEASE: returns hardcoded `false`
- Keeps the interception branches readable and guarantees the release path is dead-simple.

### 3. Interception in AvoraAPI (all mock bodies under `#if DEBUG`)

[AvoraAPI.swift](../../../Avora/Services/AvoraAPI.swift), guarded by `isMockGenerationEnabled`:

1. **`uploadInput(data)`** — return a dummy path immediately. No storage write.
2. **`submitBatch(styleId:inputPaths:)`** — generate one fake `UUID` per input path, record
   `Date()` for each in a private in-memory `[UUID: Date]` start-time dict, return the UUIDs.
   No network, no 402/credit path.
3. **`poll(jobId:)`** — look up the job's start time; return `.processing` until 10s have
   elapsed, then `.done(outputPath: "mock://result")`.

The start-time dict is what lets a stateless `poll` simulate the 10-second delay across
repeated calls. Because interception happens at `poll`, a batch of N photos each reveals
independently after ~10s, matching the real flow.

### 4. Bundled result image

- Add one image asset `MockResult` to `Assets.xcassets`.
- In [ImageStore.swift](../../../Avora/Services/ImageStore.swift), recognize the `mock://`
  scheme and return `UIImage(named: "MockResult")` directly, skipping the signed-URL download
  and disk/memory cache path.
- Every slot in a batch shows the same bundled image (decided: one image, not cycled).

## Out of scope (YAGNI)

- **Credit changes.** Nothing hits the backend, so credits won't decrement in mock mode. This
  is acceptable for testing and will simply be left as-is (noted, not faked).
- **Error/failure simulation.** Only the success path, as requested. Can be added later.
- **Configurable delay.** Fixed 10s (a single constant, easy to change later).

## Files touched

| File | Change |
|------|--------|
| `Avora/Views/Settings/SettingsView.swift` | `#if DEBUG` Developer section + mock toggle |
| `Avora/Config/AvoraConfig.swift` | `isMockGenerationEnabled` helper (false in release) |
| `Avora/Services/AvoraAPI.swift` | Mock branches in `uploadInput` / `submitBatch` / `poll` + start-time dict |
| `Avora/Services/ImageStore.swift` | `mock://` scheme → bundled `MockResult` asset |
| `Assets.xcassets` | New `MockResult` image |

## Success criteria

- In a DEBUG build, Settings shows a Developer → Mock generation toggle; a Release build does not.
- With the toggle on, tapping Generate spends no credits, makes no network calls, and after
  ~10s reveals the bundled `MockResult` image using the normal reveal animation — for each
  selected photo.
- With the toggle off, behavior is unchanged (real generation).
- No mock code compiles into a Release build.
