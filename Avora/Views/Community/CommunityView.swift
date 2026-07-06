import SwiftUI

struct CommunityView: View {
    @Environment(AppState.self) private var app
    @State private var items: [CommunityItem] = []
    @State private var sort: CommunitySort = .latest
    @State private var nextCursor: Date?      // latest
    @State private var nextOffset: Int?       // most liked
    @State private var loading = false
    @State private var reloadToken = 0
    @State private var hasLoaded = false
    @State private var showSettings = false
    @State private var showCredits = false
    private let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: Spacing.sm) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        CommunityCard(item: item) { toggleLike(item) }
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if item.id == items.last?.id { Task { await loadMore() } }
                    }
                }
            }
            .padding(Spacing.sm)
        }
        .navigationTitle("Community")
        .navigationDestination(for: CommunityItem.self) { CommunityDetailView(item: $0) }
        .navigationDestination(for: CreateRoute.self) { CreateView(route: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CreditsBalancePill(credits: app.profile?.totalCredits ?? -1) { showCredits = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(CommunitySort.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } label: {
                    ThiingIcon(name: sort == .mostLiked ? "ActionLike" : "ActionLatest", size: 32)
                        .accessibilityLabel("Sort")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { ThiingIcon(name: "ActionSettings", size: 32) }
                    .padding(.trailing, -4)
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
                    "No creations shared yet",
                    systemImage: "person.2",
                    description: Text("Shared creations from the community will appear here.")
                )
            }
        }
        .task(id: sort) {
            items = SnapshotStore.loadCommunity(sort) ?? []
            await refresh()
            hasLoaded = true
        }
        .refreshable { await refresh() }
    }

    private func toggleLike(_ item: CommunityItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let wasLiked = items[idx].likedByMe
        // optimistic flip
        items[idx].likedByMe.toggle()
        items[idx].likeCount += wasLiked ? -1 : 1
        let id = item.id
        Task {
            do {
                let count = wasLiked
                    ? try await AvoraAPI.shared.unlikeCreation(id)
                    : try await AvoraAPI.shared.likeCreation(id)
                if let i = items.firstIndex(where: { $0.id == id }) {
                    items[i].likeCount = count
                }
            } catch {
                if let i = items.firstIndex(where: { $0.id == id }) {
                    items[i].likedByMe = wasLiked
                    items[i].likeCount += wasLiked ? 1 : -1
                }
            }
        }
    }

    private func refresh() async {
        reloadToken += 1
        let token = reloadToken
        do {
            switch sort {
            case .latest:
                let (page, next) = try await AvoraAPI.shared.communityLatest(before: nil)
                guard token == reloadToken else { return }
                items = page
                nextCursor = next
                nextOffset = nil
            case .mostLiked:
                let (page, next) = try await AvoraAPI.shared.communityMostLiked(offset: 0)
                guard token == reloadToken else { return }
                items = page
                nextOffset = next
                nextCursor = nil
            }
            SnapshotStore.saveCommunity(sort, items)
        } catch {
            // keep whatever is on screen (snapshot or prior page)
        }
    }

    private func loadMore() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let token = reloadToken
        do {
            let page: [CommunityItem]
            switch sort {
            case .latest:
                guard let cursor = nextCursor else { return }
                let (p, next) = try await AvoraAPI.shared.communityLatest(before: cursor)
                guard token == reloadToken else { return }
                page = p; nextCursor = next
            case .mostLiked:
                guard let offset = nextOffset else { return }
                let (p, next) = try await AvoraAPI.shared.communityMostLiked(offset: offset)
                guard token == reloadToken else { return }
                page = p; nextOffset = next
            }
            let seen = Set(items.map(\.id))
            items += page.filter { !seen.contains($0.id) }
        } catch { }
    }
}
