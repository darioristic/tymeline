import XCTest
@testable import TymelineCore

final class KeychainHelperTests: XCTestCase {
    private var testService: String = ""

    override func setUp() {
        super.setUp()
        testService = "app.tymeline.test.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        try KeychainHelper.deleteAll(in: testService)
        try super.tearDownWithError()
    }

    func testAccountNameFormat() {
        XCTAssertEqual(
            KeychainHelper.accountName(service: .linear, workspaceId: "ws-123"),
            "linear-ws-123"
        )
        XCTAssertEqual(
            KeychainHelper.accountName(service: .clockify, workspaceId: "ws-abc"),
            "clockify-ws-abc"
        )
    }

    func testSetAndGetSecret() throws {
        try KeychainHelper.setSecret("hello-key", for: "account-1", in: testService)
        XCTAssertEqual(
            try KeychainHelper.getSecret(for: "account-1", in: testService),
            "hello-key"
        )
    }

    func testGetMissingSecretThrowsItemNotFound() {
        XCTAssertThrowsError(
            try KeychainHelper.getSecret(for: "missing", in: testService)
        ) { error in
            XCTAssertEqual(error as? KeychainError, .itemNotFound)
        }
    }

    func testSetOverwritesExistingSecret() throws {
        try KeychainHelper.setSecret("v1", for: "rotated", in: testService)
        try KeychainHelper.setSecret("v2", for: "rotated", in: testService)
        XCTAssertEqual(
            try KeychainHelper.getSecret(for: "rotated", in: testService),
            "v2"
        )
    }

    func testDeleteSecret() throws {
        try KeychainHelper.setSecret("doomed", for: "doomed-account", in: testService)
        try KeychainHelper.deleteSecret(for: "doomed-account", in: testService)
        XCTAssertThrowsError(
            try KeychainHelper.getSecret(for: "doomed-account", in: testService)
        ) { error in
            XCTAssertEqual(error as? KeychainError, .itemNotFound)
        }
    }

    func testDeleteSecretIsIdempotent() throws {
        XCTAssertNoThrow(
            try KeychainHelper.deleteSecret(for: "never-existed", in: testService)
        )
    }

    func testDeleteAllClearsAllAccountsForService() throws {
        try KeychainHelper.setSecret("a", for: "acct-a", in: testService)
        try KeychainHelper.setSecret("b", for: "acct-b", in: testService)
        try KeychainHelper.deleteAll(in: testService)
        XCTAssertThrowsError(try KeychainHelper.getSecret(for: "acct-a", in: testService))
        XCTAssertThrowsError(try KeychainHelper.getSecret(for: "acct-b", in: testService))
    }

    func testSecretRoundTripPreservesUnicode() throws {
        let unicode = "Žirafa 🦒 ключ ключ"
        try KeychainHelper.setSecret(unicode, for: "unicode", in: testService)
        XCTAssertEqual(
            try KeychainHelper.getSecret(for: "unicode", in: testService),
            unicode
        )
    }
}
