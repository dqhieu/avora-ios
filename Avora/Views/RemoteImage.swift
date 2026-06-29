import SwiftUI

/// Loads an output image through `ImageStore`, keyed by its storage path.
/// Drop-in replacement for `AsyncImage(url:)` that survives signed-URL churn.
struct RemoteImage: View {
    let path: String
    var contentMode: ContentMode = .fit

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if failed {
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(Color.avoraTextSecondary)
                }
            } else {
                ProgressView()
            }
        }
        .task(id: path) { await load() }
    }

    private func load() async {
        failed = false
        do {
            image = try await ImageStore.shared.image(for: path)
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}
