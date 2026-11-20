import CoreGraphics
import XCTest
@testable import Current

final class TaskConfigurationTests: XCTestCase {
    func testConfigurationCodableRoundTrip() throws {
        var configuration = TaskConfiguration.initial
        configuration.window = SavedWindow(
            bundleIdentifier: "com.example.app",
            ownerName: "Example",
            title: "Main",
            bounds: CGRect(x: 10, y: 20, width: 800, height: 600)
        )
        configuration.selectedRelativePoint = CGPoint(x: 100, y: 200)
        configuration.clickMode = .windowRouted
        configuration.executionMode = .flow
        configuration.intervalText = "0.5"
        configuration.countText = "20"
        configuration.steps = [
            ClickStep(point: CGPoint(x: 1, y: 2), minimumIntervalText: "0.5", maximumIntervalText: "1.5")
        ]
        configuration.flowCycleText = "3"

        let task = ClickTask(name: "测试任务", configuration: configuration)
        let decoded = try JSONDecoder().decode(ClickTask.self, from: JSONEncoder().encode(task))
        XCTAssertEqual(decoded, task)
    }

    func testLibraryUpsertsAndDeletesTasks() {
        let id = UUID()
        let original = ClickTask(id: id, name: "原任务", configuration: .initial)
        var library = TaskLibrary()
        library.upsert(original)
        XCTAssertEqual(library.tasks, [original])
        XCTAssertEqual(library.selectedTaskID, id)

        var updatedConfiguration = TaskConfiguration.initial
        updatedConfiguration.countText = "99"
        let updated = ClickTask(id: id, name: "新名称", configuration: updatedConfiguration)
        library.upsert(updated)
        XCTAssertEqual(library.tasks, [updated])
        XCTAssertEqual(library.tasks.count, 1)

        library.delete(id: id)
        XCTAssertTrue(library.tasks.isEmpty)
        XCTAssertNil(library.selectedTaskID)
    }

    func testWindowMatchesAcrossProcessAndWindowIDs() {
        let bounds = CGRect(x: 10, y: 20, width: 800, height: 600)
        let saved = SavedWindow(
            bundleIdentifier: "com.example.app",
            ownerName: "Old Name",
            title: "Main",
            bounds: bounds
        )
        let current = window(id: 999, pid: 888, bundleID: "com.example.app", title: "Main", bounds: bounds)
        XCTAssertEqual(saved.matchingWindow(in: [current]), current)
    }

    func testWindowBoundsDisambiguateMultipleMatches() {
        let savedBounds = CGRect(x: 10, y: 20, width: 800, height: 600)
        let saved = SavedWindow(
            bundleIdentifier: "com.example.app",
            ownerName: "Example",
            title: "Main",
            bounds: savedBounds
        )
        let other = window(id: 1, pid: 10, bundleID: "com.example.app", title: "Main", bounds: CGRect(x: 0, y: 0, width: 400, height: 300))
        let expected = window(id: 2, pid: 10, bundleID: "com.example.app", title: "Main", bounds: savedBounds)
        XCTAssertEqual(saved.matchingWindow(in: [other, expected]), expected)
    }

    func testMissingOrAmbiguousWindowDoesNotMatch() {
        let bounds = CGRect(x: 10, y: 20, width: 800, height: 600)
        let saved = SavedWindow(
            bundleIdentifier: "com.example.app",
            ownerName: "Example",
            title: "Main",
            bounds: bounds
        )
        let first = window(id: 1, pid: 10, bundleID: "com.example.app", title: "Main", bounds: bounds)
        let second = window(id: 2, pid: 10, bundleID: "com.example.app", title: "Main", bounds: bounds)
        let wrongTitle = window(id: 3, pid: 10, bundleID: "com.example.app", title: "Other", bounds: bounds)

        XCTAssertNil(saved.matchingWindow(in: []))
        XCTAssertNil(saved.matchingWindow(in: [wrongTitle]))
        XCTAssertNil(saved.matchingWindow(in: [first, second]))
    }

    private func window(
        id: CGWindowID,
        pid: pid_t,
        bundleID: String,
        title: String,
        bounds: CGRect
    ) -> WindowDescriptor {
        WindowDescriptor(
            id: id,
            ownerPID: pid,
            ownerName: "Example",
            ownerBundleIdentifier: bundleID,
            title: title,
            bounds: bounds
        )
    }
}
