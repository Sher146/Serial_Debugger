import SwiftUI
import SerialCore

@main
struct SerialMonitorApp: App {
    private let environment: SessionEnvironment
    @StateObject private var windows = SessionWindowRegistry()

    init() {
        environment = SessionEnvironment.bootstrap(arguments: ProcessInfo.processInfo.arguments)
    }

    var body: some Scene {
        WindowGroup(L10n.appName) {
            SessionWindowView(environment: environment, registry: windows)
        }
        .defaultSize(width: 1_280, height: 760)
        .commands { SessionCommands() }

        Settings {
            SettingsHost(registry: windows)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 560)
    }
}

/// 命令始终作用于聚焦窗口的会话，而不是某个全局单例。
private struct SessionCommands: Commands {
    @FocusedObject private var model: SessionViewModel?

    var body: some Commands {
        CommandMenu("会话") {
            Button("刷新端口") { model?.refreshPorts() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model == nil || model?.isConfigurationLocked == true)
            Button(model?.isConnected == true ? "断开" : "连接") { model?.connectOrDisconnect() }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(model == nil)
        }
        CommandMenu("发送") {
            Button("发送当前内容") { model?.sendCurrentText() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model?.canSend != true)
            Button(model?.isAutoSending == true ? "停止循环" : "开始循环") {
                guard let model else { return }
                model.isAutoSending ? model.stopAutoSend() : model.startEditorAutoSend()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model?.isAutoSending != true && model?.canSend != true)
        }
        CommandMenu("日志") {
            Button(logTitle) { model?.toggleLogging() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(model == nil)
        }
        CommandMenu("视图") {
            Button(model?.isPaused == true ? "恢复显示" : "暂停显示") { model?.togglePause() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(model == nil)
            Button("清空记录") { model?.clearRecords() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model?.visibleRecords.isEmpty != false)
            Divider()
            Button(model?.showsPresets == true ? "隐藏预设" : "显示预设") {
                model?.showsPresets.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(model == nil)
        }
    }

    private var logTitle: String {
        if case .recording? = model?.logStatus { return "停止记录" }
        return "开始记录"
    }
}
