import Foundation

@MainActor
@Observable
final class BatchGenerationPoller {
    enum Phase: Equatable {
        case working, done(outputPath: String), failed(code: String?)
    }
    struct Item: Identifiable, Equatable {
        let id: UUID          // job id
        var phase: Phase
    }

    private(set) var items: [Item] = []
    private var tasks: [Task<Void, Never>] = []

    /// True once every job has reached a terminal phase (done or failed).
    var allTerminal: Bool {
        !items.isEmpty && items.allSatisfy {
            if case .working = $0.phase { return false }
            return true
        }
    }

    func start(jobIds: [UUID],
               poll: @escaping (UUID) async throws -> GenerationResult,
               intervalNanos: UInt64 = 5_000_000_000) {
        stop()
        items = jobIds.map { Item(id: $0, phase: .working) }
        tasks = jobIds.map { jobId in
            Task { [weak self] in
                while !Task.isCancelled {
                    do {
                        let r = try await poll(jobId)
                        switch r.status {
                        case .pending:
                            break
                        case .completed:
                            if let path = r.outputPath, !path.isEmpty {
                                self?.update(jobId, .done(outputPath: path))
                            } else {
                                self?.update(jobId, .failed(code: "no_output"))
                            }
                            return
                        case .failed:
                            self?.update(jobId, .failed(code: r.errorCode))
                            return
                        }
                    } catch {
                        // transient network error: keep polling
                    }
                    try? await Task.sleep(nanoseconds: intervalNanos)
                }
            }
        }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    private func update(_ jobId: UUID, _ phase: Phase) {
        if let idx = items.firstIndex(where: { $0.id == jobId }) {
            items[idx].phase = phase
        }
    }
}
