import SwiftUI

@main
struct CurrentApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Current", id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}
