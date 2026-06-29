import Foundation

@MainActor
@Observable
final class GenerationPoller {
    enum Phase: Equatable {
        case idle, working, done(outputPath: String), failed(code: String?)
    }
    private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?

    var isTerminal: Bool {
        if case .done = phase { return true }
        if case .failed = phase { return true }
        return false
    }

    func start(jobId: UUID,
               poll: @escaping (UUID) async throws -> GenerationResult,
               intervalNanos: UInt64 = 5_000_000_000) {
        phase = .working
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let r = try await poll(jobId)
                    switch r.status {
                    case .pending: break
                    case .completed:
                        if let path = r.outputPath, !path.isEmpty {
                            await MainActor.run { self?.phase = .done(outputPath: path) }
                        } else {
                            await MainActor.run { self?.phase = .failed(code: "no_output") }
                        }
                        return
                    case .failed:
                        await MainActor.run { self?.phase = .failed(code: r.errorCode) }
                        return
                    }
                } catch {
                    // transient network error: keep polling
                }
                try? await Task.sleep(nanoseconds: intervalNanos)
            }
        }
    }

    func stop() { task?.cancel(); task = nil }
}
