import SwiftUI

struct StylesGridView: View {
    @Environment(AppState.self) private var app
    @State private var loadError = false
    @State private var showSettings = false
    @State private var showCredits = false
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(app.styles) { style in
                    NavigationLink(value: CreateRoute(style: style, placeholder: nil)) {
                        StyleCard(style: style)
                    }
                    .buttonStyle(.plain)
                }
            }.padding()

            if loadError && app.styles.isEmpty {
                ContentUnavailableView {
                    Label("Couldn’t load styles", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Retry") { Task { await load(force: true) } }
                }
                .padding(.top, 40)
            }
        }
        .navigationTitle("Styles")
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
        .navigationDestination(for: CreateRoute.self) { CreateView(route: $0) }
        .task { await load() }
        .refreshable { await load(force: true) }
    }

    private func load(force: Bool = false) async {
        loadError = false
        do {
            try await app.loadStyles(force: force)
            await app.refreshProfile()
        } catch {
            loadError = true
        }
    }
}

private struct StyleCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let style: Style
    var body: some View {
        VStack(alignment: .leading) {
            tile
            Text(style.name)
                .font(.avoraHeadline)
                .padding(.top, Spacing.xs)
        }
    }

    @ViewBuilder
    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
        let content = Color.clear
            .contentShape(.rect)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let path = style.sampleImagePath {
                    RemoteImage(path: path, source: .sample, contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .font(.avoraLargeTitle)
                        .foregroundStyle(Color.avoraTextTertiary)
                }
            }
            .clipShape(shape)
        Group {
            if #available(iOS 26.0, *) {
                content.glassEffect(in: shape)
            } else {
                content
                    .background(colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : .white, in: shape)
                    .overlay(shape.stroke(Color.secondary.opacity(0.5), lineWidth: 0.5))
            }
        }
        .overlay(alignment: .topTrailing) {
            if let badge = style.displayBadge {
                StyleBadge(text: badge)
                    .padding(8)
            }
        }
    }
}

private struct StyleBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.avoraCaption2)
            .foregroundStyle(Color.avoraTextPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.avoraSurface, in: Capsule())
            .overlay(Capsule().stroke(Color.avoraBorderHighlight, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview("Style cards — badge states") {
    let cols = [GridItem(.flexible()), GridItem(.flexible())]
    return LazyVGrid(columns: cols, spacing: 12) {
        StyleCard(style: Style(id: "1", name: "Vintage Film", sampleImagePath: nil, active: true, sortOrder: 0, badgeText: "Hot 🔥"))
        StyleCard(style: Style(id: "2", name: "Watercolor", sampleImagePath: nil, active: true, sortOrder: 1, badgeText: nil))
        StyleCard(style: Style(id: "3", name: "Trending One", sampleImagePath: nil, active: true, sortOrder: 2, badgeText: "Trending 🔥"))
        StyleCard(style: Style(id: "4", name: "Blank Badge", sampleImagePath: nil, active: true, sortOrder: 3, badgeText: "   "))
    }
    .padding()
}
#endif
