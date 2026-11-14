import StoreKit
import XCTest
@testable import Paygate

/// Which purchases entitle a user. A lifetime non-consumable used to be left
/// out, so its buyers kept seeing the paywall and Restore found nothing.
final class EntitlementTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNonConsumableEntitles() {
        XCTAssertTrue(StoreKitManager.grantsEntitlement(
            type: .nonConsumable, revocationDate: nil, expirationDate: nil, now: now
        ))
    }

    func testSubscriptionsEntitle() {
        XCTAssertTrue(StoreKitManager.grantsEntitlement(
            type: .autoRenewable, revocationDate: nil, expirationDate: now.addingTimeInterval(60), now: now
        ))
        XCTAssertTrue(StoreKitManager.grantsEntitlement(
            type: .nonRenewable, revocationDate: nil, expirationDate: nil, now: now
        ))
    }

    func testConsumableNeverEntitles() {
        XCTAssertFalse(StoreKitManager.grantsEntitlement(
            type: .consumable, revocationDate: nil, expirationDate: nil, now: now
        ))
    }

    func testRevokedDoesNotEntitle() {
        XCTAssertFalse(StoreKitManager.grantsEntitlement(
            type: .nonConsumable, revocationDate: now, expirationDate: nil, now: now
        ))
    }

    func testExpiredSubscriptionDoesNotEntitle() {
        XCTAssertFalse(StoreKitManager.grantsEntitlement(
            type: .autoRenewable, revocationDate: nil, expirationDate: now.addingTimeInterval(-1), now: now
        ))
    }
}

final class RestoreBridgeTests: XCTestCase {

    func testDeliverScriptCarriesStatusAndProduct() {
        let js = RestoreBridge.deliverScript(status: .restored, productId: "lifetime")
        XCTAssertTrue(js.contains(#""status":"restored""#), js)
        XCTAssertTrue(js.contains(#""productId":"lifetime""#), js)
        XCTAssertTrue(js.contains("_restoreResult"), js)
    }

    func testDeliverScriptEscapesMessage() {
        let js = RestoreBridge.deliverScript(status: .error, message: "bad \"quote\" </script>")
        // JSON-encoded, so a quote in an error message cannot end the string.
        XCTAssertTrue(js.contains(#"bad \"quote\""#), js)
    }

    func testNothingFoundAndErrorAlwaysHaveAMessage() {
        XCTAssertNotNil(RestoreBridge.fallbackAlert(for: .nothingFound))
        XCTAssertNotNil(RestoreBridge.fallbackAlert(for: .error))
        XCTAssertNil(RestoreBridge.fallbackAlert(for: .cancelled))
        XCTAssertNil(RestoreBridge.fallbackAlert(for: .restored))
    }
}
