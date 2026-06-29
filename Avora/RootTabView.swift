import SwiftUI

// Value-based route so each tab's NavigationStack path reflects the current
// push depth. Binding the tab bar's visibility to `path.isEmpty` then lets it
// animate out on push and back in on pop together with the navigation
// transition, instead of reappearing after the transition completes.
struct ImageRoute: Hashable { let path: String }

struct RootTabView: View {
    var body: some View {
        TabView {
            StylesTab()
                .tabItem { Label("Create", systemImage: "wand.and.stars") }
            CollectionTab()
                .tabItem { Label("Collection", systemImage: "square.grid.2x2") }
        }
    }
}

private struct StylesTab: View {
    @State private var path = NavigationPath()
    var body: some View {
        NavigationStack(path: $path) { StylesGridView() }
            .toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
    }
}

private struct CollectionTab: View {
    @State private var path = NavigationPath()
    var body: some View {
        NavigationStack(path: $path) { CollectionView() }
            .toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
    }
}
