import SwiftUI
import PhotosUI

struct CreateView: View {
    let style: Style
    @Environment(AppState.self) private var app
    @State private var pickerItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var poller = GenerationPoller()
    @State private var resultURL: URL?
    @State private var showPaywall = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 16) {
            previewArea
            controls
        }
        .padding()
        .navigationTitle(style.name)
        .sheet(isPresented: $showPaywall) { PaywallView().environment(app) }
        .onChange(of: pickerItem) { _, item in Task { await loadPicked(item) } }
        .onChange(of: poller.phase) { _, phase in Task { await handlePhase(phase) } }
    }

    @ViewBuilder private var previewArea: some View {
        ZStack {
            if let resultURL {
                AsyncImage(url: resultURL) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
            } else if let sourceImage {
                Image(uiImage: sourceImage).resizable().scaledToFit().opacity(isWorking ? 0.4 : 1)
            } else {
                RoundedRectangle(cornerRadius: 16).fill(.secondary.opacity(0.12))
                    .overlay { Text("Pick a photo to start").foregroundStyle(.secondary) }
            }
            if isWorking {
                ProgressView("Generating…")
                    .padding()
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var controls: some View {
        if resultURL != nil {
            HStack {
                Button { Task { await save() } } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                Button { reset() } label: {
                    Label("Generate again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        } else {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(sourceImage == nil ? "Choose Photo" : "Change Photo", systemImage: "photo")
            }
            .buttonStyle(.bordered)
            Button { Task { await generate() } } label: {
                Label("Generate", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(sourceImage == nil || isWorking)
        }
        if let errorText {
            Text(errorText).foregroundStyle(.red).font(.footnote)
        }
    }

    private var isWorking: Bool {
        if case .working = poller.phase { return true }
        return false
    }

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self),
              let img = UIImage(data: data) else { return }
        sourceImage = img
        resultURL = nil
        errorText = nil
    }

    private func generate() async {
        guard let img = sourceImage else { return }
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
            resultURL = try? await AvoraAPI.shared.signedOutputURL(path)
            await app.refreshProfile()
        case .failed:
            errorText = "This photo couldn't be generated. Your credit was refunded."
            await app.refreshProfile()
        default:
            break
        }
    }

    private func save() async {
        guard let url = resultURL,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
    }

    private func reset() {
        poller.stop()
        poller = GenerationPoller()
        resultURL = nil
        pickerItem = nil
        sourceImage = nil
        errorText = nil
    }
}
