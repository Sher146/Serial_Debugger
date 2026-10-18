import SwiftUI
import SerialCore

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, display, format, retention, logging, session

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "常规"
        case .display: "显示与可读性"
        case .format: "数据格式"
        case .retention: "数据保留"
        case .logging: "日志"
        case .session: "会话与预设"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .display: "textformat.size"
        case .format: "chevron.left.forwardslash.chevron.right"
        case .retention: "internaldrive"
        case .logging: "doc.text"
        case .session: "cable.connector"
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var model: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: SettingsSection? = .general
    @State private var draft: AppPreferences
    @State private var baseline: AppPreferences
    @State private var confirmsReset = false

    init(model: SessionViewModel) {
        _model = ObservedObject(wrappedValue: model)
        let preferences = model.settingsDraft()
        _draft = State(initialValue: preferences)
        _baseline = State(initialValue: preferences)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.appName)
                    .appFont(.title, weight: .bold)
                    .padding(.horizontal, DesignTokens.contentInset)
                    .padding(.vertical, 16)

                List(SettingsSection.allCases, selection: $selection) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .padding(.top, 44)
            .frame(width: 200)
            .frame(maxHeight: .infinity)
            .background(colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.94))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings.sidebar")

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text((selection ?? .general).title)
                    .appFont(.title, weight: .bold)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 4)

                Form {
                    switch selection ?? .general {
                    case .general: general
                    case .display: display
                    case .format: format
                    case .retention: retention
                    case .logging: logging
                    case .session: session
                    }
                }
                .formStyle(.grouped)

                actionBar
            }
            .padding(.top, 44)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 760)
        .frame(minHeight: 560, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .vertical)
        .preferredColorScheme(model.appearance.colorScheme)
        .environment(\.appFontScale, model.fontScale)
        .onAppear(perform: reloadDraft)
        .background(SettingsWindowConfigurationBridge())
        .background(UITestWindowPlacementBridge())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.window")
        .alert("恢复默认设置？", isPresented: $confirmsReset) {
            Button("取消", role: .cancel) {}
            Button("恢复默认") { draft = AppPreferences() }
        } message: {
            Text("默认值会先写入草稿；点击“保存”后才会还原设置和日志目录权限。预设、日志文件与当前记录不会删除。")
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("取消") { dismiss() }
                .accessibilityIdentifier("settings.cancel")
            Button("保存") {
                model.applySettings(draft)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(draft == baseline)
            .accessibilityIdentifier("settings.save")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var general: some View {
        Group {
            Section("外观") {
                Picker("外观模式", selection: $draft.appearance) {
                    Text("跟随系统").tag(AppAppearance.system)
                    Text("浅色").tag(AppAppearance.light)
                    Text("深色").tag(AppAppearance.dark)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.appearance")
                Picker("全局字体大小", selection: $draft.fontScale) {
                    Text("特小").tag(AppFontScale.xSmall)
                    Text("小").tag(AppFontScale.small)
                    Text("标准").tag(AppFontScale.standard)
                    Text("大").tag(AppFontScale.large)
                    Text("特大").tag(AppFontScale.xLarge)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.font-scale")
            }
            Section("恢复") {
                Button("恢复默认设置…", role: .destructive) { confirmsReset = true }
                    .accessibilityIdentifier("settings.reset")
                Text("恢复默认只会在点击保存后生效。")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var display: some View {
        Group {
            Section("控制台") {
                Picker("行距", selection: $draft.consoleLineSpacing) {
                    Text("紧凑").tag(ConsoleLineSpacing.compact)
                    Text("标准").tag(ConsoleLineSpacing.standard)
                    Text("宽松").tag(ConsoleLineSpacing.relaxed)
                }
                .accessibilityIdentifier("settings.console-line-spacing")
            }
            Section("工作区") {
                Toggle("显示时间戳", isOn: $draft.showsTimestamps)
                Toggle("自动跟随最新数据", isOn: $draft.followsLatest)
                Toggle("显示预设检查器", isOn: $draft.showsPresets)
            }
        }
    }

    private var format: some View {
        Group {
            Section("默认格式") {
                Picker("接收格式", selection: $draft.receiveFormat) {
                    Text("ASCII").tag(DisplayFormat.ascii)
                    Text("HEX").tag(DisplayFormat.hex)
                }
                Picker("发送格式", selection: $draft.sendFormat) {
                    Text("ASCII").tag(DisplayFormat.ascii)
                    Text("HEX").tag(DisplayFormat.hex)
                }
                Picker("默认行结束符", selection: $draft.lineEnding) {
                    Text("无").tag(LineEnding.none)
                    Text("CR").tag(LineEnding.cr)
                    Text("LF").tag(LineEnding.lf)
                    Text("CRLF").tag(LineEnding.crlf)
                }
            }
            Section("文本与 HEX") {
                Picker("文本编码", selection: $draft.textEncoding) {
                    Text("UTF-8").tag(TextEncodingPreference.utf8)
                    Text("GB18030").tag(TextEncodingPreference.gb18030)
                }
                Picker("HEX 分隔符", selection: $draft.hexPresentation.separator) {
                    Text("空格").tag(HexSeparator.space)
                    Text("无").tag(HexSeparator.none)
                    Text("逗号").tag(HexSeparator.comma)
                }
                Toggle("HEX 使用大写", isOn: $draft.hexPresentation.usesUppercase)
            }
        }
    }

    private var retention: some View {
        Group {
            Section("内存缓存") {
                Picker("最大记录数", selection: $draft.maximumRecords) {
                    Text("10,000 条").tag(10_000)
                    Text("50,000 条").tag(50_000)
                    Text("100,000 条").tag(100_000)
                    Text("200,000 条").tag(200_000)
                }
                Picker("最大缓存大小", selection: $draft.maximumBytes) {
                    Text("4 MB").tag(4 * 1_024 * 1_024)
                    Text("16 MB").tag(16 * 1_024 * 1_024)
                    Text("64 MB").tag(64 * 1_024 * 1_024)
                    Text("128 MB").tag(128 * 1_024 * 1_024)
                }
                Text("降低上限会在保存后从最早记录开始裁剪，原始串口连接不会中断。")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var logging: some View {
        Group {
            Section("默认位置") {
                LabeledContent("日志目录") {
                    Text(model.logDirectoryDescription(for: draft))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("选择目录…") {
                        guard let directory = model.selectSettingsLogDirectory() else { return }
                        draft.logDirectoryPath = directory.path
                        draft.logDirectoryBookmark = directory.bookmark
                    }
                    Button("清除目录", role: .destructive) {
                        draft.logDirectoryPath = nil
                        draft.logDirectoryBookmark = nil
                    }
                    .disabled(draft.logDirectoryPath == nil)
                }
                TextField("文件名前缀", text: $draft.logFileNamePrefix)
            }
            Section("记录策略") {
                Toggle("成功连接后自动记录", isOn: $draft.autoStartLogging)
                Picker("单文件轮转", selection: $draft.logRotationMaximumBytes) {
                    Text("关闭").tag(Optional<Int>.none)
                    Text("5 MB").tag(Optional(5 * 1_024 * 1_024))
                    Text("20 MB").tag(Optional(20 * 1_024 * 1_024))
                    Text("100 MB").tag(Optional(100 * 1_024 * 1_024))
                }
                Text("新策略只会在保存后应用于下一次开始的日志。")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var session: some View {
        Group {
            Section("恢复") {
                Toggle("恢复上次串口配置", isOn: $draft.restoresLastConfiguration)
                Toggle("恢复发送草稿和循环参数", isOn: $draft.restoresSendDraft)
                Text("自动发送只恢复编辑草稿，启动时不会自动开始。")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("默认串口参数") {
                Picker("预设波特率", selection: $draft.defaultConfiguration.baudRate) {
                    ForEach(BaudRateCatalog.rates(including: draft.defaultConfiguration.baudRate), id: \.self) { rate in
                        Text(BaudRateCatalog.label(for: rate)).tag(rate)
                    }
                }
                TextField("自定义波特率", value: $draft.defaultConfiguration.baudRate, format: .number)
                Picker("数据位", selection: $draft.defaultConfiguration.dataBits) {
                    ForEach(SerialConfiguration.DataBits.allCases, id: \.self) { Text("\($0.rawValue)").tag($0) }
                }
                Picker("校验", selection: $draft.defaultConfiguration.parity) {
                    ForEach(SerialConfiguration.Parity.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }
                Picker("停止位", selection: $draft.defaultConfiguration.stopBits) {
                    ForEach(SerialConfiguration.StopBits.allCases, id: \.self) { Text("\($0.rawValue)").tag($0) }
                }
                Picker("流控制", selection: $draft.defaultConfiguration.flowControl) {
                    ForEach(SerialConfiguration.FlowControl.allCases, id: \.self) { Text($0.rawValue == "none" ? "无" : "硬件").tag($0) }
                }
            }
            .disabled(model.isConfigurationLocked)
            Section("预设") {
                Text("当前共有 \(model.presets.count) 条预设；可在主窗口的预设检查器中创建、编辑与发送。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func reloadDraft() {
        let preferences = model.settingsDraft()
        draft = preferences
        baseline = preferences
    }
}

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
