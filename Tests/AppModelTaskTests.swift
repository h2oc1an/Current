import XCTest
@testable import Current

@MainActor
final class AppModelTaskTests: XCTestCase {
    func testTaskLifecyclePersistsAcrossModelInstances() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CurrentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TaskStore(fileURL: directory.appendingPathComponent("tasks.json"))
        let model = AppModel(taskStore: store)
        XCTAssertFalse(model.showsConfiguration)

        model.startNewTask()
        XCTAssertTrue(model.showsConfiguration)
        XCTAssertEqual(model.tasks.map(\.name), ["任务 1"])
        XCTAssertEqual(model.selectedTaskID, model.tasks.first?.id)
        model.taskNameText = "任务 A"
        model.countText = "12"
        model.saveTask()
        guard let taskA = model.tasks.first(where: { $0.name == "任务 A" }) else {
            return XCTFail("任务 A 应保存成功：\(model.errorMessage ?? "")")
        }

        model.startNewTask()
        model.taskNameText = "任务 B"
        model.countText = "34"
        model.saveTask()
        XCTAssertEqual(model.tasks.count, 2)

        model.selectTask(id: taskA.id)
        XCTAssertEqual(model.countText, "12")
        model.countText = "56"
        model.saveTask()
        XCTAssertEqual(model.tasks.count, 2)

        let restored = AppModel(taskStore: store)
        XCTAssertEqual(restored.selectedTaskID, taskA.id)
        XCTAssertEqual(restored.taskNameText, "任务 A")
        XCTAssertEqual(restored.countText, "56")

        restored.selectTask(id: taskA.id)
        XCTAssertNil(restored.selectedTaskID)
        XCTAssertFalse(restored.showsConfiguration)
        restored.selectTask(id: taskA.id)
        XCTAssertEqual(restored.selectedTaskID, taskA.id)
        XCTAssertTrue(restored.showsConfiguration)

        restored.deleteSelectedTask()
        XCTAssertNil(restored.selectedTaskID)
        XCTAssertFalse(restored.showsConfiguration)
        XCTAssertEqual(restored.tasks.map(\.name), ["任务 B"])
        XCTAssertEqual(try store.load().selectedTaskID, nil)
    }
}
