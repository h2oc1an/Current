import XCTest
@testable import Current

final class RepeatConfigurationTests: XCTestCase {
    func testValidConfiguration() {
        let configuration = RepeatConfiguration(interval: 0.5, count: 10)
        XCTAssertEqual(configuration?.interval, 0.5)
        XCTAssertEqual(configuration?.count, 10)
    }

    func testIntervalBoundaries() {
        XCTAssertNotNil(RepeatConfiguration(interval: RepeatConfiguration.minimumInterval, count: 1))
        XCTAssertNotNil(RepeatConfiguration(interval: RepeatConfiguration.maximumInterval, count: 1))
        XCTAssertNil(RepeatConfiguration(interval: 0, count: 1))
        XCTAssertNil(RepeatConfiguration(interval: -1, count: 1))
        XCTAssertNil(RepeatConfiguration(interval: 3_601, count: 1))
    }

    func testNonFiniteIntervalsAreRejected() {
        XCTAssertNil(RepeatConfiguration(interval: .nan, count: 1))
        XCTAssertNil(RepeatConfiguration(interval: .infinity, count: 1))
    }

    func testCountMustBePositive() {
        XCTAssertNil(RepeatConfiguration(interval: 1, count: 0))
        XCTAssertNil(RepeatConfiguration(interval: 1, count: -1))
        XCTAssertNotNil(RepeatConfiguration(interval: 1, count: 1))
    }
}
