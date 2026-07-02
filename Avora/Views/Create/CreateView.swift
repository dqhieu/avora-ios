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
            photoArea
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

    // The photo area is shown in every state — picking, generating, and done. A single
    // photo fills the height; multiple photos form a tappable stacked deck that expands
    // into a horizontal strip. Each card reflects its own generation state via `slotCard`.
    @ViewBuilder private var photoArea: some View {
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
            slotCard(0)
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

    // Expanded view: all photos laid out horizontally, scrolled one at a time.
    private var photoStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.md) {
                ForEach(sourceImages.indices, id: \.self) { index in
                    slotCard(index)
                        .containerRelativeFrame(.horizontal, count: 4, span: 3, spacing: Spacing.md)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Photos fan out as an overlapping deck, each card rotated a little around the
    // centre so the stack reads as a pile.
    private var stackedPhotos: some View {
        let count = sourceImages.count
        return ZStack {
            ForEach(sourceImages.indices, id: \.self) { index in
                slotCard(index)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    .rotationEffect(.degrees((Double(index) - Double(count - 1) / 2) * 7))
                    .zIndex(Double(index))
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // One card per picked photo. It shows the source image, sparkles while its job
    // generates, the finished result once ready, or a refunded badge if it failed.
    @ViewBuilder private func slotCard(_ index: Int) -> some View {
        let phase = poller.items.indices.contains(index) ? poller.items[index].phase : nil
        switch phase {
        case .done(let path):
            RemoteImage(path: path, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        case .working:
            photoCard(sourceImages[index]) { SparkleDrift() }
        case .failed:
            photoCard(sourceImages[index]) {
                ZStack(alignment: .bottomTrailing) {
                    Color.black.opacity(0.2)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.avoraFootnote)
                        .foregroundStyle(Color.avoraTextPrimary)
                        .padding(Spacing.sm)
                        .avoraGlass(in: Circle())
                        .padding(Spacing.sm)
                }
            }
        case nil:
            // Show sparkles the instant Generate is tapped, before the upload + submit
            // finishes and the poller takes over the working state.
            photoCard(sourceImages[index]) {
                if isSubmitting { SparkleDrift() }
            }
        }
    }

    // A photo clipped to a rounded card, with an optional overlay (shimmer, badge)
    // that is clipped to the same shape.
    private func photoCard<Overlay: View>(
        _ img: UIImage, @ViewBuilder overlay: () -> Overlay
    ) -> some View {
        Image(uiImage: img)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(overlay())
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    @ViewBuilder private var controls: some View {
        if poller.allTerminal {
            HStack {
                Button { Task { await saveAll() } } label: {
                    Label("Save all", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.avoraAccent)
                Button { reset() } label: {
                    Label("Generate again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .tint(Color.avoraAccent)
            }
        } else {
            AvoraPrimaryButton { Task { await generate() } } label: {
                if isWorking {
                    HStack(spacing: Spacing.sm) {
                        ProgressView().tint(Color.avoraOnAccent)
                        Text("Generating…")
                    }
                } else {
                    VStack(spacing: Spacing.xs) {
                        Label("Generate", systemImage: "wand.and.stars")
                        Text("\(sourceImages.count * app.config.generationCost) credits")
                            .font(.avoraCaption)
                            .opacity(0.85)
                    }
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
