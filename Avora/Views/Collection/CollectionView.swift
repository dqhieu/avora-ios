import SwiftUI

struct CollectionView: View {
    @State private var items: [Generation] = []
    @State private var nextCursor: Date?
    @State private var loading = false
    private let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: Spacing.sm) {
                ForEach(items.filter { $0.status == .completed && $0.outputPath != nil }) { gen in
                    NavigationLink { FullImageView(path: gen.outputPath!) } label: {
                        Thumb(path: gen.outputPath!)
                    }.buttonStyle(.plain)
                    .onAppear {
                        if gen.id == items.last?.id { Task { await loadMore() } }
                    }
                }
            }.padding(Spacing.sm)
        }
        .navigationTitle("Collection")
        .overlay {
            if items.isEmpty && !loading {
                ContentUnavailableView(
                    "No creations yet",
                    systemImage: "square.grid.2x2",
                    description: Text("Generated images will appear here.")
                )
            }
        }
        .task { if items.isEmpty { await loadMore() } }
        .refreshable { items = []; nextCursor = nil; await loadMore() }
    }

    private func loadMore() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        if let (page, next) = try? await AvoraAPI.shared.listGenerations(cursor: nextCursor) {
            let seen = Set(items.map(\.id))
            items += page.filter { !seen.contains($0.id) }
            nextCursor = next
        }
    }
}

private struct Thumb: View {
    let path: String
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(Color.avoraSurface)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                RemoteImage(path: path, contentMode: .fill)
            }
            .clipShape(.rect(cornerRadius: Radius.sm, style: .continuous))
    }
}

private struct FullImageView: View {
    let path: String
    var body: some View {
        RemoteImage(path: path, contentMode: .fit)
            .navigationTitle("Creation")
            .navigationBarTitleDisplayMode(.inline)
    }
}
