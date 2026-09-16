import XCTest
@testable import GPXlibre

/// Spec "valhalla-client-toggle" (it19) : teste le VRAI Keychain (disponible en simulateur),
/// jamais un mock — chaque test utilise un `service` dédié et unique (jamais
/// `ValhallaKeychainStore.defaultService`, le vrai service de l'app) pour ne jamais lire/écrire
/// les identifiants réels ni polluer un autre test, avec nettoyage explicite en tearDown (même
/// esprit que `tracksDirectoryOverride`/`UserDefaults(suiteName:)` ailleurs dans la suite).
final class ValhallaKeychainStoreTests: XCTestCase {
    private var service: String!

    override func setUp() {
        super.setUp()
        service = "ValhallaKeychainStoreTests.\(UUID().uuidString)"
    }

    override func tearDown() {
        ValhallaKeychainStore.clear(service: service)
        super.tearDown()
    }

    func testUsernameAndPasswordAreEmptyByDefault() {
        XCTAssertEqual(ValhallaKeychainStore.username(service: service), "")
        XCTAssertEqual(ValhallaKeychainStore.password(service: service), "")
    }

    func testSaveThenLoadRoundTrips() {
        ValhallaKeychainStore.save(username: "motard", password: "s3cr3t", service: service)

        XCTAssertEqual(ValhallaKeychainStore.username(service: service), "motard")
        XCTAssertEqual(ValhallaKeychainStore.password(service: service), "s3cr3t")
    }

    func testSavingAgainUpdatesRatherThanDuplicates() {
        ValhallaKeychainStore.save(username: "premier", password: "un", service: service)
        ValhallaKeychainStore.save(username: "second", password: "deux", service: service)

        XCTAssertEqual(ValhallaKeychainStore.username(service: service), "second")
        XCTAssertEqual(ValhallaKeychainStore.password(service: service), "deux")
    }

    func testClearRemovesBothEntries() {
        ValhallaKeychainStore.save(username: "motard", password: "s3cr3t", service: service)

        ValhallaKeychainStore.clear(service: service)

        XCTAssertEqual(ValhallaKeychainStore.username(service: service), "")
        XCTAssertEqual(ValhallaKeychainStore.password(service: service), "")
    }

    /// Un `service` distinct isole complètement les identifiants — jamais de fuite entre deux
    /// instances Valhalla configurées (ou, ici, entre deux tests).
    func testDifferentServicesAreIsolated() {
        let otherService = "ValhallaKeychainStoreTests.\(UUID().uuidString)"
        defer { ValhallaKeychainStore.clear(service: otherService) }

        ValhallaKeychainStore.save(username: "a", password: "1", service: service)
        ValhallaKeychainStore.save(username: "b", password: "2", service: otherService)

        XCTAssertEqual(ValhallaKeychainStore.username(service: service), "a")
        XCTAssertEqual(ValhallaKeychainStore.username(service: otherService), "b")
    }
}
