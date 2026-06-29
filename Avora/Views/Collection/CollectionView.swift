import SwiftUI
import UIKit

struct CollectionView: View {
    @Environment(AppState.self) private var app
    @State private var items: [Generation] = []
    @State private var nextCursor: Date?
    @State private var loading = false
    @State private var showSettings = false
    private let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: Spacing.sm) {
                ForEach(items.filter { $0.status == .completed && $0.outputPath != nil }) { gen in
                    NavigationLink(value: gen) {
                        Thumb(path: gen.outputPath!)
                    }.buttonStyle(.plain)
                    .onAppear {
                        if gen.id == items.last?.id { Task { await loadMore() } }
                    }
                }
            }.padding(Spacing.sm)
        }
        .navigationTitle("Collection")
        .navigationDestination(for: Generation.self) { CreationDetailView(generation: $0) }
        .navigationDestination(for: CreateRoute.self) { CreateView(route: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView().environment(app) }
        }
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

private struct CreationDetailView: View {
    let generation: Generation
    @Environment(AppState.self) private var app
    @State private var style: Style?
    @State private var saved = false

    /// The creation's own output image, reused as the placeholder in `CreateView`.
    private var placeholder: RemoteImageRef? {
        generation.outputPath.map { RemoteImageRef(path: $0, source: .output) }
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            if let path = generation.outputPath {
                RemoteImage(path: path, contentMode: .fit)
            }
            controls
        }
        .padding(Spacing.lg)
        .frame(maxHeight: .infinity)
        .navigationTitle(style?.name ?? "Creation")
        .navigationBarTitleDisplayMode(.inline)
        .task { await resolveStyle() }
    }

    @ViewBuilder private var controls: some View {
        if let style {
            NavigationLink(value: CreateRoute(style: style, placeholder: placeholder)) {
                Label("Create with this style", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.avoraAccent)
        }
        Button { Task { await save() } } label: {
            Label(saved ? "Saved to Photos" : "Save to Photos",
                  systemImage: saved ? "checkmark" : "square.and.arrow.down")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Color.avoraAccent)
        .disabled(saved)
    }

    private func resolveStyle() async {
        guard let styleId = generation.styleId else { return }
        try? await app.loadStyles()
        style = app.style(id: styleId)
    }

    private func save() async {
        guard let path = generation.outputPath,
              let img = try? await ImageStore.shared.image(for: path) else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        saved = true
    }
}
