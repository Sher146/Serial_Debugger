import SwiftUI
import SerialCore

@main
struct SerialMonitorApp: App {
    @StateObject private var model: SessionViewModel

    init() {
        let client: any SessionClient
        let preferencesStore: PreferencesStore
        let presetStore: PresetStore
        if let scenario = SessionUITestScenario(arguments: ProcessInfo.processInfo.arguments) {
            client = SessionScenarioClient(scenario: scenario)
            // UI tests must not inherit user presets or panel visibility from a
            // previous manual launch. A single fixed suite, cleared on launch,
            // avoids accumulating one plist per run in ~/Library/Preferences.
            let suiteName = "serial-monitor.ui-test"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            preferencesStore = PreferencesStore(defaults: defaults, key: "preferences")
            presetStore = PresetStore(defaults: defaults, key: "presets")
            // A deterministic log directory lets the logging toggle run without
            // presenting a blocking NSOpenPanel during automation.
            var testPreferences = preferencesStore.load()
            testPreferences.logDirectoryPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("serial-monitor-ui-test-logs", isDirectory: true)
                .path
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-ui-testing-font-scale"),
               arguments.indices.contains(index + 1),
               let scale = AppFontScale(rawValue: arguments[index + 1]) {
                testPreferences.fontScale = scale
            }
            preferencesStore.save(testPreferences)
        } else {
            client = SessionCoordinator(serialPort: POSIXSerialPortAdapter(), logService: FileLogService())
            preferencesStore = PreferencesStore()
            presetStore = PresetStore()
        }
        _model = StateObject(wrappedValue: SessionViewModel(client: client, preferencesStore: preferencesStore, presetStore: presetStore))
    }

    var body: some Scene {
        WindowGroup(L10n.appName) {
            SessionView(model: model)
                .preferredColorScheme(model.appearance.colorScheme)
                .environment(\.appFontScale, model.fontScale)
        }
        .defaultSize(width: 1_280, height: 760)
        .commands { SessionCommands(model: model) }

        Settings {
            SettingsView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 560)
    }
}

private struct SessionCommands: Commands {
    @ObservedObject var model: SessionViewModel

    var body: some Commands {
        CommandMenu("会话") {
            Button("刷新端口") { model.refreshPorts() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isConfigurationLocked)
            Button(model.isConnected ? "断开" : "连接") { model.connectOrDisconnect() }
                .keyboardShortcut("k", modifiers: .command)
        }
        CommandMenu("发送") {
            Button("发送当前内容") { model.sendCurrentText() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canSend)
            Button(model.isAutoSending ? "停止循环" : "开始循环") {
                model.isAutoSending ? model.stopAutoSend() : model.startEditorAutoSend()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.isAutoSending ? false : !model.canSend)
        }
        CommandMenu("日志") {
            Button(logTitle) { model.toggleLogging() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
        CommandMenu("视图") {
            Button(model.isPaused ? "恢复显示" : "暂停显示") { model.togglePause() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("清空记录") { model.clearRecords() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.visibleRecords.isEmpty)
            Divider()
            Button(model.showsPresets ? "隐藏预设" : "显示预设") { model.showsPresets.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .option])
        }
    }

    private var logTitle: String {
        if case .recording = model.logStatus { return "停止记录" }
        return "开始记录"
    }
}
