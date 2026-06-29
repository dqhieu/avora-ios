import UIKit

/// Applies custom fonts to UIKit-backed chrome that SwiftUI modifiers cannot
/// reach — specifically navigation-bar titles, which ignore `.font()`.
enum AppearanceConfigurator {
    static func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()

        if let largeTitle = UIFont(name: "CormorantGaramond-SemiBold", size: 34) {
            appearance.largeTitleTextAttributes[.font] =
                UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: largeTitle)
        }
        if let inlineTitle = UIFont(name: "CormorantGaramond-SemiBold", size: 20) {
            appearance.titleTextAttributes[.font] =
                UIFontMetrics(forTextStyle: .headline).scaledFont(for: inlineTitle)
        }

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
}
