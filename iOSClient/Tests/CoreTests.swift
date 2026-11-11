import XCTest
import CryptoKit
import WebKit
@testable import Lanpangzi

final class CoreTests: XCTestCase {
    func testNormalizeAndRejectIncompleteCDK() throws {
        XCTAssertEqual(try Account.normalize(" abcdef-ghijkl-mnopqr-stuvwx "), "ABCDEFGHIJKLMNOPQRSTUVWX")
        XCTAssertThrowsError(try Account.normalize("短卡"))
    }

    func testRejectUnsafeGameURLs() throws {
        for value in ["javascript:alert(1)", "file:///etc/passwd", "https://user:pass@game.example/", "https://"] {
            XCTAssertThrowsError(try APIClient.gameURL(value))
        }
        XCTAssertEqual(try APIClient.gameURL("https://game.example/start?token=test").host, "game.example")
    }

    func testScriptIntegrityRejectsCorruptionMissingHeaderAndSizeMismatch() throws {
        let data = Data("window.test = true;".utf8)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let manifest = ScriptManifest(ok: true, sha256: sha, size: data.count)
        XCTAssertEqual(try APIClient.verifiedScript(data, manifest: manifest, header: sha), "window.test = true;")
        XCTAssertThrowsError(try APIClient.verifiedScript(Data("corrupted".utf8), manifest: manifest, header: sha))
        XCTAssertThrowsError(try APIClient.verifiedScript(data, manifest: manifest, header: nil))
        XCTAssertThrowsError(try APIClient.verifiedScript(data,
            manifest: ScriptManifest(ok: true, sha256: sha, size: data.count + 1), header: sha))
    }

    @MainActor
    func testSixPersistentStoresUseDistinctIdentifiers() {
        let accounts = (0..<6).map { _ in Account() }
        XCTAssertEqual(Set(accounts.map(\.id)).count, 6)
        let stores = accounts.map { WKWebsiteDataStore(forIdentifier: $0.id) }
        XCTAssertTrue(stores.allSatisfy(\.isPersistent))
        for i in 0..<6 {
            for j in 0..<6 where i != j { XCTAssertFalse(stores[i] === stores[j]) }
        }
    }

    @MainActor
    func testSameOriginCookiesAreIsolatedAcrossSixWindows() async throws {
        let stores = (0..<6).map { _ in WKWebsiteDataStore(forIdentifier: UUID()) }
        for (index, store) in stores.enumerated() {
            let cookie = try XCTUnwrap(HTTPCookie(properties: [
                .domain: "isolation.example", .path: "/", .name: "account", .value: String(index), .secure: "TRUE"
            ]))
            await store.httpCookieStore.setCookie(cookie)
        }
        for (index, store) in stores.enumerated() {
            let values = await store.httpCookieStore.allCookies()
                .filter { $0.domain == "isolation.example" && $0.name == "account" }.map(\.value)
            XCTAssertEqual(values, [String(index)])
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        }
    }
}
