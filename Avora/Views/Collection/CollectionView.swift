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
                    .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                    .onAppear {
                        if gen.id == items.last?.id { Task { await loadMore() } }
                    }
                }
            }.padding(Spacing.sm)
        }
        .avoraSoftScrollEdge()
        .navigationTitle("Collection")
        .navigationDestination(for: Generation.self) { gen in
            CreationDetailView(generation: gen, onDelete: { deletedId in
                items.removeAll { $0.id == deletedId }
                SnapshotStore.saveCollection(items)
            })
        }
        .navigationDestination(for: CreateRoute.self) { CreateView(route: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CreditsBalancePill(credits: app.profile?.totalCredits ?? -1) { Haptics.tap(); showCredits = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Haptics.tap(); showSettings = true } label: { ThiingIcon(name: "ActionSettings", size: 32) }
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
                    ThiingIcon(name: "ActionShare", size: 20)
                        .padding(4)
                        .avoraGlass(in: Circle())
                        .padding(4)
                }
            }
    }
}

private struct CreationDetailView: View {
    let generation: Generation
    let onDelete: (UUID) -> Void
    init(generation: Generation, onDelete: @escaping (UUID) -> Void) {
        self.generation = generation
        self.onDelete = onDelete
        _shared = State(initialValue: generation.sharedAt != nil)
    }
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var style: Style?
    @State private var shared: Bool
    @State private var showShareConfirm = false
    @State private var sharing = false
    @State private var showDeleteConfirm = false
    @State private var deleting = false

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
                    HStack(spacing: Spacing.xs) {
                        ThiingIcon(name: "ActionGenerate", size: 22)
                        Text("Create with this style")
                    }
                }
                .buttonStyle(AvoraPrimaryButtonStyle())
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                .padding(.horizontal, Spacing.lg)
            } else if let prompt = generation.customPrompt {
                NavigationLink(value: CreateRoute(style: .custom, placeholder: placeholder, customPrompt: prompt)) {
                    HStack(spacing: Spacing.xs) {
                        ThiingIcon(name: "ActionGenerate", size: 22)
                        Text("Create with this prompt")
                    }
                }
                .buttonStyle(AvoraPrimaryButtonStyle())
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                .padding(.horizontal, Spacing.lg)
            }
        }
        .padding(.vertical, Spacing.lg)
        .frame(maxHeight: .infinity)
        .navigationTitle(style?.name ?? "Creation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Haptics.tap(); Task { await save() } } label: {
                    ThiingIcon(name: "ActionSave", size: 28)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if shared {
                        Haptics.warning()
                        Task { await setShared(false) }
                    } else if generation.customPrompt != nil {
                        Haptics.tap()
                        showShareConfirm = true      // warn: prompt becomes public
                    } else {
                        Haptics.tap()
                        Task { await setShared(true) }
                    }
                } label: {
                    ThiingIcon(name: "ActionShare", size: 28, active: shared)
                }
                .disabled(sharing)
                .confirmationDialog(
                  "Share to Community?", isPresented: $showShareConfirm, titleVisibility: .visible
                ) {
                  Button("Share") { Haptics.tap(); Task { await setShared(true) } }
                  Button("Cancel", role: .cancel) { }
                } message: {
                  Text("Your prompt will be visible to others so they can create with it.")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.warning()
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .disabled(deleting)
                .confirmationDialog(
                  "Delete creation?", isPresented: $showDeleteConfirm, titleVisibility: .visible
                ) {
                  Button("Delete", role: .destructive) { Haptics.warning(); Task { await delete() } }
                  Button("Cancel", role: .cancel) { }
                } message: {
                  Text("This permanently removes it. This can't be undone.")
                }
            }
        }
        .task { await resolveStyle() }
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
        ToastWindowManager.shared.show(title: "Saved to Photos")
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
            ToastWindowManager.shared.show(
                title: newValue ? "Shared to Community" : "Removed from Community"
            )
        } catch { }
    }

    private func delete() async {
        deleting = true
        defer { deleting = false }
        do {
            try await AvoraAPI.shared.deleteCreation(generation.id)
            if generation.sharedAt != nil { SnapshotStore.clearCommunity() }
            onDelete(generation.id)
            dismiss()
            ToastWindowManager.shared.show(title: "Deleted")
        } catch {
            ToastWindowManager.shared.show(title: "Couldn't delete")
        }
    }
}
