import Foundation

struct TaskStore {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            self.fileURL = applicationSupport
                .appendingPathComponent("Current", isDirectory: true)
                .appendingPathComponent("tasks.json")
        }
    }

    func load() throws -> TaskLibrary {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return TaskLibrary()
        }
        return try JSONDecoder().decode(TaskLibrary.self, from: Data(contentsOf: fileURL))
    }

    func save(_ library: TaskLibrary) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: fileURL, options: .atomic)
    }
}
