# Scan-Line Reveal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the blur-based generation animation in `CreateView` with a scan-line reveal — a glowing accent line sweeps top→bottom while generating, then wipes the finished result in from the top.

**Architecture:** Rewrite the single view `FocusReveal` as `ScanReveal` (same `(source, resultPath, isGenerating)` interface). The source photo stays sharp; a looping `Capsule` line scans while `resultImage == nil`; when the downloaded result lands, one sweep drives both the line position and a top-anchored mask on the result layer so the new image is unveiled row by row. Pure SwiftUI — no shaders, no new dependencies.

**Tech Stack:** SwiftUI, `GeometryReader`, `.mask`, `withAnimation` completion handlers, existing `ImageStore` / `Color.avoraAccent` / `Radius.lg`.

## Global Constraints

- Keep the initializer interface identical to `FocusReveal`: `init(source: UIImage, resultPath: String?, isGenerating: Bool)` — the only call site is `CreateView.slotCard`.
- File rename is safe without `.pbxproj` edits: the project uses Xcode synchronized folders.
- Do not touch `CreateView` layout, controls, polling, or the failed-generation badge (the `if case .failed` branch in `slotCard`).
- No new Swift packages.
- Tunable constants live as named `private let` at the top of the struct: `loopDuration = 1.8`, `revealDuration = 1.2`, `lineThickness = 2.5`, `glowBlur = 8`.
- Scheme `Avora`, project `Avora.xcodeproj`.

**Note on testing:** This is a pure animation view; there is no meaningful XCTest for sweep timing or masking. The verification cycle for each task is **compile-clean** (Task 1) plus **visual confirmation in the simulator using the existing Mock generation toggle** (Task 2). That is the honest test loop for this change.

---

### Task 1: Implement `ScanReveal` and rewire the call site

**Files:**
- Create: `Avora/Views/ScanReveal.swift`
- Modify: `Avora/Views/Create/CreateView.swift` (`slotCard`, the `FocusReveal(...)` call ~line 184)
- Delete: `Avora/Views/FocusReveal.swift`

**Interfaces:**
- Consumes (existing, unchanged): `ImageStore.shared.image(for:) async throws -> UIImage`, `Color.avoraAccent`, `Radius.lg`.
- Produces: `struct ScanReveal: View` with `init(source: UIImage, resultPath: String?, isGenerating: Bool)`.

- [ ] **Step 1: Create `Avora/Views/ScanReveal.swift` with the full implementation**

```swift
import SwiftUI

/// A generation card that keeps the source photo sharp while a glowing accent
/// line sweeps top→bottom on a loop ("scanning"). When the result arrives, one
/// final sweep wipes the finished image in from the top: everything above the
/// line shows the result, everything below still shows the source, so the new
/// image is unveiled row by row. Replaces the blur-based FocusReveal.
struct ScanReveal: View {
    let source: UIImage
    let resultPath: String?
    let isGenerating: Bool

    /// Seconds for one top→bottom pass while waiting for the result.
    private let loopDuration: Double = 1.8
    /// Seconds for the single sweep that wipes the finished result in.
    private let revealDuration: Double = 1.2
    /// Height of the scan line in points.
    private let lineThickness: CGFloat = 2.5
    /// Blur radius of the glow copy behind the line.
    private let glowBlur: CGFloat = 8

    /// 0...1 looping line position while generating.
    @State private var scanY: CGFloat = 0
    /// 0...1 wipe position; also the height fraction of the revealed result.
    @State private var revealProgress: CGFloat = 0
    @State private var resultImage: UIImage?
    /// Once true, the visible line follows `revealProgress` instead of `scanY`.
    @State private var isRevealing = false
    @State private var lineOpacity: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let lineFraction = isRevealing ? revealProgress : scanY
            ZStack(alignment: .top) {
                cardImage(source)
                if let resultImage {
                    cardImage(resultImage)
                        .mask(alignment: .top) {
                            Rectangle().frame(height: h * revealProgress)
                        }
                }
                scanLine
                    .offset(y: h * lineFraction - lineThickness / 2)
                    .opacity(lineOpacity)
            }
            .frame(width: geo.size.width, height: h)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onAppear { if isGenerating { startScanning() } }
        .onChange(of: isGenerating) { _, gen in if gen { startScanning() } }
        .task(id: resultPath) { await revealResult() }
    }

    private func cardImage(_ img: UIImage) -> some View {
        Image(uiImage: img)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    // Thin accent line with a soft blurred glow copy behind it.
    private var scanLine: some View {
        ZStack {
            Capsule()
                .fill(Color.avoraAccent)
                .frame(height: lineThickness)
                .blur(radius: glowBlur)
            Capsule()
                .fill(Color.avoraAccent)
                .frame(height: lineThickness)
        }
        .frame(maxWidth: .infinity)
    }

    // Loop the line top→bottom while the job runs.
    private func startScanning() {
        guard resultImage == nil, !isRevealing else { return }
        lineOpacity = 1
        scanY = 0
        withAnimation(.linear(duration: loopDuration).repeatForever(autoreverses: false)) {
            scanY = 1
        }
    }

    // Download the result, then run one top→bottom sweep that wipes it in.
    private func revealResult() async {
        guard let resultPath else { return }
        do {
            let img = try await ImageStore.shared.image(for: resultPath)
            resultImage = img
            isRevealing = true
            revealProgress = 0
            lineOpacity = 1
            withAnimation(.easeInOut(duration: revealDuration)) {
                revealProgress = 1
            } completion: {
                withAnimation(.easeOut(duration: 0.3)) { lineOpacity = 0 }
            }
        } catch {
            // Download failed: stop scanning, keep the sharp source, fade the line out.
            isRevealing = true
            withAnimation(.easeOut(duration: 0.3)) { lineOpacity = 0 }
        }
    }
}

#Preview {
    ScanReveal(
        source: UIImage(systemName: "photo.fill")!
            .withTintColor(.systemTeal, renderingMode: .alwaysOriginal),
        resultPath: nil,
        isGenerating: true
    )
    .frame(width: 300, height: 400)
    .padding()
}
```

