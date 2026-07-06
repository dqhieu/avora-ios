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
    @State private var more: [CommunityItem] = []

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
        ScrollView {
            VStack(spacing: Spacing.lg) {
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
                createButton
                moreSection
            }
            .padding(.vertical, Spacing.lg)
        }
        .navigationTitle(style?.name ?? "Creation")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await resolveStyle()
            await loadMore()
        }
    }

    @ViewBuilder
    private var createButton: some View {
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
        } else if let prompt = item.customPrompt {
            NavigationLink(value: CreateRoute(style: .custom, placeholder: placeholder,
                                              customPrompt: prompt)) {
                HStack(spacing: Spacing.xs) {
                    ThiingIcon(name: "ActionGenerate", size: 22)
                    Text("Create with this style")
                }
            }
            .buttonStyle(AvoraPrimaryButtonStyle())
            .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
            .padding(.horizontal, Spacing.lg)
        }
    }

    private var likeButton: some View {
        Button {
            Haptics.selection()
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
                Text("\(likeCount)")
                    .foregroundStyle(Color.avoraTextSecondary)
                    .contentTransition(.numericText())
                ThiingIcon(name: "ActionLike", size: 20, active: liked)
                    .animation(.default, value: liked)
            }
            .font(.avoraHeadline)
        }
        .buttonStyle(.plain)
    }

    private let moreColumns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    @ViewBuilder
    private var moreSection: some View {
        if !more.isEmpty, let username = item.username {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("More from @\(username)")
                    .font(.avoraHeadline)
                    .foregroundStyle(Color.avoraTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: moreColumns, spacing: Spacing.sm) {
                    ForEach(more) { other in
                        NavigationLink(value: other) { moreThumbnail(other) }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
        }
    }

    private func moreThumbnail(_ other: CommunityItem) -> some View {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(Color.avoraSurface)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let path = other.outputPath {
                    RemoteImage(path: path, contentMode: .fill)
                }
            }
            .clipShape(.rect(cornerRadius: Radius.md, style: .continuous))
    }

    private func loadMore() async {
        guard let username = item.username else { return }
        more = (try? await AvoraAPI.shared.communityByUser(username, excluding: item.id)) ?? []
    }

    private func resolveStyle() async {
        guard let styleId = item.styleId else { return }
        try? await app.loadStyles()
        style = app.style(id: styleId)
    }
}
