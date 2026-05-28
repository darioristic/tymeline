import Foundation

/// A configured (Linear, Clockify) pair. The user can have N of these
/// (e.g. "Work" + "Personal"). Each has its own poll loop and active timer.
///
/// API keys are NOT in this struct - they live in macOS Keychain under
/// service `app.tymeline`, accounts `linear-<id>` and `clockify-<id>`.
public struct Workspace: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var colorHex: String
    public var pollIntervalSeconds: Int
    public var enabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    /// Resolved on first successful Linear /viewer call.
    public var linearUserId: String?
    /// Resolved on first successful Clockify /user call.
    public var clockifyWorkspaceId: String?
    public var clockifyUserId: String?

    /// Maps Linear projectId -> Clockify projectId. The user configures this
    /// in Settings. If an issue's Linear project is not in the map, the
    /// timer start request will fail (Clockify often requires a project).
    public var projectMappings: [String: String]

    /// When true, the Linear poll includes issues with state type `backlog`
    /// in addition to `unstarted` + `started`. Default false to keep the
    /// menu focused on what you're actually working on.
    public var includeBacklog: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#7C7C7C",
        pollIntervalSeconds: Int = 10,
        enabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        linearUserId: String? = nil,
        clockifyWorkspaceId: String? = nil,
        clockifyUserId: String? = nil,
        projectMappings: [String: String] = [:],
        includeBacklog: Bool = false
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.pollIntervalSeconds = pollIntervalSeconds
        self.enabled = enabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.linearUserId = linearUserId
        self.clockifyWorkspaceId = clockifyWorkspaceId
        self.clockifyUserId = clockifyUserId
        self.projectMappings = projectMappings
        self.includeBacklog = includeBacklog
    }

    enum CodingKeys: String, CodingKey {
        case id, name, colorHex, pollIntervalSeconds, enabled
        case createdAt, updatedAt
        case linearUserId, clockifyWorkspaceId, clockifyUserId
        case projectMappings
        case includeBacklog
    }

    /// Custom decoder so older `workspaces.json` files without
    /// `projectMappings` / `includeBacklog` still load with defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.colorHex = try c.decode(String.self, forKey: .colorHex)
        self.pollIntervalSeconds = try c.decode(Int.self, forKey: .pollIntervalSeconds)
        self.enabled = try c.decode(Bool.self, forKey: .enabled)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        self.linearUserId = try c.decodeIfPresent(String.self, forKey: .linearUserId)
        self.clockifyWorkspaceId = try c.decodeIfPresent(String.self, forKey: .clockifyWorkspaceId)
        self.clockifyUserId = try c.decodeIfPresent(String.self, forKey: .clockifyUserId)
        self.projectMappings = try c.decodeIfPresent([String: String].self, forKey: .projectMappings) ?? [:]
        self.includeBacklog = try c.decodeIfPresent(Bool.self, forKey: .includeBacklog) ?? false
    }
}
