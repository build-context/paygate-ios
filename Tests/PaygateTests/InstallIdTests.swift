import XCTest
@testable import Paygate

final class InstallIdTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "paygate.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testCreatesAndPersistsAnIdOnFirstUse() {
        XCTAssertNil(defaults.string(forKey: InstallId.defaultsKey))
        let id = InstallId.resolve(in: defaults)
        XCTAssertNotNil(UUID(uuidString: id), "expected a UUID, got \(id)")
        XCTAssertEqual(defaults.string(forKey: InstallId.defaultsKey), id)
    }

    func testReturnsTheSameIdOnEveryLaterUse() {
        let first = InstallId.resolve(in: defaults)
        for _ in 0..<5 {
            XCTAssertEqual(InstallId.resolve(in: defaults), first)
        }
    }

    func testKeepsAnIdAnEarlierLaunchStored() {
        defaults.set("from-an-earlier-launch", forKey: InstallId.defaultsKey)
        XCTAssertEqual(InstallId.resolve(in: defaults), "from-an-earlier-launch")
    }

    func testEveryRequestCarriesTheInstallId() {
        var request = URLRequest(url: URL(string: "https://example.invalid/sdk/gates/g")!)
        PaygateHTTP.applyDefaultHeaders(to: &request, apiKey: "pk_test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Paygate-Install-Id"), Paygate.installId)
        XCTAssertEqual(Paygate.installId, Paygate.installId)
    }

    func testAppUserIdIsSentOnlyWhenUsable() {
        defer { Paygate.appUserId = nil }

        func sent() -> String? {
            var request = URLRequest(url: URL(string: "https://example.invalid/sdk/gates/g")!)
            PaygateHTTP.applyDefaultHeaders(to: &request, apiKey: "pk_test")
            return request.value(forHTTPHeaderField: "Paygate-App-User-Id")
        }

        Paygate.appUserId = nil
        XCTAssertNil(sent())
        Paygate.appUserId = "  user_42  "
        XCTAssertEqual(sent(), "user_42")
        Paygate.appUserId = "   "
        XCTAssertNil(sent())
        Paygate.appUserId = "a\nb"
        XCTAssertNil(sent())
        Paygate.appUserId = String(repeating: "x", count: 257)
        XCTAssertNil(sent())
    }
}
