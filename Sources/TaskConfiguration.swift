import CoreGraphics
import Foundation

struct SavedWindow: Codable, Equatable {
    let bundleIdentifier: String?
    let ownerName: String
    let title: String
    let bounds: CGRect

    init(window: WindowDescriptor) {
        bundleIdentifier = window.ownerBundleIdentifier
        ownerName = window.ownerName
        title = window.title
        bounds = window.bounds
    }

    init(bundleIdentifier: String?, ownerName: String, title: String, bounds: CGRect) {
        self.bundleIdentifier = bundleIdentifier
        self.ownerName = ownerName
        self.title = title
        self.bounds = bounds
    }

    func matchingWindow(in windows: [WindowDescriptor]) -> WindowDescriptor? {
        var candidates = windows.filter { window in
            let matchesApplication: Bool
            if let bundleIdentifier {
                matchesApplication = window.ownerBundleIdentifier == bundleIdentifier
            } else {
                matchesApplication = window.ownerName == ownerName
            }
            return matchesApplication && window.title == title
        }

        if candidates.count > 1 {
            candidates = candidates.filter { $0.bounds == bounds }
        }
        return candidates.count == 1 ? candidates[0] : nil
    }
}

struct TaskConfiguration: Codable, Equatable {
    var window: SavedWindow?
    var selectedRelativePoint: CGPoint?
    var clickMode: ClickMode
    var executionMode: ExecutionMode
    var intervalText: String
    var countText: String
    var steps: [ClickStep]
    var flowCycleText: String
    var clickAfterPicking: Bool

    init(
        window: SavedWindow?,
        selectedRelativePoint: CGPoint?,
        clickMode: ClickMode,
        executionMode: ExecutionMode,
        intervalText: String,
        countText: String,
        steps: [ClickStep],
        flowCycleText: String,
        clickAfterPicking: Bool = false
    ) {
        self.window = window
        self.selectedRelativePoint = selectedRelativePoint
        self.clickMode = clickMode
        self.executionMode = executionMode
        self.intervalText = intervalText
        self.countText = countText
        self.steps = steps
        self.flowCycleText = flowCycleText
        self.clickAfterPicking = clickAfterPicking
    }

    private enum CodingKeys: String, CodingKey {
        case window, selectedRelativePoint, clickMode, executionMode
        case intervalText, countText, steps, flowCycleText, clickAfterPicking
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        window = try container.decodeIfPresent(SavedWindow.self, forKey: .window)
        selectedRelativePoint = try container.decodeIfPresent(CGPoint.self, forKey: .selectedRelativePoint)
        clickMode = try container.decode(ClickMode.self, forKey: .clickMode)
        executionMode = try container.decode(ExecutionMode.self, forKey: .executionMode)
        intervalText = try container.decode(String.self, forKey: .intervalText)
        countText = try container.decode(String.self, forKey: .countText)
        steps = try container.decode([ClickStep].self, forKey: .steps)
        flowCycleText = try container.decode(String.self, forKey: .flowCycleText)
        clickAfterPicking = try container.decodeIfPresent(Bool.self, forKey: .clickAfterPicking) ?? false
    }

    static let initial = TaskConfiguration(
        window: nil,
        selectedRelativePoint: nil,
        clickMode: .foreground,
        executionMode: .single,
        intervalText: "1",
        countText: "10",
        steps: [],
        flowCycleText: "1"
    )
}

struct ClickTask: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var configuration: TaskConfiguration

    init(id: UUID = UUID(), name: String, configuration: TaskConfiguration) {
        self.id = id
        self.name = name
        self.configuration = configuration
    }
}

struct TaskLibrary: Codable, Equatable {
    var tasks: [ClickTask] = []
    var selectedTaskID: UUID?

    mutating func upsert(_ task: ClickTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        selectedTaskID = task.id
    }

    mutating func delete(id: UUID) {
        tasks.removeAll { $0.id == id }
        if selectedTaskID == id {
            selectedTaskID = nil
        }
    }
}
