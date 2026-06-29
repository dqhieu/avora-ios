import CoreText
import Foundation

/// Registers the app's bundled `.ttf` fonts with the process font manager at
/// launch. The app generates its Info.plist (`GENERATE_INFOPLIST_FILE = YES`),
/// and `UIAppFonts` is not a key Xcode synthesizes from build settings, so the
/// fonts are registered in code instead. Must run before any custom font is used.
enum FontRegistrar {
    static func registerBundledFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else {
            return
        }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
