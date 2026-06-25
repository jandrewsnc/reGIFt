import Foundation

actor GIFCache {
    static let shared = GIFCache()

    private let cacheDir: URL
    private var inProgress: [String: Task<URL, Error>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private init() {
        cacheDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("regift", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func cachedFile(id: String, sourceURL: URL) async throws -> URL {
        let dest = cacheDir.appendingPathComponent("\(id).gif")
        if FileManager.default.fileExists(atPath: dest.path) {
            return dest
        }
        if let existing = inProgress[id] {
            return try await existing.value
        }
        let task = Task<URL, Error> {
            let (data, _) = try await self.session.data(from: sourceURL)
            try data.write(to: dest, options: .atomic)
            return dest
        }
        inProgress[id] = task
        defer { inProgress.removeValue(forKey: id) }
        return try await task.value
    }

    // Synchronously computable without actor isolation — used during drag initiation
    nonisolated func expectedPath(id: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("regift", isDirectory: true)
            .appendingPathComponent("\(id).gif")
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }
}
