import SwiftUI
import PhotosUI

struct CreateView: View {
    let style: Style
    private let placeholder: RemoteImageRef?
    @Environment(AppState.self) private var app
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var sourceImages: [UIImage] = []
    @State private var poller = BatchGenerationPoller()
    @State private var showPaywall = false
    @State private var errorText: String?
    @State private var isSubmitting = false
    @State private var isPhotosExpanded = false

    init(route: CreateRoute) {
        self.style = route.style
        self.placeholder = route.placeholder
    }

    /// Image shown before the user picks photos: an explicit one from the route
    /// (e.g. a prior creation), otherwise the style's own sample.
    private var effectivePlaceholder: RemoteImageRef? {
        placeholder ?? style.sampleImagePath.map { RemoteImageRef(path: $0, source: .sample) }
    }

    private var hasResults: Bool { !poller.items.isEmpty }

    private var isWorking: Bool {
        isSubmitting || (!poller.items.isEmpty && !poller.allTerminal)
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            if hasResults {
                resultsGrid
            } else {
                pickArea
            }
            controls
        }
        .padding(Spacing.lg)
        .navigationTitle(style.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !hasResults {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images) {
                        Text("Select photo")
                    }
                    .disabled(isWorking)
                }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView().environment(app) }
        .onChange(of: pickerItems) { _, items in Task { await loadPicked(items) } }
        .onChange(of: poller.allTerminal) { _, done in
            if done { Task { await app.refreshProfile() } }
        }
        .onDisappear { poller.stop() }
    }

    // Area shown before generating: a single large photo, a 2-wide grid of photos,
    // or a placeholder prompt — filling the available height in every case.
    @ViewBuilder private var pickArea: some View {
        if sourceImages.isEmpty {
            ZStack {
                if let effectivePlaceholder {
                    RemoteImage(path: effectivePlaceholder.path, source: effectivePlaceholder.source, contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(Color.avoraSurface)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sourceImages.count == 1 {
            photoCard(sourceImages[0])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isPhotosExpanded {
            photoStrip
        } else {
            stackedPhotos
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isPhotosExpanded = true
                    }
                }
        }
    }

    // Expanded view: all picked photos laid out horizontally, scrolled one at a time.
    private var photoStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.md) {
                ForEach(Array(sourceImages.enumerated()), id: \.offset) { _, img in
                    photoCard(img)
                        .containerRelativeFrame(.horizontal, count: 4, span: 3, spacing: Spacing.md)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func photoCard(_ img: UIImage) -> some View {
        Image(uiImage: img)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // Multiple picked photos fan out as an overlapping deck, each card rotated a
    // little around the centre so the stack reads as a pile.
    private var stackedPhotos: some View {
        let count = sourceImages.count
        return ZStack {
            ForEach(Array(sourceImages.enumerated()), id: \.offset) { index, img in
                photoCard(img)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    .rotationEffect(.degrees((Double(index) - Double(count - 1) / 2) * 7))
                    .zIndex(Double(index))
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Area shown after generating: one cell per job, each progressing independently.
    @ViewBuilder private var resultsGrid: some View {
        filledGrid(poller.items) { item in
            resultCell(item)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.avoraSurface)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // Lays items out in rows of two, each cell sharing the available width and height
    // equally. A single item therefore fills the whole area; more than one forms a grid.
    @ViewBuilder private func filledGrid<T, Content: View>(
        _ items: [T], @ViewBuilder content: @escaping (T) -> Content
    ) -> some View {
        let rows = stride(from: 0, to: items.count, by: 2).map { start in
            Array(items[start..<min(start + 2, items.count)].enumerated().map { ($0.offset + start, $0.element) })
        }
        VStack(spacing: Spacing.md) {
            ForEach(rows, id: \.first!.0) { row in
                HStack(spacing: Spacing.md) {
                    ForEach(row, id: \.0) { _, item in content(item) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder private func resultCell(_ item: BatchGenerationPoller.Item) -> some View {
        switch item.phase {
        case .working:
            ProgressView("Generating…")
        case .done(let path):
            RemoteImage(path: path, contentMode: .fill)
                .clipped()
                .overlay(alignment: .bottomTrailing) {
                    Button { Task { await saveOne(path) } } label: {
                        Image(systemName: "square.and.arrow.down")
                            .padding(Spacing.sm)
                            .avoraGlass(in: Circle())
                    }
                    .padding(Spacing.sm)
                }
        case .failed:
            Text("Couldn't generate — credit refunded")
                .font(.avoraFootnote)
                .foregroundStyle(Color.avoraTextSecondary)
                .multilineTextAlignment(.center)
                .padding(Spacing.sm)
        }
    }

    @ViewBuilder private var controls: some View {
        if hasResults {
            HStack {
                Button { Task { await saveAll() } } label: {
                    Label("Save all", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.avoraAccent)
                .disabled(isWorking)
                Button { reset() } label: {
                    Label("Generate again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .tint(Color.avoraAccent)
            }
        } else {
            AvoraPrimaryButton { Task { await generate() } } label: {
                VStack(spacing: Spacing.xs) {
                    Label("Generate", systemImage: "wand.and.stars")
                    Text("\(sourceImages.count * app.config.generationCost) credits")
                        .font(.avoraCaption)
                        .opacity(0.85)
                }
            }
            .disabled(sourceImages.isEmpty || isWorking)
        }
        if let errorText {
            Text(errorText).foregroundStyle(Color.avoraError).font(.avoraFootnote)
        }
    }

    private func loadPicked(_ newItems: [PhotosPickerItem]) async {
        var imgs: [UIImage] = []
        for item in newItems {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                imgs.append(img)
            }
        }
        sourceImages = imgs
        isPhotosExpanded = false
        poller.stop()
        poller = BatchGenerationPoller()
        errorText = nil
    }

    private func generate() async {
        let imgs = sourceImages
        guard !imgs.isEmpty, !isSubmitting else { return }
        let cost = imgs.count * app.config.generationCost
        guard (app.profile?.totalCredits ?? 0) >= cost else { showPaywall = true; return }
        isSubmitting = true
        defer { isSubmitting = false }
        errorText = nil
        do {
            // Upload all inputs in parallel; if any fails, abort before submitting
            // so billing stays all-or-nothing (nothing is charged).
            // Normalize on the main actor — UIImage isn't Sendable; the parallel uploads
            // then carry only Sendable Data. Order preserved via the index map.
            let payloads = imgs.map { ImageNormalizer.normalize($0) }
            let paths = try await withThrowingTaskGroup(of: (Int, String).self) { group -> [String] in
                for (i, data) in payloads.enumerated() {
                    group.addTask {
                        let path = try await AvoraAPI.shared.uploadInput(data)
                        return (i, path)
                    }
                }
                var byIndex: [Int: String] = [:]
                for try await (i, path) in group { byIndex[i] = path }
                return payloads.indices.map { byIndex[$0]! }
            }
            let jobIds = try await AvoraAPI.shared.submitBatch(styleId: style.id, inputPaths: paths)
            poller.start(jobIds: jobIds, poll: { try await AvoraAPI.shared.poll(jobId: $0) })
        } catch AvoraError.insufficientCredits {
            showPaywall = true
        } catch {
            errorText = "Couldn't start generation. Try again."
        }
    }

    private func saveOne(_ path: String) async {
        guard let img = try? await ImageStore.shared.image(for: path) else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
    }

    private func saveAll() async {
        for item in poller.items {
            if case .done(let path) = item.phase {
                await saveOne(path)
            }
        }
    }

    private func reset() {
        poller.stop()
        poller = BatchGenerationPoller()
        pickerItems = []
        sourceImages = []
        isPhotosExpanded = false
        errorText = nil
    }
}
