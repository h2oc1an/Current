import CoreGraphics
import Foundation

// 事件流的一步：相对目标窗口左上角的点击位置，以及点击后到下一步（或下一轮）
// 之间的随机等待范围。间隔以文本保存，便于直接绑定输入框。
struct ClickStep: Identifiable, Equatable, Codable {
    let id: UUID
    var point: CGPoint
    var minimumIntervalText: String
    var maximumIntervalText: String

    init(
        id: UUID = UUID(),
        point: CGPoint,
        minimumIntervalText: String = "1",
        maximumIntervalText: String = "2"
    ) {
        self.id = id
        self.point = point
        self.minimumIntervalText = minimumIntervalText
        self.maximumIntervalText = maximumIntervalText
    }
}

// 事件流的校验与快照。运行期间使用不可变快照，避免界面编辑影响正在执行的流程。
struct FlowValidationError: Error, Equatable {
    let message: String
}

enum FlowConfiguration {
    static let minimumInterval: TimeInterval = 0.1
    static let maximumInterval: TimeInterval = 3_600

    struct Step: Equatable {
        let point: CGPoint
        let minimumInterval: TimeInterval
        let maximumInterval: TimeInterval

        func randomInterval() -> TimeInterval {
            let minimumTenths = Int((minimumInterval * 10).rounded())
            let maximumTenths = Int((maximumInterval * 10).rounded())
            return TimeInterval(Int.random(in: minimumTenths...maximumTenths)) / 10
        }
    }

    struct Plan: Equatable {
        let steps: [Step]
        // 循环轮数，必须为正整数。
        let cycles: Int
    }

    static func plan(steps: [ClickStep], cyclesText: String) -> Result<Plan, FlowValidationError> {
        guard !steps.isEmpty else {
            return .failure(FlowValidationError(message: "请先添加至少一个事件流步骤。"))
        }

        var parsedSteps: [Step] = []
        for (index, step) in steps.enumerated() {
            guard let minimum = parseInterval(step.minimumIntervalText),
                  let maximum = parseInterval(step.maximumIntervalText) else {
                return .failure(FlowValidationError(message: "第 \(index + 1) 步的间隔需在 0.1～3600 秒之间，且最多保留 1 位小数。"))
            }
            guard maximum >= minimum else {
                return .failure(FlowValidationError(message: "第 \(index + 1) 步的最大间隔不能小于最小间隔。"))
            }
            parsedSteps.append(Step(point: step.point, minimumInterval: minimum, maximumInterval: maximum))
        }

        let trimmedCycles = cyclesText.trimmingCharacters(in: .whitespaces)
        guard let cycles = Int(trimmedCycles), cycles > 0 else {
            return .failure(FlowValidationError(message: "循环次数需为正整数。"))
        }

        return .success(Plan(steps: parsedSteps, cycles: cycles))
    }

    private static func parseInterval(_ text: String) -> TimeInterval? {
        guard let interval = TimeInterval(text.trimmingCharacters(in: .whitespaces)),
              interval.isFinite,
              interval >= minimumInterval,
              interval <= maximumInterval,
              abs(interval * 10 - (interval * 10).rounded()) < 0.000_001 else {
            return nil
        }
        return interval
    }
}
