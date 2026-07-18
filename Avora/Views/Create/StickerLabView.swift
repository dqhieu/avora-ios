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
        var selected = false

        enum Status { case processing, done, failed }
    }

    @State private var pickerSelection: [PhotosPickerItem] = []
    @State private var items: [StickerItem] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 3)

    private var isProcessing: Bool { items.contains { $0.status == .processing } }
    private var selectedCount: Int { items.filter { $0.selected }.count }

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
                    StickerCell(item: item) { toggle(item) }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
        }
    }

    @ViewBuilder private var controls: some View {
        AvoraPrimaryButton { Haptics.tap(); saveSelected() } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "square.and.arrow.down")
                Text("Save \(selectedCount) to Photos")
            }
        }
        .disabled(isProcessing || selectedCount == 0)
    }

    /// Shows each picked photo as soon as it decodes (so the grid fills in instead
    /// of waiting for the whole batch), then runs stickers at most 3 at a time so 16
    /// simultaneous Vision + Core Image passes don't spike memory. Selection order
    /// is preserved for display.
    private func load(_ selection: [PhotosPickerItem]) async {
        items = []
        for pick in selection {
            if let data = try? await pick.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                items.append(StickerItem(source: img))
            }
        }
        pickerSelection = []

        let sources = items.map { ($0.id, $0.source) }
        var firstSuccess = true
        await withTaskGroup(of: (UUID, UIImage?).self) { group in
            var next = 0
            let maxInFlight = 3

            func addTask(_ index: Int) {
                let (id, source) = sources[index]
                group.addTask { (id, await StickerProcessor.makeSticker(from: source)) }
            }

            while next < sources.count && next < maxInFlight {
                addTask(next); next += 1
            }
            for await (id, sticker) in group {
                if let idx = items.firstIndex(where: { $0.id == id }) {
                    if let sticker {
                        items[idx].result = sticker
                        items[idx].status = .done
                        items[idx].selected = true
                        if firstSuccess { Haptics.success(); firstSuccess = false }
                    } else {
                        items[idx].status = .failed
                    }
                }
                if next < sources.count { addTask(next); next += 1 }
            }
        }
    }

    /// Toggles whether a finished sticker is included in the save.
    private func toggle(_ item: StickerItem) {
        guard item.status == .done,
              let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].selected.toggle()
        Haptics.tap()
    }

    /// Saves every selected sticker and reports the count.
    private func saveSelected() {
        let chosen = items.indices.filter { items[$0].selected }
        guard !chosen.isEmpty else { return }
        for idx in chosen {
            if let result = items[idx].result {
                UIImageWriteToSavedPhotosAlbum(result, nil, nil, nil)
            }
        }
        let count = chosen.count
        ToastWindowManager.shared.show(title: count == 1 ? "Saved 1 sticker to Photos" : "Saved \(count) stickers to Photos")
    }
}

/// One grid cell: sticker over checkerboard when done, source + spinner while
/// processing, or an inline mark when no subject was found. Tapping a done cell
/// toggles whether it's included in the save.
private struct StickerCell: View {
    let item: StickerLabView.StickerItem
    let onToggle: () -> Void

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
                        .opacity(item.selected ? 1 : 0.4)
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
            if item.status == .done {
                Image(systemName: item.selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.selected ? Color.avoraSuccess : Color.avoraTextTertiary)
                    .padding(Spacing.xs)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if item.status == .done { onToggle() } }
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
