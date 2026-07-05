import Foundation

/// Persists small snapshots of list metadata (styles, first page of the
/// collection) so the UI can paint instantly on cold launch, before the network
/// refresh returns. Rebuildable optimization: every read and write is
/// best-effort and the snapshot is never authoritative.
enum SnapshotStore {
    /// Base directory for snapshot files (Caches/snapshots). Rebuildable data,
    /// so the OS may purge it — callers fall back to a normal network load.
    private static let directory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var stylesURL: URL { directory.appendingPathComponent("styles.json") }
    private static var collectionURL: URL { directory.appendingPathComponent("collection.json") }

    static func loadStyles() -> [Style]? { load([Style].self, from: stylesURL) }
    static func saveStyles(_ styles: [Style]) { save(styles, to: stylesURL) }

    static func loadCollection() -> [Generation]? { load([Generation].self, from: collectionURL) }
    static func saveCollection(_ items: [Generation]) { save(items, to: collectionURL) }

    static func clearCollection() { try? FileManager.default.removeItem(at: collectionURL) }

    private static func communityURL(_ sort: CommunitySort) -> URL {
        directory.appendingPathComponent("community-\(sort.rawValue).json")
    }

    static func loadCommunity(_ sort: CommunitySort) -> [CommunityItem]? {
        load([CommunityItem].self, from: communityURL(sort))
    }
    static func saveCommunity(_ sort: CommunitySort, _ items: [CommunityItem]) {
        save(items, to: communityURL(sort))
    }
    static func clearCommunity() {
        for sort in CommunitySort.allCases {
            try? FileManager.default.removeItem(at: communityURL(sort))
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
