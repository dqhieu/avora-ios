import SwiftUI
import UIKit

struct CollectionView: View {
    @Environment(AppState.self) private var app
    @State private var items: [Generation] = []
    @State private var nextCursor: Date?
    @State private var loading = false
    @State private var reloadToken = 0
    @State private var hasLoaded = false
    @State private var showSettings = false
    @State private var showCredits = false
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
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let credits = app.profile?.totalCredits {
                    CreditsBalancePill(credits: credits) { showCredits = true }
                }
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView().environment(app) }
        }
        .sheet(isPresented: $showCredits) {
            NavigationStack { CreditsView().environment(app) }
        }
        .overlay {
            if items.isEmpty && hasLoaded {
                ContentUnavailableView(
                    "No creations yet",
                    systemImage: "square.grid.2x2",
                    description: Text("Generated images will appear here.")
                )
            }
        }
        .task {
            // Paint instantly from the last snapshot, then reconcile once from
            // the network. hasLoaded is flipped after the refresh so the empty
            // state can't flash during a first-ever load with no snapshot.
            if items.isEmpty { items = SnapshotStore.loadCollection() ?? [] }
            guard !hasLoaded else { return }
            await refresh()
            hasLoaded = true
        }
        .refreshable { await refresh() }
    }

    private func loadMore() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let token = reloadToken
        if let (page, next) = try? await AvoraAPI.shared.listGenerations(cursor: nextCursor) {
            // A refresh landed while this page was in flight — drop the stale page
            // rather than appending it onto the freshly loaded collection.
            guard token == reloadToken else { return }
            let seen = Set(items.map(\.id))
            items += page.filter { !seen.contains($0.id) }
            nextCursor = next
        }
    }

    // Load the first page into place without blanking the list first, so a failed
    // or in-flight-superseded refresh can't leave the collection stuck empty.
    private func refresh() async {
        reloadToken += 1
        if let (page, next) = try? await AvoraAPI.shared.listGenerations(cursor: nil) {
            items = page
            nextCursor = next
            SnapshotStore.saveCollection(page)
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
