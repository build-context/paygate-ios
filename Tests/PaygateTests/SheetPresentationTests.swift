import UIKit
import XCTest
@testable import Paygate

/// The paywall sheet takes the app's corner radius, so it matches the app's
/// other sheets. Without one it must look exactly as it always has.
@MainActor
final class SheetPresentationTests: XCTestCase {

    func testRadiusIsAppliedToTheSheet() throws {
        guard #available(iOS 16.0, *) else { throw XCTSkip("preferredCornerRadius needs iOS 16") }
        let vc = UIViewController()
        Paygate.configurePresentation(of: vc, style: .sheet, sheetCornerRadius: 40)
        XCTAssertEqual(vc.modalPresentationStyle, .pageSheet)
        XCTAssertEqual(vc.sheetPresentationController?.preferredCornerRadius, 40)
    }

    func testNoRadiusKeepsTheSystemDefault() throws {
        guard #available(iOS 16.0, *) else { throw XCTSkip("preferredCornerRadius needs iOS 16") }
        let vc = UIViewController()
        Paygate.configurePresentation(of: vc, style: .sheet, sheetCornerRadius: nil)
        XCTAssertNil(vc.sheetPresentationController?.preferredCornerRadius)
    }

    func testFullScreenIgnoresTheRadius() {
        let vc = UIViewController()
        Paygate.configurePresentation(of: vc, style: .fullScreen, sheetCornerRadius: 40)
        XCTAssertEqual(vc.modalPresentationStyle, .fullScreen)
    }

    func testBadValuesFallBackToTheSystemRadius() {
        XCTAssertNil(Paygate.sanitizedCornerRadius(nil))
        XCTAssertNil(Paygate.sanitizedCornerRadius(-1))
        XCTAssertNil(Paygate.sanitizedCornerRadius(.nan))
        XCTAssertNil(Paygate.sanitizedCornerRadius(.infinity))
        XCTAssertEqual(Paygate.sanitizedCornerRadius(0), 0)
        XCTAssertEqual(Paygate.sanitizedCornerRadius(40), 40)
    }
}
