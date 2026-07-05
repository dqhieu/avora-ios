import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            StylesTab()
                .tabItem { Label("Create", systemImage: "wand.and.stars") }
            CommunityTab()
                .tabItem { Label("Community", systemImage: "person.2") }
            CollectionTab()
                .tabItem { Label("Collection", systemImage: "square.grid.2x2") }
        }
    }
}

// Each tab owns its NavigationPath so the tab bar's visibility can be bound to
// push depth. Driving it from `path.isEmpty` lets the bar animate out on push
// and back in on pop together with the transition, instead of reappearing only
// after the back transition completes.
private struct StylesTab: View {
    @State private var path = NavigationPath()
    var body: some View {
        NavigationStack(path: $path) { StylesGridView() }
            .toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
    }
}

private struct CommunityTab: View {
    @State private var path = NavigationPath()
    var body: some View {
        NavigationStack(path: $path) { CommunityView() }
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
