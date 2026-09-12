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
            // previous manual launch.
            let defaults = UserDefaults(suiteName: "serial-monitor.ui-test.\(UUID().uuidString)")!
            preferencesStore = PreferencesStore(defaults: defaults, key: "preferences")
            presetStore = PresetStore(defaults: defaults, key: "presets")
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
        }
        .defaultSize(width: 1_180, height: 760)
        .windowToolbarStyle(.unifiedCompact)
        .commands { SessionCommands(model: model) }

        Settings {
            SettingsView(model: model)
        }
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

private struct SettingsView: View {
    @ObservedObject var model: SessionViewModel

    var body: some View {
        Form {
            Section("默认串口参数") {
                TextField("波特率", value: $model.configuration.baudRate, format: .number)
                Picker("数据位", selection: $model.configuration.dataBits) {
                    ForEach(SerialConfiguration.DataBits.allCases, id: \.self) { Text("\($0.rawValue)").tag($0) }
                }
                Picker("校验", selection: $model.configuration.parity) {
                    ForEach(SerialConfiguration.Parity.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }
                Picker("停止位", selection: $model.configuration.stopBits) {
                    ForEach(SerialConfiguration.StopBits.allCases, id: \.self) { Text("\($0.rawValue)").tag($0) }
                }
                Picker("流控制", selection: $model.configuration.flowControl) {
                    ForEach(SerialConfiguration.FlowControl.allCases, id: \.self) { Text($0.rawValue == "none" ? "无" : "硬件").tag($0) }
                }
            }
            Section("显示与发送") {
                Picker("接收格式", selection: $model.receiveFormat) {
                    Text("ASCII").tag(DisplayFormat.ascii); Text("HEX").tag(DisplayFormat.hex)
                }
                Picker("发送格式", selection: $model.sendFormat) {
                    Text("ASCII").tag(DisplayFormat.ascii); Text("HEX").tag(DisplayFormat.hex)
                }
                Picker("默认行结束符", selection: $model.lineEnding) {
                    Text("无").tag(LineEnding.none); Text("CR").tag(LineEnding.cr); Text("LF").tag(LineEnding.lf); Text("CRLF").tag(LineEnding.crlf)
                }
                Toggle("显示时间戳", isOn: $model.showsTimestamps)
                Toggle("自动跟随", isOn: $model.followsLatest)
                Toggle("显示预设检查器", isOn: $model.showsPresets)
            }
            Section("日志") {
                TextField("文件名前缀", text: $model.logFileNamePrefix)
                Text("开始记录时可选择或复用本机日志目录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 440)
        .accessibilityIdentifier("settings.window")
    }
}
