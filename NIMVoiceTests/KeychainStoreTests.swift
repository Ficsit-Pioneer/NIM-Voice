import XCTest
@testable import NIMVoice

/// Round-trips the Keychain-backed key store. These run hosted inside the app
/// (TEST_HOST) so the bundle has keychain access. If the environment still
/// can't reach the keychain, the tests skip rather than fail spuriously.
final class KeychainStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        KeychainStore.delete()
    }

    override func tearDown() {
        KeychainStore.delete()
        super.tearDown()
    }

    func testSaveReadDeleteRoundTrip() throws {
        let token = "nvapi-\(UUID().uuidString)"
        try XCTSkipUnless(KeychainStore.save(token), "Keychain unavailable in this environment")

        XCTAssertEqual(KeychainStore.read(), token)
        XCTAssertTrue(KeychainStore.hasKey)

        XCTAssertTrue(KeychainStore.delete())
        XCTAssertNil(KeychainStore.read())
        XCTAssertFalse(KeychainStore.hasKey)
    }

    func testOverwriteReplacesPreviousValue() throws {
        try XCTSkipUnless(KeychainStore.save("first-key"), "Keychain unavailable in this environment")
        XCTAssertTrue(KeychainStore.save("second-key"))
        XCTAssertEqual(KeychainStore.read(), "second-key")
    }

    func testSavingBlankClearsTheKey() throws {
        try XCTSkipUnless(KeychainStore.save("something"), "Keychain unavailable in this environment")
        // Whitespace-only input is treated as "clear".
        XCTAssertTrue(KeychainStore.save("   "))
        XCTAssertNil(KeychainStore.read())
        XCTAssertFalse(KeychainStore.hasKey)
    }

    func testKeyIsTrimmedOnSave() throws {
        try XCTSkipUnless(KeychainStore.save("  nvapi-padded  "), "Keychain unavailable in this environment")
        XCTAssertEqual(KeychainStore.read(), "nvapi-padded")
    }
}
