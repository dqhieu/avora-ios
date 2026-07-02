# Pixelate → Sharpen Generation Reveal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `SparkleDrift` generation animation in `CreateView` with a pixelate-then-sharpen reveal driven by a Metal `.layerEffect` shader.

**Architecture:** A single stitchable Metal `pixellate` shader exposes one `size` (block-edge) uniform. A new self-contained `PixelReveal` card view drives that uniform through three phases — ramp to max blocks, gentle pulse at max, then sharpen to crisp — and loads the finished result through `ImageStore`. `CreateView.slotCard` renders one stable `PixelReveal` instance across the working→done transition so view identity (and thus the block-size state) persists and the reveal is continuous. `SparkleDrift` is deleted.

**Tech Stack:** Swift, SwiftUI, Metal (`SwiftUI::Layer` stitchable shader via `ShaderLibrary` / `.layerEffect`), Xcode synchronized folders.

## Global Constraints

- iOS deployment target 18.0 — `.layerEffect` (iOS 17+) is safe.
- This repo uses **Xcode synchronized folders**: any `.swift` / `.metal` file created under `Avora/` is auto-added to the `Avora` target and its build phases. Do NOT edit `Avora.xcodeproj/project.pbxproj`.
- Build/verify with scheme **Avora** on simulator **iPhone 17**.
- No changes to `BatchGenerationPoller`, billing, upload/submit, save/reset, or `RemoteImage`.
- Commit message style: conventional commits, no AI references (per repo rules).
- `Phase` enum (in `Avora/Services/BatchGenerationPoller.swift`): `case working, done(outputPath: String), failed(code: String?)`. `poller.items[i].phase` is a non-optional `Phase`; `slotCard` reads it as `Phase?` because the index may not yet exist in `poller.items`.

### Build command (used by every task's verify step)

Preferred (XcodeBuildMCP):
```
build_sim({ projectPath: "/Users/hieudinh/Projects/avora-ios/Avora.xcodeproj", scheme: "Avora", simulatorName: "iPhone 17" })
```
CLI fallback:
```bash
cd /Users/hieudinh/Projects/avora-ios && \
xcodebuild -project Avora.xcodeproj -scheme Avora \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected on success: `** BUILD SUCCEEDED **`.

---

## Task 1: Metal pixellate shader

**Files:**
- Create: `Avora/Views/PixelShader.metal`

**Interfaces:**
- Consumes: nothing.
- Produces: a stitchable shader function `pixellate` callable from SwiftUI as `ShaderLibrary.pixellate(.float(size))` and applied via `.layerEffect(_:maxSampleOffset:)`. `size` is the block edge length in points; `size <= 1` renders the layer unchanged (sharp).

- [ ] **Step 1: Write the shader file**

Create `Avora/Views/PixelShader.metal` with exactly:

```metal
#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// Snaps each sampled pixel to a `size`-point grid, producing square blocks.
// size <= 1 is a passthrough so the same shader renders the sharp end of the
// pixelate/sharpen animation.
[[ stitchable ]] half4 pixellate(float2 position,
                                 SwiftUI::Layer layer,
                                 float size) {
    if (size <= 1.0) {
        return layer.sample(position);
    }
    float2 snapped = floor(position / size) * size + size * 0.5;
    return layer.sample(snapped);
}
```

- [ ] **Step 2: Build to verify the shader compiles into the target**

Run the build command (see Global Constraints). The Metal file is auto-compiled into `default.metallib` by Xcode's synchronized folder + Metal build phase.
Expected: `** BUILD SUCCEEDED **`. A Metal syntax error would fail the build here.

- [ ] **Step 3: Commit**

```bash
cd /Users/hieudinh/Projects/avora-ios
git add Avora/Views/PixelShader.metal
git commit -m "feat: add pixellate layer-effect shader"
```

---

## Task 2: PixelReveal card view

**Files:**
- Create: `Avora/Views/PixelReveal.swift`

**Interfaces:**
- Consumes: `ShaderLibrary.pixellate(.float(_))` from Task 1; `ImageStore.shared.image(for:)` (existing — returns `UIImage`, `async throws`, defaults to `.output` source); `Radius.lg` (existing design token).
- Produces:
  ```swift
  struct PixelReveal: View {
      let source: UIImage
      let resultPath: String?   // non-nil once the job phase is .done(outputPath:)
      let isGenerating: Bool    // true during isSubmitting / .working
  }
  ```
  Renders a rounded card that pixelates the source while generating and sharpens into the downloaded result. Consumed by Task 3.

- [ ] **Step 1: Write the view**

Create `Avora/Views/PixelReveal.swift` with exactly:

```swift
import SwiftUI

