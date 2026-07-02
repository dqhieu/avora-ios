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

    private let columns = [GridItem(.flexible(), spacing: Spacing.md),
                           GridItem(.flexible(), spacing: Spacing.md)]

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
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if hasResults {
                    resultsGrid
                } else {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images) {
                        pickArea
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                }
                controls
            }
            .padding(Spacing.lg)
        }
        .navigationTitle(style.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) { PaywallView().environment(app) }
        .onChange(of: pickerItems) { _, items in Task { await loadPicked(items) } }
        .onChange(of: poller.allTerminal) { _, done in
            if done { Task { await app.refreshProfile() } }
        }
        .onDisappear { poller.stop() }
    }

    // Area shown before generating: thumbnails of picked photos, or a placeholder prompt.
    @ViewBuilder private var pickArea: some View {
        if sourceImages.isEmpty {
            ZStack {
                if let effectivePlaceholder {
                    RemoteImage(path: effectivePlaceholder.path, source: effectivePlaceholder.source, contentMode: .fit)
                        .opacity(0.4)
                } else {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(Color.avoraSurface)
                        .frame(height: 240)
                }
                Text("Pick up to 4 photos to start")
                    .foregroundStyle(Color.avoraTextSecondary)
                    .padding(Spacing.sm)
                    .avoraGlass(in: Capsule())
            }
            .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(Array(sourceImages.enumerated()), id: \.offset) { _, img in
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(height: 160).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
            }
        }
    }

    // Area shown after generating: one cell per job, each progressing independently.
    @ViewBuilder private var resultsGrid: some View {
        LazyVGrid(columns: columns, spacing: Spacing.md) {
            ForEach(poller.items) { item in
                resultCell(item)
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .background(Color.avoraSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
            let paths = try await withThrowingTaskGroup(of: (Int, String).self) { group -> [String] in
                for (i, img) in imgs.enumerated() {
                    group.addTask {
                        let data = ImageNormalizer.normalize(img)
                        let path = try await AvoraAPI.shared.uploadInput(data)
                        return (i, path)
                    }
                }
                var byIndex: [Int: String] = [:]
                for try await (i, path) in group { byIndex[i] = path }
                return imgs.indices.map { byIndex[$0]! }
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
        errorText = nil
    }
}
