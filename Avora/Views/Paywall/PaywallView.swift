import SwiftUI

// Placeholder — Task 10 replaces this with the real paywall implementation.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Paywall")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }
}
