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

    /// Loads each picked photo, then runs stickers at most 3 at a time so 16
    /// simultaneous Vision + Core Image passes don't spike memory. Selection order
    /// is preserved for display.
    private func load(_ selection: [PhotosPickerItem]) async {
        var loaded: [StickerItem] = []
        for pick in selection {
            if let data = try? await pick.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                loaded.append(StickerItem(source: img))
            }
        }
        items = loaded
        pickerSelection = []

        var firstSuccess = true
        await withTaskGroup(of: (UUID, UIImage?).self) { group in
            var next = 0
            let maxInFlight = 3

            func addTask(_ index: Int) {
                let item = loaded[index]
                group.addTask { (item.id, await StickerProcessor.makeSticker(from: item.source)) }
            }

            while next < loaded.count && next < maxInFlight {
                addTask(next); next += 1
            }
            for await (id, sticker) in group {
                if let idx = items.firstIndex(where: { $0.id == id }) {
                    if let sticker {
                        items[idx].result = sticker
                        items[idx].status = .done
                        if firstSuccess { Haptics.success(); firstSuccess = false }
                    } else {
                        items[idx].status = .failed
                    }
                }
                if next < loaded.count { addTask(next); next += 1 }
            }
        }
    }

    private func save(_ item: StickerItem) {}
    private func saveAll() {}
}

/// One grid cell: sticker over checkerboard when done, source + spinner while
/// processing, or an inline mark when no subject was found. Tapping a done cell saves it.
private struct StickerCell: View {
    let item: StickerLabView.StickerItem
    let onSave: () -> Void

    var body: some View {
        ZStack {
            Checkerboard()
            switch item.status {
            case .processing:
                Image(uiImage: item.source)
                    .resizable().scaledToFit()
                    .opacity(0.4)
                    .overlay { ProgressView() }
            case .done:
                if let result = item.result {
                    Image(uiImage: result)
                        .resizable().scaledToFit()
                        .padding(Spacing.xs)
                }
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .font(.avoraFootnote)
                    .foregroundStyle(Color.avoraError)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if item.saved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.avoraSuccess)
                    .padding(Spacing.xs)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if item.status == .done && !item.saved { onSave() } }
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
