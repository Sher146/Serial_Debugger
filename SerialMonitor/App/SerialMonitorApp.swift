import SwiftUI
import SerialCore

@main
struct SerialMonitorApp: App {
    private let coordinator = SessionCoordinator(serialPort: POSIXSerialPortAdapter())
    private let uiTestClient = SessionPreviewClient(state: .connected(SerialConfiguration(path: "/dev/cu.ui-test")))

    var body: some Scene {
        WindowGroup(L10n.appName) {
            SessionView(client: isRunningUITests ? uiTestClient : coordinator)
        }
        .defaultSize(width: 1_180, height: 760)
        .windowToolbarStyle(.unifiedCompact)
    }

    private var isRunningUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing-connected")
    }
}
