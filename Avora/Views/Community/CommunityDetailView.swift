import SwiftUI

/// Full-screen view of one shared creation: large image, author, like toggle, and
/// a button that routes into CreateView reusing the creation's style (preset) or
/// its custom prompt. Like state is local and optimistic, seeded from the item.
struct CommunityDetailView: View {
    let item: CommunityItem
    @Environment(AppState.self) private var app
    @State private var style: Style?
    @State private var liked: Bool
    @State private var likeCount: Int

    init(item: CommunityItem) {
        self.item = item
        _liked = State(initialValue: item.likedByMe)
        _likeCount = State(initialValue: item.likeCount)
    }

    /// The shared output image, reused as the CreateView placeholder.
    private var placeholder: RemoteImageRef? {
        item.outputPath.map { RemoteImageRef(path: $0, source: .output) }
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: 4)
            if let path = item.outputPath {
                RemoteImage(path: path, contentMode: .fit)
            }
            HStack {
                Text(item.username.map { "@\($0)" } ?? "@unknown")
                    .font(.avoraHeadline)
                    .foregroundStyle(Color.avoraTextSecondary)
                Spacer()
                likeButton
            }
            .padding(.horizontal, Spacing.lg)
            Spacer(minLength: 4)
            createButton
        }
        .padding(.vertical, Spacing.lg)
        .frame(maxHeight: .infinity)
        .navigationTitle(style?.name ?? "Creation")
        .navigationBarTitleDisplayMode(.inline)
        .task { await resolveStyle() }
    }

    @ViewBuilder
    private var createButton: some View {
        if let style {
            NavigationLink(value: CreateRoute(style: style, placeholder: placeholder)) {
                Label("Create with this style", systemImage: "wand.and.stars")
            }
            .buttonStyle(AvoraPrimaryButtonStyle())
            .padding(.horizontal, Spacing.lg)
        } else if let prompt = item.customPrompt {
            NavigationLink(value: CreateRoute(style: .custom, placeholder: placeholder,
                                              customPrompt: prompt)) {
                Label("Create with this style", systemImage: "wand.and.stars")
            }
            .buttonStyle(AvoraPrimaryButtonStyle())
            .padding(.horizontal, Spacing.lg)
        }
    }

    private var likeButton: some View {
        Button {
            let wasLiked = liked
            liked.toggle()
            likeCount += wasLiked ? -1 : 1
            Task {
                do {
                    let count = wasLiked
                        ? try await AvoraAPI.shared.unlikeCreation(item.id)
                        : try await AvoraAPI.shared.likeCreation(item.id)
                    likeCount = count
                } catch {
                    liked = wasLiked
                    likeCount += wasLiked ? 1 : -1
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .foregroundStyle(liked ? Color.avoraAccent : Color.avoraTextSecondary)
                Text("\(likeCount)")
                    .foregroundStyle(Color.avoraTextSecondary)
                    .contentTransition(.numericText())
            }
            .font(.avoraHeadline)
        }
        .buttonStyle(.plain)
    }

    private func resolveStyle() async {
        guard let styleId = item.styleId else { return }
        try? await app.loadStyles()
        style = app.style(id: styleId)
    }
}
