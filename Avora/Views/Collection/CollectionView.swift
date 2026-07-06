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
                        Thumb(path: gen.outputPath!, shared: gen.sharedAt != nil)
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
            ToolbarItem(placement: .topBarLeading) {
                CreditsBalancePill(credits: app.profile?.totalCredits ?? -1) { showCredits = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { ThiingIcon(name: "ActionSettings", size: 32) }
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
    var shared: Bool = false
    var body: some View {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(Color.avoraSurface)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                RemoteImage(path: path, contentMode: .fill)
            }
            .clipShape(.rect(cornerRadius: Radius.sm, style: .continuous))
            .overlay(alignment: .topLeading) {
                if shared {
                    Label("Shared", systemImage: "person.2.fill")
                        .font(.avoraCaption2)
                        .labelStyle(.iconOnly)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                }
            }
    }
}

private struct CreationDetailView: View {
    let generation: Generation
    init(generation: Generation) {
        self.generation = generation
        _shared = State(initialValue: generation.sharedAt != nil)
    }
    @Environment(AppState.self) private var app
    @State private var style: Style?
    @State private var saved = false
    @State private var shared: Bool
    @State private var showShareConfirm = false
    @State private var sharing = false

    /// The creation's own output image, reused as the placeholder in `CreateView`.
    private var placeholder: RemoteImageRef? {
        generation.outputPath.map { RemoteImageRef(path: $0, source: .output) }
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: 4)
            if let path = generation.outputPath {
                RemoteImage(path: path, contentMode: .fit)
            }
            Spacer(minLength: 4)
            if let style {
                NavigationLink(value: CreateRoute(style: style, placeholder: placeholder)) {
                    Label("Create with this style", systemImage: "wand.and.stars")
                }
                .buttonStyle(AvoraPrimaryButtonStyle())
                .padding(.horizontal, Spacing.lg)
            } else if let prompt = generation.customPrompt {
                NavigationLink(value: CreateRoute(style: .custom, placeholder: placeholder, customPrompt: prompt)) {
                    Label("Create with this prompt", systemImage: "wand.and.stars")
                }
                .buttonStyle(AvoraPrimaryButtonStyle())
                .padding(.horizontal, Spacing.lg)
            }
        }
        .padding(.vertical, Spacing.lg)
        .frame(maxHeight: .infinity)
        .navigationTitle(style?.name ?? "Creation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await save() } } label: {
                    ThiingIcon(name: "ActionSave", size: 28, active: !saved)
                }
                .disabled(saved)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if shared {
                        Task { await setShared(false) }
                    } else if generation.customPrompt != nil {
                        showShareConfirm = true      // warn: prompt becomes public
                    } else {
                        Task { await setShared(true) }
                    }
                } label: {
                    ThiingIcon(name: "ActionShare", size: 28, active: shared)
                }
                .disabled(sharing)
            }
        }
        .task { await resolveStyle() }
        .confirmationDialog(
            "Share to Community?", isPresented: $showShareConfirm, titleVisibility: .visible
        ) {
            Button("Share") { Task { await setShared(true) } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your prompt will be visible to others so they can create with it.")
        }
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

    private func setShared(_ newValue: Bool) async {
        sharing = true
        defer { sharing = false }
        do {
            if newValue {
                try await AvoraAPI.shared.shareCreation(generation.id)
            } else {
                try await AvoraAPI.shared.unshareCreation(generation.id)
            }
            shared = newValue
            SnapshotStore.clearCommunity()   // force the feed to refetch on next view
        } catch { }
    }
}
