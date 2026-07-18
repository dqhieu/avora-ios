import SwiftUI
import PhotosUI

/// The Sticker Lab flow: turn a photo into a die-cut sticker entirely on-device.
/// Fully local — pick a photo, run `StickerProcessor`, view the transparent result
/// over a checkerboard (so the die-cut edge and white border are visible), Save to
/// Photos. Intentionally separate from the server-backed styles: no upload, no
/// credits, no Collection/Community.
struct StickerLabView: View {
    /// One picked photo and its independent sticker lifecycle.
    struct StickerItem: Identifiable {
        let id = UUID()
        let source: UIImage
        var result: UIImage?
        var status: Status = .processing
        var saved = false

        enum Status { case processing, done, failed }
    }

    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var items: [StickerItem] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 3)

    private var isProcessing: Bool { items.contains { $0.status == .processing } }
    private var hasUnsaved: Bool { items.contains { $0.status == .done && !$0.saved } }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            content
            if !items.isEmpty {
                controls
                    .padding(.horizontal, Spacing.lg)
            }
        }
        .padding(.vertical, Spacing.lg)
        .navigationTitle("Sticker Lab")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $pickerSelection, maxSelectionCount: 16, matching: .images) {
                        Text("Pick photos")
                    }
                    .disabled(isProcessing)
                }
            }
        }
        .onChange(of: pickerSelection) { _, selection in
            guard !selection.isEmpty else { return }
            Task { await load(selection) }
        }
    }

    @ViewBuilder private var content: some View {
        if items.isEmpty {
            emptyPrompt
        } else {
            grid
        }
    }

    private var emptyPrompt: some View {
        PhotosPicker(selection: $pickerSelection, maxSelectionCount: 16, matching: .images) {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.avoraLargeTitle)
                Text("Pick photos to make stickers")
                    .font(.avoraFootnote)
                    .foregroundStyle(Color.avoraTextTertiary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.sm) {
                ForEach($items) { $item in
                    StickerCell(item: item) { save(item) }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
        }
    }

    @ViewBuilder private var controls: some View {
        AvoraPrimaryButton { Haptics.tap(); saveAll() } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "square.and.arrow.down")
                Text("Save All to Photos")
            }
        }
        .disabled(isProcessing || !hasUnsaved)
    }

    // Implemented in later tasks.
    private func load(_ selection: [PhotosPickerItem]) async {}
    private func save(_ item: StickerItem) {}
    private func saveAll() {}
}

/// One grid cell: sticker over checkerboard when done, source + spinner while
/// processing, or an inline mark when no subject was found. Tapping a done cell saves it.
private struct StickerCell: View {
    let item: StickerLabView.StickerItem
    let onSave: () -> Void
    var body: some View {
        Image(uiImage: item.source)
            .resizable().scaledToFit()
    }
}

/// Light/dark checkerboard so a transparent PNG (and its white border) reads clearly.
private struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 16
            for row in 0..<Int((size.height / tile).rounded(.up)) {
                for col in 0..<Int((size.width / tile).rounded(.up)) {
                    let dark = (row + col) % 2 == 0
                    let rect = CGRect(x: CGFloat(col) * tile, y: CGFloat(row) * tile,
                                      width: tile, height: tile)
                    ctx.fill(Path(rect), with: .color(.gray.opacity(dark ? 0.28 : 0.12)))
                }
            }
        }
    }
}
