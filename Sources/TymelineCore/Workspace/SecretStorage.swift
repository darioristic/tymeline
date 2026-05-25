import Foundation

/// File-based replacement for macOS Keychain that avoids the "tymeline
/// wants to use your confidential information" prompt every rebuild.
///
/// With ad-hoc signing, every build of the app has a different code
/// signature, so the Keychain ACL treats each build as a different app
/// and prompts on every brew upgrade / local rebuild. App sandbox already
/// restricts ~/Library/Containers/app.tymeline/Data/ to this bundle id,
/// so storing API keys as JSON there is a reasonable trade-off for an
/// ad-hoc-signed personal tool: no prompts, still scoped to this app.
///
/// Format on disk: `{ "linear-<uuid>": "<key>", "clockify-<uuid>": "<key>" }`
public actor SecretStorage {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Standard install: writes to Application Support/tymeline/secrets.json
    /// inside the sandbox container.
    public init(fileManager: FileManager = .default) throws {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent("tymeline", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("secrets.json")
    }

    public func get(_ account: String) throws -> String? {
        try load()[account]
    }

    public func set(_ secret: String, for account: String) throws {
        var all = try load()
        all[account] = secret
        try save(all)
    }

    public func delete(_ account: String) throws {
        var all = try load()
        guard all.removeValue(forKey: account) != nil else { return }
        try save(all)
    }

    public func all() throws -> [String: String] {
        try load()
    }

    private func load() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func save(_ secrets: [String: String]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(secrets)
        try data.write(to: url, options: .atomic)
        // Restrict file mode to user-only just in case (sandbox already
        // protects the directory, but defense in depth is cheap).
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }
}
