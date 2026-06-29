import SwiftUI
import PhotosUI

struct CreateView: View {
    let style: Style
    @Environment(AppState.self) private var app
    @State private var pickerItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var poller = GenerationPoller()
    @State private var resultPath: String?
    @State private var showPaywall = false
    @State private var errorText: String?
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: Spacing.lg) {
            previewArea
            controls
        }
        .padding(Spacing.lg)
        .navigationTitle(style.name)
        .sheet(isPresented: $showPaywall) { PaywallView().environment(app) }
        .onChange(of: pickerItem) { _, item in Task { await loadPicked(item) } }
        .onChange(of: poller.phase) { _, phase in Task { await handlePhase(phase) } }
        .onDisappear { poller.stop() }
    }

    @ViewBuilder private var previewArea: some View {
        ZStack {
            if let resultPath {
                RemoteImage(path: resultPath, contentMode: .fit)
            } else if let sourceImage {
                Image(uiImage: sourceImage).resizable().scaledToFit().opacity(isWorking ? 0.4 : 1)
            } else {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Color.avoraSurface)
                    .overlay {
                        Text("Pick a photo to start")
                            .foregroundStyle(Color.avoraTextSecondary)
                    }
            }
            if isWorking {
                ProgressView("Generating…")
                    .padding(Spacing.lg)
                    .avoraGlass(in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var controls: some View {
        if resultPath != nil {
            HStack {
                Button { Task { await save() } } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
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
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(sourceImage == nil ? "Choose Photo" : "Change Photo", systemImage: "photo")
            }
            .buttonStyle(.bordered)
            .tint(Color.avoraAccent)
            Button { Task { await generate() } } label: {
                Label("Generate", systemImage: "wand.and.stars")
            }
            .buttonStyle(AvoraPrimaryButtonStyle())
            .disabled(sourceImage == nil || isWorking)
        }
        if let errorText {
            Text(errorText).foregroundStyle(Color.avoraError).font(.avoraFootnote)
        }
    }

    private var isWorking: Bool {
        if isSubmitting { return true }
        if case .working = poller.phase { return true }
        return false
    }

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else { return }
        sourceImage = img
        resultPath = nil
        errorText = nil
    }

    private func generate() async {
        guard let img = sourceImage, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        errorText = nil
        do {
            let data = ImageNormalizer.normalize(img)
            let path = try await AvoraAPI.shared.uploadInput(data)
            let jobId = try await AvoraAPI.shared.submit(styleId: style.id, inputPath: path)
            poller.start(jobId: jobId, poll: { try await AvoraAPI.shared.poll(jobId: $0) })
        } catch AvoraError.insufficientCredits {
            showPaywall = true
        } catch {
            errorText = "Couldn't start generation. Try again."
        }
    }

    private func handlePhase(_ phase: GenerationPoller.Phase) async {
        switch phase {
        case .done(let path):
            resultPath = path
            await app.refreshProfile()
        case .failed:
            errorText = "This photo couldn't be generated. Your credit was refunded."
            await app.refreshProfile()
        default:
            break
        }
    }

    private func save() async {
        guard let resultPath,
              let img = try? await ImageStore.shared.image(for: resultPath) else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
    }

    private func reset() {
        poller.stop()
        poller = GenerationPoller()
        resultPath = nil
        pickerItem = nil
        sourceImage = nil
        errorText = nil
    }
}
