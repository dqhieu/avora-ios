import SwiftUI

/// A single community feed tile: the shared image with a caption row showing the
/// author's username and a tappable like affordance. Liking is optimistic — the
/// parent flips `likedByMe`/`likeCount` immediately and reverts on failure.
struct CommunityCard: View {
    let item: CommunityItem
    let onToggleLike: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            tile
            HStack {
                Text(item.username.map { "@\($0)" } ?? "@unknown")
                    .font(.avoraSubheadline)
                    .foregroundStyle(Color.avoraTextSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                likeButton
            }
            .padding(.horizontal, 2)
        }
        .padding(.bottom, Spacing.xs)
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(Color.avoraSurface)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let path = item.outputPath {
                    RemoteImage(path: path, contentMode: .fill)
                }
            }
            .clipShape(.rect(cornerRadius: Radius.md, style: .continuous))
    }

    private var likeButton: some View {
        Button(action: onToggleLike) {
            HStack(spacing: 3) {
                Image(systemName: item.likedByMe ? "heart.fill" : "heart")
                    .foregroundStyle(item.likedByMe ? Color.avoraAccent : Color.avoraTextSecondary)
                Text("\(item.likeCount)")
                    .font(.avoraSubheadline)
                    .foregroundStyle(Color.avoraTextSecondary)
                    .contentTransition(.numericText())
            }
        }
        .buttonStyle(.plain)
    }
}
