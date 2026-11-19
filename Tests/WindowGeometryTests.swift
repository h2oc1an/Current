import CoreGraphics
import XCTest
@testable import Current

final class WindowGeometryTests: XCTestCase {
    func testQuartzRectConvertsToAppKitFrame() {
        let quartzRect = CGRect(x: 100, y: 200, width: 400, height: 300)
        let frame = WindowGeometry.appKitFrame(forQuartzRect: quartzRect, mainScreenHeight: 1_000)
        XCTAssertEqual(frame, CGRect(x: 100, y: 500, width: 400, height: 300))
    }

    func testRelativePointUsesWindowTopLeft() {
        let frame = CGRect(x: 100, y: 500, width: 400, height: 300)
        let point = WindowGeometry.relativePoint(forAppKitPoint: CGPoint(x: 150, y: 770), inAppKitFrame: frame)
        XCTAssertEqual(point, CGPoint(x: 50, y: 30))
    }

    func testRelativePointFollowsMovedWindow() {
        let relativePoint = CGPoint(x: 40, y: 60)
        let original = WindowGeometry.quartzPoint(
            forRelativePoint: relativePoint,
            in: CGRect(x: 100, y: 200, width: 400, height: 300)
        )
        let moved = WindowGeometry.quartzPoint(
            forRelativePoint: relativePoint,
            in: CGRect(x: 500, y: 700, width: 400, height: 300)
        )
        XCTAssertEqual(original, CGPoint(x: 140, y: 260))
        XCTAssertEqual(moved, CGPoint(x: 540, y: 760))
    }

    func testPointOutsideResizedWindowIsRejected() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
        XCTAssertNil(WindowGeometry.quartzPoint(forRelativePoint: CGPoint(x: 100, y: 20), in: bounds))
        XCTAssertNil(WindowGeometry.quartzPoint(forRelativePoint: CGPoint(x: 20, y: 80), in: bounds))
        XCTAssertNil(WindowGeometry.quartzPoint(forRelativePoint: CGPoint(x: -1, y: 20), in: bounds))
    }

    func testNonFinitePointIsRejected() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
        XCTAssertNil(WindowGeometry.quartzPoint(forRelativePoint: CGPoint(x: CGFloat.nan, y: 20), in: bounds))
        XCTAssertNil(WindowGeometry.quartzPoint(forRelativePoint: CGPoint(x: 20, y: CGFloat.infinity), in: bounds))
    }
}
