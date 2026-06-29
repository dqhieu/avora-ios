import SwiftUI

struct StylesGridView: View {
    @Environment(AppState.self) private var app
    @State private var styles: [Style] = []
    @State private var loadError = false
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            if let p = app.profile {
                HStack {
                    Label("\(p.totalCredits) credits", systemImage: "sparkles")
                    Spacer()
                    Text("\(p.totalGenerations) generations").foregroundStyle(.secondary)
                }.padding(.horizontal).font(.avoraSubheadline.monospacedDigit())
            }
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
        .navigationTitle("Avora")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
            }
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
    let style: Style
    var body: some View {
        VStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 14)
                .fill(.secondary.opacity(0.15))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: "photo").font(.avoraLargeTitle).foregroundStyle(.secondary)
                }
            Text(style.name).font(.avoraHeadline).padding(.top, 4)
        }
    }
}
