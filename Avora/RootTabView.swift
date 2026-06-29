import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            NavigationStack { StylesGridView() }
                .tabItem { Label("Create", systemImage: "wand.and.stars") }
            NavigationStack { CollectionView() }
                .tabItem { Label("Collection", systemImage: "square.grid.2x2") }
        }
    }
}
