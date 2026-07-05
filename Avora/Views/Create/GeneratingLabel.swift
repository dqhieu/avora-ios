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
            .animation(.snappy, value: index)
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
