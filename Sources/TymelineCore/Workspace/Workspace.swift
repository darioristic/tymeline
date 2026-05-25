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

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#7C7C7C",
        pollIntervalSeconds: Int = 30,
        enabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        linearUserId: String? = nil,
        clockifyWorkspaceId: String? = nil,
        clockifyUserId: String? = nil
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
    }
}