- [ ] **Step 2: Update the call site in `CreateView.slotCard`**

In `Avora/Views/Create/CreateView.swift`, find the `FocusReveal(...)` call (~line 184) and change only the type name:

```swift
            ScanReveal(
                source: sourceImages[index],
                resultPath: resultPath,
                isGenerating: isSubmitting || isWorkingPhase
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
```

- [ ] **Step 3: Delete the old file**

```bash
rm Avora/Views/FocusReveal.swift
```

- [ ] **Step 4: Confirm no stray references remain**

Run: `grep -rn "FocusReveal" Avora`
Expected: no output (empty).

- [ ] **Step 5: Build for the simulator to verify it compiles clean**

Use XcodeBuildMCP `build_sim` (scheme `Avora`, an iOS simulator), or:

```bash
xcodebuild -project Avora.xcodeproj -scheme Avora \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`, no errors referencing `ScanReveal` or `FocusReveal`.

- [ ] **Step 6: Commit**

```bash
git add Avora/Views/ScanReveal.swift Avora/Views/Create/CreateView.swift
git rm --cached Avora/Views/FocusReveal.swift 2>/dev/null; git add -A Avora/Views
git commit -m "feat: replace blur generation animation with scan-line reveal"
```

---

### Task 2: Visual verification and tuning

**Files:**
- Modify (only if tuning is needed): `Avora/Views/ScanReveal.swift` (the four tunable constants)

**Interfaces:** none — verification task.

- [ ] **Step 1: Build & run on a simulator with Mock generation enabled**

Use XcodeBuildMCP `build_run_sim` (scheme `Avora`). Once running, open **Settings** tab in the app and turn on the **Mock generation** toggle (`SettingsView`, line ~41). Mock jobs finish after ~10s (`AvoraConfig.mockGenerationDelayNanos`), giving a long window to watch the scan loop before the reveal.

- [ ] **Step 2: Verify the generating loop**

Pick a style, add one photo, tap **Generate**. Confirm:
- The source photo stays **sharp** (no blur at any point).
- A glowing accent line sweeps **top→bottom repeatedly**, ~1.8s per pass, with a soft glow.

- [ ] **Step 3: Verify the wipe reveal**

When the mock job completes (~10s), confirm:
- One top→bottom sweep runs; the finished (mock) result is **unveiled from the top down**, with the line at the boundary between result (above) and source (below).
- The line **fades out** once it reaches the bottom, leaving the sharp result.

- [ ] **Step 4: Verify multi-photo independence**

Reset, add 2–4 photos, tap **Generate**. Confirm each card scans and reveals on its own (lines are not synchronized across cards). Confirm a failed slot still shows the existing error badge (unchanged behavior).

- [ ] **Step 5: Tune if needed, then commit**

If any timing/thickness/glow feels off, adjust the constants at the top of `ScanReveal` (`loopDuration`, `revealDuration`, `lineThickness`, `glowBlur`) and re-run Steps 2–3. When it looks right:

```bash
git add Avora/Views/ScanReveal.swift
git commit -m "chore: tune scan-line reveal timing"
```

(If no tuning was needed, skip the commit — Task 1's commit stands.)

---

## Self-Review

**Spec coverage:**
- No-blur sharp source + looping scan line → Task 1 Step 1 (`startScanning`, `cardImage`), verified Task 2 Step 2. ✓
- Wipe reveal (result masked above the line) → Task 1 Step 1 (`.mask` + `revealResult`), verified Task 2 Step 3. ✓
- Thin accent line + soft glow → Task 1 Step 1 (`scanLine`). ✓
- Rename + same interface + single call-site change → Task 1 Steps 1–3. ✓
- Timing/params as named constants → Task 1 Step 1, Global Constraints. ✓
- Failed generation badge unchanged → Global Constraints; call site untouched except type name. ✓
- Result download failure fallback → Task 1 Step 1 (`revealResult` catch). ✓
- Multi-photo independence → verified Task 2 Step 4. ✓

**Placeholder scan:** No TBDs; all code shown in full; commands have expected output. ✓

**Type consistency:** `ScanReveal`, `scanY`, `revealProgress`, `resultImage`, `isRevealing`, `lineOpacity`, `startScanning()`, `revealResult()`, and the four constants are used consistently across steps and match the call site in Task 1 Step 2. ✓
