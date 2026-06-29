import SwiftUI

// TODO: Task 8 replaces this placeholder with the real creation flow.
struct CreateView: View {
    let style: Style

    var body: some View {
        Text(style.name)
            .navigationTitle(style.name)
            .navigationBarTitleDisplayMode(.inline)
    }
}
