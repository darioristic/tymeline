import Foundation

/// File-based JSON persistence for Workspace records.
///
/// Default location: `~/Library/Application Support/tymeline/workspaces.json`
/// (or the sandboxed equivalent when running inside the app). Tests inject a
/// custom URL.
///
/// API keys are NOT stored here - they live in macOS Keychain.
public actor WorkspaceStorage {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Convenience initializer for production use - resolves the standard
    /// Application Support path and creates the parent directory.
    public init(fileManager: FileManager = .default) throws {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent("tymeline", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("workspaces.json")
    }

    public func load() throws -> [Workspace] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Workspace].self, from: data)
    }

    public func save(_ workspaces: [Workspace]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(workspaces)
        try data.write(to: url, options: .atomic)
    }
}
