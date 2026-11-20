import CoreGraphics
import XCTest
@testable import Current

final class FlowConfigurationTests: XCTestCase {
    private func step(_ x: CGFloat, _ y: CGFloat, _ minimum: String, _ maximum: String = "2") -> ClickStep {
        ClickStep(
            point: CGPoint(x: x, y: y),
            minimumIntervalText: minimum,
            maximumIntervalText: maximum
        )
    }

    func testEmptyStepsAreRejected() {
        guard case .failure = FlowConfiguration.plan(steps: [], cyclesText: "1") else {
            return XCTFail("空步骤应校验失败")
        }
    }

    func testValidPlan() {
        let steps = [step(10, 20, "0.5", "1.5"), step(30, 40, "1", "2")]
        guard case .success(let plan) = FlowConfiguration.plan(steps: steps, cyclesText: "3") else {
            return XCTFail("应校验通过")
        }
        XCTAssertEqual(plan.cycles, 3)
        XCTAssertEqual(plan.steps, [
            FlowConfiguration.Step(point: CGPoint(x: 10, y: 20), minimumInterval: 0.5, maximumInterval: 1.5),
            FlowConfiguration.Step(point: CGPoint(x: 30, y: 40), minimumInterval: 1, maximumInterval: 2),
        ])
    }

    func testIntervalBoundaries() {
        XCTAssertSuccess(FlowConfiguration.plan(steps: [step(0, 0, "0.1", "0.2")], cyclesText: "1"))
        XCTAssertSuccess(FlowConfiguration.plan(steps: [step(0, 0, "3599.9", "3600")], cyclesText: "1"))
        XCTAssertFailure(FlowConfiguration.plan(steps: [step(0, 0, "0.09")], cyclesText: "1"))
        XCTAssertFailure(FlowConfiguration.plan(steps: [step(0, 0, "3599.9", "3600.1")], cyclesText: "1"))
        XCTAssertFailure(FlowConfiguration.plan(steps: [step(0, 0, "abc")], cyclesText: "1"))
        XCTAssertFailure(FlowConfiguration.plan(steps: [step(0, 0, "")], cyclesText: "1"))
        XCTAssertFailure(FlowConfiguration.plan(steps: [step(0, 0, "0.55")], cyclesText: "1"))
        XCTAssertFailure(FlowConfiguration.plan(steps: [step(0, 0, "1", "1.55")], cyclesText: "1"))
    }

    func testMaximumIntervalMayEqualMinimumButNotBeSmaller() {
        XCTAssertSuccess(FlowConfiguration.plan(steps: [step(0, 0, "1", "1")], cyclesText: "1"))
        XCTAssertFailure(FlowConfiguration.plan(steps: [step(0, 0, "2", "1")], cyclesText: "1"))
        XCTAssertFailure(FlowConfiguration.plan(steps: [step(0, 0, "2", "1.9")], cyclesText: "1"))
    }

    func testRandomIntervalStaysWithinRangeAndUsesTenths() {
        guard case .success(let plan) = FlowConfiguration.plan(
            steps: [step(0, 0, "0.7", "1.2")],
            cyclesText: "1"
        ) else {
            return XCTFail("应校验通过")
        }

        for _ in 0..<100 {
            let interval = plan.steps[0].randomInterval()
            XCTAssertGreaterThanOrEqual(interval, 0.7)
            XCTAssertLessThanOrEqual(interval, 1.2)
            XCTAssertEqual(interval * 10, (interval * 10).rounded(), accuracy: 0.000_001)
        }
    }

    func testCycleCountParsing() {
        XCTAssertSuccess(FlowConfiguration.plan(steps: [step(0, 0, "1")], cyclesText: "1"))
        XCTAssertSuccess(FlowConfiguration.plan(steps: [step(0, 0, "1")], cyclesText: " 5 "))
        XCTAssertFailure(FlowConfiguration.plan(steps: [step(0, 0, "1")], cyclesText: "0"))
        XCTAssertFailure(FlowConfiguration.plan(steps: [step(0, 0, "1")], cyclesText: "-1"))
        XCTAssertFailure(FlowConfiguration.plan(steps: [step(0, 0, "1")], cyclesText: "abc"))
        XCTAssertFailure(FlowConfiguration.plan(steps: [step(0, 0, "1")], cyclesText: ""))
    }

    func testErrorMentionsStepNumber() {
        let steps = [step(0, 0, "1"), step(1, 1, "bogus")]
        guard case .failure(let error) = FlowConfiguration.plan(steps: steps, cyclesText: "1") else {
            return XCTFail("应校验失败")
        }
        XCTAssertTrue(error.message.contains("第 2 步"), error.message)
    }

    private func XCTAssertSuccess<T>(_ result: Result<T, FlowValidationError>) {
        guard case .success = result else {
            return XCTFail("应校验通过，实际失败：\(result)")
        }
    }

    private func XCTAssertFailure<T>(_ result: Result<T, FlowValidationError>) {
        guard case .failure = result else {
            return XCTFail("应校验失败")
        }
    }
}
