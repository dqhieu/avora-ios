import SwiftUI

struct StylesGridView: View {
    @Environment(AppState.self) private var app
    @State private var styles: [Style] = []
    @State private var loadError = false
    @State private var showSettings = false
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(styles) { style in
                    NavigationLink(value: style) { StyleCard(style: style) }
                        .buttonStyle(.plain)
                }
            }.padding()

            if loadError && styles.isEmpty {
                ContentUnavailableView {
                    Label("Couldn’t load styles", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Retry") { Task { await load() } }
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
        .refreshable { await load() }
    }

    private func load() async {
        loadError = false
        do {
            styles = try await AvoraAPI.shared.fetchStyles()
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
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(systemName: "photo")
                    .font(.avoraLargeTitle)
                    .foregroundStyle(Color.avoraTextTertiary)
            }
        if #available(iOS 26.0, *) {
            content.glassEffect(in: shape)
        } else {
            content
                .background(colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : .white, in: shape)
                .overlay(shape.stroke(Color.secondary.opacity(0.5), lineWidth: 0.5))
        }
    }
}
