# Generation Loading Messages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the static "Generating…" text in the CreateView Generate button with a cycling, Avora-themed status message that keeps the wait feeling alive.

**Architecture:** A new self-contained SwiftUI subview `GeneratingLabel` owns a 5-second ticker and a message index. It plays a main sequence once, then loops a "nearly done" tail pool until the job finishes. The index math is a pure `static` function so it is trivial to reason about. CreateView changes by exactly one line — swapping `Text("Generating…")` for `GeneratingLabel(isActive:)`.

**Tech Stack:** SwiftUI, Swift concurrency (`Task`/`.task(id:)`). iOS app target `Avora`.

## Global Constraints

- **No test target exists.** This is a single-app-target project with zero tests. Verification is: (a) a successful build, and (b) the SwiftUI `#Preview` / simulator. Do not scaffold an XCTest target for this cosmetic feature. The one genuinely-testable piece — the index-advancement math — is a pure function verified against an explicit expected-sequence table in Task 1.
- **File placement:** the project uses an Xcode *synchronized root group* (`PBXFileSystemSynchronizedRootGroup`). Any new `.swift` file saved under `Avora/` is auto-added to the target — **do not edit `Avora.xcodeproj/project.pbxproj`.**
- **Styling:** the Generate button label inherits `.font(.avoraButton)` and `.foregroundStyle(Color.avoraOnAccent)` from `AvoraPrimaryButtonStyle`. `GeneratingLabel` must NOT set its own font or color — it inherits, exactly as today's `Text("Generating…")` does.
- **Cadence:** advance every **5 seconds** (`5_000_000_000` nanoseconds).
- **Message copy:** use the two lists verbatim from the spec (`docs/superpowers/specs/2026-07-03-generation-loading-messages-design.md`), including the trailing `…` (ellipsis character U+2026, not three dots) to match the existing `"Generating…"`.
- **Build command:** `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build` (or the XcodeBuildMCP `build_sim` equivalent). A clean build with no errors is the pass condition.

---

### Task 1: `GeneratingLabel` component

**Files:**
- Create: `Avora/Views/Create/GeneratingLabel.swift`

**Interfaces:**
- Consumes: nothing (uses only SwiftUI + design tokens `Font.avoraButton` / `Color.avoraOnAccent` already in the codebase, inherited implicitly).
- Produces:
  - `struct GeneratingLabel: View { let isActive: Bool }` — the view CreateView will embed.
  - `static func nextIndex(after index: Int) -> Int` — pure index-advancement helper used internally and eyeball-verified below.

**Index behavior (the correctness contract):** with 9 main messages (indices 0–8) and 5 tail messages (indices 9–13), advancement must produce:

| after | → next | message shown |
|-------|--------|---------------|
| 0 | 1 | Studying the details… |
| 7 | 8 | Polishing the look… |
| 8 | 9 | Adding final touches… (first tail) |
| 12 | 13 | Putting on the finishing touches… (last tail) |
| 13 | 9 | Adding final touches… (wraps within tail only) |
| 9 | 10 | One last tweak… |

Key invariant: once past index 8, the index NEVER returns below 9 (never replays the main sequence).

- [ ] **Step 1: Create the file with the full component**

Create `Avora/Views/Create/GeneratingLabel.swift`:

```swift
import SwiftUI

/// Rotating status text shown inside the Generate button while a batch runs.
/// Plays a main sequence once, then loops a "nearly done" tail pool until the
/// job finishes, so there is always fresh text no matter how long generation
/// takes. Font and color are inherited from the enclosing button style.
struct GeneratingLabel: View {
    /// True while a generation is in flight. The ticker runs only while active,
    /// and the message resets to the start each time it becomes active.
    let isActive: Bool

    // Plays once, in order.
    static let mainMessages: [String] = [
        "Reading your photo…",
        "Studying the details…",
        "Understanding the style…",
        "Sketching it out…",
        "Setting the scene…",
        "Applying the style…",
        "Blending the colors…",
        "Refining the details…",
        "Polishing the look…",
    ]

    // Loops among itself until generation finishes. Every line reads as "nearly done".
    static let tailMessages: [String] = [
        "Adding final touches…",
        "One last tweak…",
        "Almost there…",
        "Just about ready…",
        "Putting on the finishing touches…",
    ]

    private static let messages = mainMessages + tailMessages
    private static let intervalNanos: UInt64 = 5_000_000_000  // 5s

    @State private var index = 0

    var body: some View {
        Text(Self.messages[index])
            .contentTransition(.opacity)
            .task(id: isActive) { await run() }
    }

    private func run() async {
        index = 0
        guard isActive else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.intervalNanos)
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                index = Self.nextIndex(after: index)
            }
        }
    }

    /// Advance through the main sequence once, then wrap within the tail pool only.
    static func nextIndex(after index: Int) -> Int {
        let next = index + 1
        if next < messages.count { return next }
        // Past the end: wrap inside the tail region, never back to the main sequence.
        let tailOffset = (next - mainMessages.count) % tailMessages.count
        return mainMessages.count + tailOffset
    }
}

#if DEBUG
#Preview("GeneratingLabel") {
    GeneratingLabel(isActive: true)
        .font(.avoraButton)
        .foregroundStyle(Color.avoraOnAccent)
        .padding()
        .background(Color.avoraAccent)
}
#endif
```

