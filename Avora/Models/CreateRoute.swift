import Foundation

/// A remote image identified by its storage path plus the bucket it lives in,
/// so callers can hand it straight to `RemoteImage`/`ImageStore`.
struct RemoteImageRef: Hashable {
    let path: String
    let source: ImageStore.Source
}

/// Navigation payload for `CreateView`. Carries the chosen style and an optional
/// preview image to show as the placeholder before the user picks their own
/// photo — a style sample (from the Styles grid) or a prior creation (from the
/// Collection). When nil, `CreateView` falls back to the style's sample image.
struct CreateRoute: Hashable {
    let style: Style
    var placeholder: RemoteImageRef?
    var customPrompt: String? = nil
}
