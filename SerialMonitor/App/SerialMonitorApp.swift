import SwiftUI

@main
struct SerialMonitorApp: App {
    var body: some Scene {
        WindowGroup("Serial Monitor") {
            ContentUnavailableView(
                "Serial Monitor",
                systemImage: "cable.connector",
                description: Text("P0 基础设施验证中")
            )
        }
    }
}