- [ ] **Step 2: Eyeball-verify the `nextIndex` math against the table**

Read the function against the correctness table above. Confirm all six rows hold — in particular `nextIndex(after: 13) == 9` (wrap stays in the tail) and `nextIndex(after: 8) == 9` (main → first tail). Since `messages.count == 14`, `mainMessages.count == 9`, `tailMessages.count == 5`:
- `nextIndex(after: 13)`: `next = 14`, not `< 14` → `tailOffset = (14 - 9) % 5 = 0` → `9`. ✓
- `nextIndex(after: 8)`: `next = 9`, `9 < 14` → `9`. ✓

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: **BUILD SUCCEEDED**, no errors or warnings referencing `GeneratingLabel.swift`.

- [ ] **Step 4: Preview-verify cycling (optional visual)**

Open `GeneratingLabel.swift` in Xcode and run the `#Preview`. It should show "Reading your photo…" and advance to "Studying the details…" after ~5s with a soft cross-fade. (Watching all 14 takes ~70s; observing the first advance is sufficient.)

- [ ] **Step 5: Commit**

```bash
git add Avora/Views/Create/GeneratingLabel.swift
git commit -m "feat: add cycling GeneratingLabel status view"
```

---

### Task 2: Wire `GeneratingLabel` into the Generate button

**Files:**
- Modify: `Avora/Views/Create/CreateView.swift` (the `isWorking` branch of the button label, currently around lines 184–188)

**Interfaces:**
- Consumes: `GeneratingLabel(isActive:)` from Task 1, and the existing `isWorking` computed property on `CreateView`.
- Produces: nothing new.

**Context:** the current code in the `controls` view's `else` branch reads:

```swift
AvoraPrimaryButton { Task { await generate() } } label: {
    if isWorking {
        HStack(spacing: Spacing.sm) {
            ProgressView().tint(Color.avoraOnAccent)
            Text("Generating…")
        }
    } else {
        VStack(spacing: Spacing.xs) {
            Label("Generate", systemImage: "wand.and.stars")
            Text("\(sourceImages.count * app.config.generationCost) credits")
                .font(.avoraCaption)
                .opacity(0.85)
        }
    }
}
```

Because this branch only mounts while `isWorking == true`, `GeneratingLabel` is freshly created each time generation starts — which is exactly what resets the message to the first line for every new generation (including "Generate again"). When generation finishes, `controls` swaps to its `poller.allTerminal` branch, the label is torn down, and the ticker `Task` is cancelled automatically.

- [ ] **Step 1: Replace the static text with the cycling label**

In `Avora/Views/Create/CreateView.swift`, change the single line inside the `isWorking` `HStack`:

Replace:
```swift
                    Text("Generating…")
```
With:
```swift
                    GeneratingLabel(isActive: isWorking)
```

Leave the `ProgressView().tint(Color.avoraOnAccent)` line and everything else unchanged.

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project Avora.xcodeproj -scheme Avora -destination 'generic/platform=iOS Simulator' build`
Expected: **BUILD SUCCEEDED**.

- [ ] **Step 3: Run in the simulator and verify live behavior**

Launch the app in the simulator, open a style → pick a photo → tap Generate. Expected:
- The button immediately shows the spinner + "Reading your photo…".
- The text advances every ~5s with a cross-fade.
- On a long job it keeps changing (never freezes, never jumps back to "Reading your photo…").
- When generation finishes, the button switches to the Save all / Generate again controls with no leftover animation.

(If a live backend generation isn't available in the environment, rely on the Task 1 preview plus a clean build; note this deviation in the completion report.)

- [ ] **Step 4: Commit**

```bash
git add Avora/Views/Create/CreateView.swift
git commit -m "feat: show cycling status messages in Generate button"
```

---

## Self-Review

**Spec coverage:**
- Placement in Generate button → Task 2. ✓
- Avora-themed 14-message list (9 main + 5 tail) → Task 1 `mainMessages`/`tailMessages`, copied verbatim from spec. ✓
- 5s cadence → `intervalNanos` in Task 1. ✓
- Main plays once, tail loops → `nextIndex` pure function + correctness table. ✓
- Reset on each new generation → covered by the view being remounted when `isWorking` flips true (Task 2 context). ✓
- Cross-fade, not snap → `.contentTransition(.opacity)` + `withAnimation(.easeInOut(duration: 0.4))`. ✓
- Spinner unchanged, one shared label → Task 2 leaves `ProgressView` intact, single label in shared button. ✓
- Timer stops when done → `.task(id:)` cancellation on teardown (Task 2 context). ✓

**Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to Task N". All code shown in full. ✓

**Type consistency:** `GeneratingLabel(isActive: Bool)`, `nextIndex(after:) -> Int`, `mainMessages`/`tailMessages`/`messages` used consistently across both tasks. Counts (9 main, 5 tail, 14 total) match every reference. ✓
