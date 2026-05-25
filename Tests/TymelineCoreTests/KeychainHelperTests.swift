import Testing
import Foundation
@testable import TymelineCore

@Suite("KeychainHelper")
final class KeychainHelperTests {
    let testService: String

    init() {
        testService = "app.tymeline.test.\(UUID().uuidString)"
    }

    deinit {
        try? KeychainHelper.deleteAll(in: testService)
    }

    @Test func accountNameFormat() {
        #expect(
            KeychainHelper.accountName(service: .linear, workspaceId: "ws-123")
            == "linear-ws-123"
        )
        #expect(
            KeychainHelper.accountName(service: .clockify, workspaceId: "ws-abc")
            == "clockify-ws-abc"
        )
    }

    @Test func setAndGetSecret() throws {
        try KeychainHelper.setSecret("hello-key", for: "account-1", in: testService)
        #expect(
            try KeychainHelper.getSecret(for: "account-1", in: testService) == "hello-key"
        )
    }

    @Test func getMissingSecretThrowsItemNotFound() {
        #expect(throws: KeychainError.itemNotFound) {
            try KeychainHelper.getSecret(for: "missing", in: testService)
        }
    }

    @Test func setOverwritesExistingSecret() throws {
        try KeychainHelper.setSecret("v1", for: "rotated", in: testService)
        try KeychainHelper.setSecret("v2", for: "rotated", in: testService)
        #expect(
            try KeychainHelper.getSecret(for: "rotated", in: testService) == "v2"
        )
    }

    @Test func deleteSecret() throws {
        try KeychainHelper.setSecret("doomed", for: "doomed-account", in: testService)
        try KeychainHelper.deleteSecret(for: "doomed-account", in: testService)
        #expect(throws: KeychainError.itemNotFound) {
            try KeychainHelper.getSecret(for: "doomed-account", in: testService)
        }
    }

    @Test func deleteSecretIsIdempotent() {
        #expect(throws: Never.self) {
            try KeychainHelper.deleteSecret(for: "never-existed", in: testService)
        }
    }

    @Test func deleteAllClearsAllAccountsForService() throws {
        try KeychainHelper.setSecret("a", for: "acct-a", in: testService)
        try KeychainHelper.setSecret("b", for: "acct-b", in: testService)
        try KeychainHelper.deleteAll(in: testService)
        #expect(throws: KeychainError.itemNotFound) {
            try KeychainHelper.getSecret(for: "acct-a", in: testService)
        }
        #expect(throws: KeychainError.itemNotFound) {
            try KeychainHelper.getSecret(for: "acct-b", in: testService)
        }
    }

    @Test func secretRoundTripPreservesUnicode() throws {
        let unicode = "Žirafa 🦒 ключ"
        try KeychainHelper.setSecret(unicode, for: "unicode", in: testService)
        #expect(
            try KeychainHelper.getSecret(for: "unicode", in: testService) == unicode
        )
    }
}