/// A generation card that dissolves the source photo into pixel blocks while its
/// job runs, holds (with a gentle pulse) through the result download, then
/// sharpens the finished result into focus. Replaces `SparkleDrift`.
struct PixelReveal: View {
    let source: UIImage
    let resultPath: String?
    let isGenerating: Bool

    /// Max block edge in points at full pixelation.
    private let maxBlock: CGFloat = 24
    /// How far the block size dips below max on each pulse.
    private let pulseDip: CGFloat = 4

    @State private var blockSize: CGFloat = 1
    @State private var resultImage: UIImage?
    @State private var resultOpacity: CGFloat = 0

    var body: some View {
        ZStack {
            cardImage(source)
            if let resultImage {
                cardImage(resultImage).opacity(resultOpacity)
            }
        }
        .layerEffect(
            ShaderLibrary.pixellate(.float(blockSize)),
            maxSampleOffset: CGSize(width: maxBlock, height: maxBlock)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onAppear { if isGenerating { startPixelating() } }
        .onChange(of: isGenerating) { _, gen in if gen { startPixelating() } }
        .task(id: resultPath) { await revealResult() }
    }

    private func cardImage(_ img: UIImage) -> some View {
        Image(uiImage: img)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    // Ramp from sharp to full blocks, then breathe at max until the result lands.
    private func startPixelating() {
        withAnimation(.easeInOut(duration: 2.5)) {
            blockSize = maxBlock
        } completion: {
            guard resultImage == nil, isGenerating else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                blockSize = maxBlock - pulseDip
            }
        }
    }

    // Load the finished result, cross-fade it in beneath the blocks so there is
    // no content pop, then sharpen from the held block size to crisp.
    private func revealResult() async {
        guard let resultPath else { return }
        do {
            let img = try await ImageStore.shared.image(for: resultPath)
            resultImage = img
            withAnimation(.easeOut(duration: 0.25)) { resultOpacity = 1 }
            withAnimation(.easeInOut(duration: 0.6).delay(0.15)) { blockSize = 1 }
        } catch {
            // Download failed: sharpen the source back so the user still sees a photo.
            withAnimation(.easeInOut(duration: 0.6)) { blockSize = 1 }
        }
    }
}

#Preview {
    PixelReveal(
        source: UIImage(systemName: "photo.fill")!
            .withTintColor(.systemTeal, renderingMode: .alwaysOriginal),
        resultPath: nil,
        isGenerating: true
    )
    .frame(width: 300, height: 400)
    .padding()
}
```

- [ ] **Step 2: Build to verify it compiles**

Run the build command (see Global Constraints).
Expected: `** BUILD SUCCEEDED **`.

Common failure to check: if `ImageStore.shared.image(for:)` requires a `source:` argument (no default), change the call to `ImageStore.shared.image(for: resultPath, source: .output)` to match how `RemoteImage` loads outputs. Confirm the signature in `Avora/Services/ImageStore.swift` before deciding.

- [ ] **Step 3: Visually smoke-test the preview (optional but recommended)**

Open `Avora/Views/PixelReveal.swift` in Xcode and run the SwiftUI preview. Expected: the teal photo symbol ramps into blocks over ~2.5s then gently pulses. This confirms the shader + ramp/pulse before integration.

- [ ] **Step 4: Commit**

```bash
cd /Users/hieudinh/Projects/avora-ios
git add Avora/Views/PixelReveal.swift
git commit -m "feat: add PixelReveal pixelate-to-sharpen generation card"
```

---

## Task 3: Integrate into CreateView and remove SparkleDrift

**Files:**
- Modify: `Avora/Views/Create/CreateView.swift:123-152` (the `slotCard(_:)` function)
- Delete: `Avora/Views/SparkleDrift.swift`

**Interfaces:**
- Consumes: `PixelReveal(source:resultPath:isGenerating:)` from Task 2.
- Produces: nothing new; `slotCard` now emits `PixelReveal` for every non-failed phase.

- [ ] **Step 1: Replace the body of `slotCard(_:)`**

In `Avora/Views/Create/CreateView.swift`, replace the entire current `slotCard` function (the `@ViewBuilder private func slotCard(_ index: Int) -> some View { ... }` block, currently lines 123-152 including the leading doc comment on 121-122) with:

```swift
    // One card per picked photo. It pixelates while its job generates, sharpens
    // into the finished result once ready, or shows a refunded badge if it failed.
    @ViewBuilder private func slotCard(_ index: Int) -> some View {
        let phase = poller.items.indices.contains(index) ? poller.items[index].phase : nil
        if case .failed = phase {
            photoCard(sourceImages[index]) {
                ZStack(alignment: .bottomTrailing) {
                    Color.black.opacity(0.2)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.avoraFootnote)
                        .foregroundStyle(Color.avoraTextPrimary)
                        .padding(Spacing.sm)
                        .avoraGlass(in: Circle())
                        .padding(Spacing.sm)
                }
            }
        } else {
            let resultPath: String? = {
                if case .done(let path) = phase { return path } else { return nil }
            }()
            let isWorkingPhase: Bool = {
                if case .working = phase { return true } else { return false }
            }()
            PixelReveal(
                source: sourceImages[index],
                resultPath: resultPath,
                isGenerating: isSubmitting || isWorkingPhase
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
```

Note: the `.failed` branch is copied verbatim from the current code (it still uses the existing `photoCard` helper, `avoraGlass`, `Spacing`, and font/color tokens — all unchanged). The `.done`, `.working`, and `nil`+`isSubmitting` branches are all replaced by the single `PixelReveal`.

- [ ] **Step 2: Delete the SparkleDrift file**

```bash
cd /Users/hieudinh/Projects/avora-ios
git rm Avora/Views/SparkleDrift.swift
```

(`SparkleDrift` had only two references, both in the old `slotCard`; Step 1 removed them.)

- [ ] **Step 3: Verify no remaining references**

```bash
cd /Users/hieudinh/Projects/avora-ios
grep -rn "SparkleDrift" Avora
```
Expected: no output.

- [ ] **Step 4: Build**

Run the build command (see Global Constraints).
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/hieudinh/Projects/avora-ios
git add Avora/Views/Create/CreateView.swift
git commit -m "feat: use PixelReveal for generation cards, remove SparkleDrift"
```

---

## Task 4: Verify the full flow in the simulator

**Files:** none (manual verification).

**Interfaces:** none.

This is the real acceptance gate — the animation cannot be unit-tested, so verify it by running the app.

- [ ] **Step 1: Build and run on simulator**

```
build_run_sim({ projectPath: "/Users/hieudinh/Projects/avora-ios/Avora.xcodeproj", scheme: "Avora", simulatorName: "iPhone 17" })
```

- [ ] **Step 2: Walk the generation flow and confirm each criterion**

Navigate: pick a style → pick 1 photo → tap Generate. Confirm:
- No sparkles anywhere.
- On Generate, the source card ramps into pixel blocks over ~2.5s, then gently pulses at max.
- No `ProgressView` spinner appears between the job finishing and the image showing.
- When the result is ready, it sharpens into focus from the block size (no hard pop, no spinner).

Then repeat with **4 photos** and confirm each card pixelates/reveals on its own timeline.

If a real backend failure is hard to trigger, this is acceptable to skip — but if any card fails, confirm it shows the warning badge over the (un-pixelated) source, matching prior behaviour.

- [ ] **Step 3: Screenshot the pixelated state for the record (optional)**

```
screenshot({ simulatorName: "iPhone 17" })
```
during generation, to capture the mid-ramp pixelation.

- [ ] **Step 4: No commit** (verification only). If a tuning value felt off (e.g. `maxBlock`, ramp duration), adjust the constants in `PixelReveal.swift`, rebuild, and commit separately with `fix: tune PixelReveal timing`.

---

## Self-Review

**Spec coverage:**
- Pixelate shader (`PixelShader.metal`) → Task 1. ✓
- `PixelReveal` view with ramp / pulse / sharpen + `ImageStore` load → Task 2. ✓
- Ramp-then-pulse timing → `startPixelating()` in Task 2. ✓
- Sharpen-into-focus reveal (result at matched block, cross-fade, then sharpen) → `revealResult()` in Task 2. ✓
- Single stable `PixelReveal` across working→done in `slotCard` → Task 3. ✓
- Failed state unchanged (badge, no pixelation) → Task 3 `.failed` branch. ✓
- Idle shows sharp source → `PixelReveal` with `isGenerating=false`, `resultPath=nil`, `blockSize=1` initial → Task 2/3. ✓
- No spinner between done and display → Task 4 verification. ✓
- Delete `SparkleDrift.swift` → Task 3. ✓
- Batch: per-card timelines → Task 4 verification. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; the `.failed` branch is repeated in full rather than referenced. ✓

**Type consistency:** `PixelReveal(source: UIImage, resultPath: String?, isGenerating: Bool)` defined in Task 2 and called with matching argument types/labels in Task 3. `blockSize`/`maxBlock`/`pulseDip` are all `CGFloat`. `ShaderLibrary.pixellate(.float(blockSize))` matches the shader's single `float size` argument from Task 1. ✓
