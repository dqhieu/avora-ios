import SwiftUI
import PhotosUI
import TipKit

struct CreateView: View {
    let style: Style
    private let placeholder: RemoteImageRef?
    @Environment(AppState.self) private var app
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var sourceImages: [UIImage] = []
    @State private var poller = BatchGenerationPoller()
    @State private var showCredits = false
    @State private var errorText: String?
    @State private var isSubmitting = false
    @State private var isPhotosExpanded = false
    @State private var quality: GenerationQuality = .default
    @State private var promptText: String
    @State private var showPromptEditor = false
    @State private var saved = false
    private let selectPhotoTip = SelectPhotoTip()

    init(route: CreateRoute) {
        self.style = route.style
        self.placeholder = route.placeholder
        _promptText = State(initialValue: route.customPrompt ?? "")
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

    private var isCustom: Bool { style.id == Style.custom.id }

    private var trimmedPrompt: String {
        promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var promptValid: Bool {
        !trimmedPrompt.isEmpty && trimmedPrompt.count <= 2000
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            photoArea
            if isCustom && !hasResults && !isWorking {
                promptField
                    .padding(.horizontal, Spacing.lg)
            }
            controls
                .padding(.horizontal, Spacing.lg)
        }
        .padding(.vertical, Spacing.lg)
        .navigationTitle(style.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !hasResults && !isWorking {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images) {
                        Text("Select photo")
                    }
                    .disabled(isWorking)
                    .popoverTip(selectPhotoTip)
                }
            } else if poller.allTerminal {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Haptics.tap(); reset() } label: { ThiingIcon(name: "ActionRegenerate", size: 32) }
                }
            }
        }
        .sheet(isPresented: $showPromptEditor) {
            PromptEditorPopup(
                initialText: promptText,
                onCancel: { showPromptEditor = false },
                onSave: { text in
                    promptText = text
                    showPromptEditor = false
                }
            )
        }
        .sheet(isPresented: $showCredits) { CreditsView().environment(app) }
        .onChange(of: pickerItems) { _, items in
            if !items.isEmpty { selectPhotoTip.invalidate(reason: .actionPerformed) }
            Task { await loadPicked(items) }
        }
        .onChange(of: poller.allTerminal) { _, done in
            if done {
                if hasResults { Haptics.success() }
                Task { await app.refreshProfile() }
            }
        }
        .onDisappear { poller.stop() }
        .ignoresSafeArea(.keyboard, edges: .all)
    }

    // The photo area is shown in every state — picking, generating, and done. A single
    // photo fills the height; multiple photos form a tappable stacked deck that expands
    // into a horizontal strip. Each card reflects its own generation state via `slotCard`.
    @ViewBuilder private var photoArea: some View {
        if sourceImages.isEmpty {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images) {
                ZStack {
                    if let effectivePlaceholder {
                        RemoteImage(path: effectivePlaceholder.path, source: effectivePlaceholder.source, contentMode: .fit)
                    } else {
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(Color.avoraSurface)
                        VStack(spacing: Spacing.sm) {
                            ThiingIcon(name: "StateEmpty", size: 64)
                            Text("Tap to add a photo")
                                .font(.avoraFootnote)
                                .foregroundStyle(Color.avoraTextTertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
        } else if sourceImages.count == 1 {
            slotCard(0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isPhotosExpanded {
            photoStrip
        } else {
            stackedPhotos
                .contentShape(Rectangle())
                .onTapGesture {
                    Haptics.tap()
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
        .avoraSoftScrollEdge()
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

    // One card per picked photo. It eases out of focus while its job generates,
    // pulls into the finished result once ready, or shows a refunded badge if it failed.
    @ViewBuilder private func slotCard(_ index: Int) -> some View {
        let phase = poller.items.indices.contains(index) ? poller.items[index].phase : nil
        if case .failed = phase {
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
        } else {
            let resultPath: String? = {
                if case .done(let path) = phase { return path } else { return nil }
            }()
            let isWorkingPhase: Bool = {
                if case .working = phase { return true } else { return false }
            }()
            ScanReveal(
                source: sourceImages[index],
                resultPath: resultPath,
                isGenerating: isSubmitting || isWorkingPhase
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // Compact glass menu, left of the Generate button. Each option shows its
    // per-image credit cost so pricing is transparent before choosing.
    private var qualityMenu: some View {
        Menu {
            Picker("Quality", selection: $quality) {
                ForEach(GenerationQuality.allCases) { q in
                    Text("\(q.label) · \(app.config.cost(for: q)) credits").tag(q)
                }
            }
        } label: {
            // Two lines: a bold "Quality" label on top with the dimmed value +
            // chevron caption below, so the control reads as "Quality: <value>".
            VStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Text("Quality")
                        .font(.avoraButton)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.avoraCaption)
                }
                Text(quality.label)
                    .font(.avoraCaption)
                    .opacity(0.85)
            }
            .foregroundStyle(Color.avoraTextPrimary)
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 56)
            .avoraGlass(in: Capsule())
        }
        .disabled(isWorking)
        .onChange(of: quality) { Haptics.selection() }
    }

    private var promptField: some View {
        Button {
            Haptics.tap()
            showPromptEditor = true
        } label: {
            HStack(spacing: Spacing.md) {
                Text(trimmedPrompt.isEmpty ? "Describe your style…" : promptText)
                    .font(.avoraBody)
                    .foregroundStyle(trimmedPrompt.isEmpty ? Color.avoraTextTertiary : Color.avoraTextPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "square.and.pencil")
                    .font(.avoraCallout)
                    .foregroundStyle(Color.avoraTextTertiary)
            }
            .contentShape(.rect)
            .padding(Spacing.md)
            .avoraGlass(in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    @ViewBuilder private var controls: some View {
        if poller.allTerminal {
            AvoraPrimaryButton { Haptics.tap(); Task { await saveAll() } } label: {
                HStack(spacing: Spacing.xs) {
                    ThiingIcon(name: saved ? "ActionSaved" : "ActionSave", size: saved ? 32 : 28)
                    Text(saved ? "Saved" : "Save to Photos")
                }
            }
            .disabled(saved)
        } else {
            HStack(spacing: Spacing.md) {
                qualityMenu
                AvoraPrimaryButton { Haptics.impact(); Task { await generate() } } label: {
                    if isWorking {
                        HStack(spacing: Spacing.sm) {
                            ProgressView().tint(Color.avoraOnAccent)
                            GeneratingLabel(isActive: isWorking)
                        }
                    } else {
                        VStack(spacing: Spacing.xs) {
                            HStack(spacing: Spacing.xs) {
                                ThiingIcon(name: "ActionGenerate", size: 28)
                                Text("Generate")
                            }
                            if !sourceImages.isEmpty {
                                Text("\(sourceImages.count * app.config.cost(for: quality)) credits")
                                  .font(.avoraCaption)
                                  .opacity(0.85)
                                  .contentTransition(.numericText())
                                  .animation(.snappy, value: sourceImages.count)
                                  .animation(.snappy, value: quality)
                            }
                        }
                    }
                }
                .disabled(sourceImages.isEmpty || isWorking || (isCustom && !promptValid))
            }
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
        let cost = imgs.count * app.config.cost(for: quality)
        // Enter the working state up front so the button shows its spinner and
        // becomes non-tappable for the whole operation — including the profile
        // fetch below, which does a network round-trip on a cold start.
        isSubmitting = true
        defer { isSubmitting = false }
        // The profile may not have loaded yet on a cold start. Try once so the
        // optimistic pre-check has real data instead of assuming zero credits.
        if app.profile == nil { await app.refreshProfile() }
        // Only short-circuit to the paywall when we actually know the balance is
        // too low. If it's still unknown, let the authoritative server 402 decide
        // (caught below) rather than falsely blocking a paying user.
        if let credits = app.profile?.totalCredits, credits < cost { showCredits = true; return }
        errorText = nil
        saved = false
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
            let jobIds: [UUID]
            if isCustom {
                jobIds = try await AvoraAPI.shared.submitBatch(
                    styleId: nil, inputPaths: paths, quality: quality.backend,
                    customPrompt: trimmedPrompt)
            } else {
                jobIds = try await AvoraAPI.shared.submitBatch(
                    styleId: style.id, inputPaths: paths, quality: quality.backend)
            }
            poller.start(jobIds: jobIds, poll: { try await AvoraAPI.shared.poll(jobId: $0) })
        } catch AvoraError.insufficientCredits {
            showCredits = true
        } catch {
            print("😂 \(error)")
            Haptics.error()
            errorText = "Couldn't start generation. Try again."
        }
    }

    private func saveOne(_ path: String) async {
        guard let img = try? await ImageStore.shared.image(for: path) else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
    }

    private func saveAll() async {
        var count = 0
        for item in poller.items {
            if case .done(let path) = item.phase {
                await saveOne(path)
                count += 1
            }
        }
        if count > 0 {
            saved = true
            ToastWindowManager.shared.show(
                title: count == 1 ? "Saved to Photos" : "Saved \(count) to Photos"
            )
        }
    }

    private func reset() {
        poller.stop()
        poller = BatchGenerationPoller()
        pickerItems = []
        sourceImages = []
        isPhotosExpanded = false
        errorText = nil
        saved = false
    }
}
