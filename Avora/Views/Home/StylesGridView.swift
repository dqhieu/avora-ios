import SwiftUI

struct StylesGridView: View {
    @Environment(AppState.self) private var app
    @State private var loadError = false
    @State private var showSettings = false
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(app.styles) { style in
                    NavigationLink(value: style) { StyleCard(style: style) }
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
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView().environment(app) }
        }
        .navigationDestination(for: Style.self) { CreateView(style: $0) }
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
        if #available(iOS 26.0, *) {
            content.glassEffect(in: shape)
        } else {
            content
                .background(colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : .white, in: shape)
                .overlay(shape.stroke(Color.secondary.opacity(0.5), lineWidth: 0.5))
        }
    }
}
