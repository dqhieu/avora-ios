import SwiftUI
import PhotosUI

/// The Sticker Lab flow: turn a photo into a die-cut sticker entirely on-device.
/// Fully local — pick a photo, run `StickerProcessor`, view the transparent result
/// over a checkerboard (so the die-cut edge and white border are visible), Save to
/// Photos. Intentionally separate from the server-backed styles: no upload, no
/// credits, no Collection/Community.
struct StickerLabView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var source: UIImage?
    @State private var result: UIImage?
    @State private var isProcessing = false
    @State private var failed = false
    @State private var saved = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            preview
            controls
                .padding(.horizontal, Spacing.lg)
        }
        .padding(.vertical, Spacing.lg)
        .navigationTitle("Sticker Lab")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if source != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $pickerItem, matching: .images) { Text("Pick photo") }
                        .disabled(isProcessing)
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
    }

    @ViewBuilder private var preview: some View {
        ZStack {
            if let result {
                Checkerboard()
                Image(uiImage: result)
                    .resizable().scaledToFit()
            } else if let source {
                Image(uiImage: source)
                    .resizable().scaledToFit()
                    .opacity(isProcessing ? 0.4 : 1)
                    .overlay { if isProcessing { ProgressView() } }
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "sparkles")
                            .font(.avoraLargeTitle)
                        Text("Pick a photo to make a sticker")
                            .font(.avoraFootnote)
                            .foregroundStyle(Color.avoraTextTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(alignment: .bottom) {
            if failed {
                Text("Couldn’t find a subject. Try another photo.")
                    .font(.avoraFootnote)
                    .foregroundStyle(Color.avoraError)
                    .padding(Spacing.sm)
            }
        }
    }

    @ViewBuilder private var controls: some View {
        AvoraPrimaryButton { Haptics.tap(); save() } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: saved ? "checkmark" : "square.and.arrow.down")
                Text(saved ? "Saved" : "Save to Photos")
            }
        }
        .disabled(result == nil || saved)
    }

    private func load(_ item: PhotosPickerItem) async {
        result = nil
        failed = false
        saved = false
        guard let data = try? await item.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else { return }
        source = img
        isProcessing = true
        let sticker = await StickerProcessor.makeSticker(from: img)
        isProcessing = false
        if let sticker {
            result = sticker
            Haptics.success()
        } else {
            failed = true
            Haptics.error()
        }
    }

    private func save() {
        guard let result else { return }
        UIImageWriteToSavedPhotosAlbum(result, nil, nil, nil)
        saved = true
        ToastWindowManager.shared.show(title: "Saved to Photos")
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
