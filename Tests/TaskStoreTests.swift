import XCTest
@testable import Current

final class TaskStoreTests: XCTestCase {
    private var directoryURL: URL!
    private var store: TaskStore!

    override func setUpWithError() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CurrentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        store = TaskStore(fileURL: directoryURL.appendingPathComponent("tasks.json"))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directoryURL)
    }

    func testMissingFileReturnsEmptyLibrary() throws {
        XCTAssertEqual(try store.load(), TaskLibrary())
    }

    func testLibraryPersistsAcrossStoreInstances() throws {
        let task = ClickTask(name: "持久化任务", configuration: .initial)
        var library = TaskLibrary()
        library.upsert(task)
        try store.save(library)

        let reloaded = try TaskStore(fileURL: store.fileURL).load()
        XCTAssertEqual(reloaded, library)
        XCTAssertEqual(reloaded.selectedTaskID, task.id)
    }

    func testCorruptedJSONThrows() throws {
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
    }
}
