import SwiftUI
import UIKit

struct RootTabView: View {
    @State private var selection = 0
    var body: some View {
        TabView(selection: $selection) {
            StylesTab()
                .tabItem { Label { Text("Create") } icon: { Image(uiImage: TabBarIcon.create) } }
                .tag(0)
            CommunityTab()
                .tabItem { Label { Text("Community") } icon: { Image(uiImage: TabBarIcon.community) } }
                .tag(1)
            CollectionTab()
                .tabItem { Label { Text("Collection") } icon: { Image(uiImage: TabBarIcon.collection) } }
                .tag(2)
        }
        .onChange(of: selection) { Haptics.selection() }
    }
}

/// The full-color 3D tab icons ship at 256px so they stay crisp on other
/// surfaces. Native `.tabItem` renders an asset at its logical point size, so a
/// 256px source would show at 256pt. These downscale the source to tab-bar size
/// once and render `.alwaysOriginal` to preserve color.
private enum TabBarIcon {
    static let create = make("TabCreate")
    static let community = make("TabCommunity")
    static let collection = make("TabCollection")

    private static func make(_ name: String, pointSize: CGFloat = 32) -> UIImage {
        let base = UIImage(named: name) ?? UIImage()
        let size = CGSize(width: pointSize, height: pointSize)
        return UIGraphicsImageRenderer(size: size).image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
        }.withRenderingMode(.alwaysOriginal)
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
