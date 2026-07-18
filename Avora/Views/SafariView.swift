import SwiftUI
import SafariServices

/// Identifiable URL wrapper so legal pages can drive `.sheet(item:)`.
struct LegalPage: Identifiable {
    let id = UUID()
    let url: URL
}

/// In-app Safari for presenting web content (privacy policy, terms of service).
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
