# Cycling Generation Loading Messages — Design

**Date:** 2026-07-03
**Status:** Approved, ready for planning

## Problem

During generation in `CreateView`, the primary button shows a spinner and a static
`"Generating…"` label. A batch can run 1–2 minutes, so the static text feels lifeless.
We want playful, rotating status messages — like the ChatGPT app — to make the wait
feel alive and reassuring.

## Scope

- Replace the static `"Generating…"` text in the Generate button with a small
  self-contained subview that cycles through themed messages.
- No change to the underlying generation, polling, or `FocusReveal` blur animation.
- One shared message for the whole batch (the button is shared across all cards).

Out of scope: per-card messages, progress percentages, phase-accurate mapping.

## Behavior

- **Cadence:** advance one message every **5 seconds**.
- **Active window:** cycling runs only while the button's `isWorking` is true — this
  covers upload + submit + polling, i.e. the whole batch.
- **Two-part sequence:**
  - **Main sequence** plays once, in order (indices 0–8).
  - **Tail pool** (indices 9–13) loops among itself every 5s until the job finishes.
    It never returns to the main sequence. Every tail line reads as "nearly done,"
    so looping feels natural rather than restarted.
- **Reset:** the index resets to the first message each time a new generation begins
  (including "Generate again").
- **Transition:** gentle cross-fade between messages (not an instant snap). This is a
  text change, not motion, so Reduce Motion needs no special handling.
- The spinner stays exactly as-is; only the label text changes.

## Messages

Main sequence (plays once, in order):

1. Reading your photo…
2. Studying the details…
3. Understanding the style…
4. Sketching it out…
5. Setting the scene…
6. Applying the style…
7. Blending the colors…
8. Refining the details…
9. Polishing the look…

Tail pool (loops until done):

10. Adding final touches…
11. One last tweak…
12. Almost there…
13. Just about ready…
14. Putting on the finishing touches…

At 5s/message the main sequence spans ~45s, after which the tail pool loops
indefinitely so there is always fresh, "almost done" text regardless of job length.

## Implementation

A new self-contained SwiftUI subview — `GeneratingLabel` — owns the timer and the
current index.

- Input: `isActive: Bool`.
- Owns a repeating 5s ticker (a cancellable `Task` sleeping 5s, or an equivalent
  timer) that advances the index while active.
- Index logic:
  - starts at 0 on activation,
  - increments through the main sequence,
  - once it reaches the tail region, wraps within the tail pool only
    (`nextIndex = mainCount + ((index + 1 - mainCount) % tailCount)`).
- Renders the current message as `Text`, styled to match the existing button label,
  with a cross-fade on change (e.g. `.animation` on a transition or `.id`-keyed
  `.transition(.opacity)`).
- Stops/cancels its ticker when `isActive` becomes false and resets the index so the
  next generation starts clean.

### Integration point

In `CreateView.swift`, the `isWorking` branch of the Generate button label
(around the current `Text("Generating…")`) swaps to:

```swift
HStack(spacing: Spacing.sm) {
    ProgressView().tint(Color.avoraOnAccent)
    GeneratingLabel(isActive: isWorking)
}
```

CreateView is otherwise untouched — the timer/index logic stays isolated in the
subview, keeping it easy to reason about and unit-testable (the index-advancement
function can be a pure `static` helper).

## Success Criteria

- Starting a generation shows "Reading your photo…" then advances every ~5s.
- After the main sequence, tail messages keep changing (never freezing on one line,
  never jumping back to "Reading your photo…").
- Messages cross-fade rather than snap.
- Starting a new generation ("Generate again") restarts from the first message.
- When generation finishes, the button returns to its Save all / Generate again state
  with no lingering timer.
