import SwiftUI
import SerialCore

struct SessionView: View {
    @ObservedObject var model: SessionViewModel

    var body: some View {
        VStack(spacing: 0) {
            workspace
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .clipped()
            Divider()
            SendEditor(model: model)
                .frame(height: 188)

            Divider()
            SessionStatusBar(model: model)
                .frame(height: 28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowMinimumSizeBridge(minimumSize: NSSize(width: 1_120, height: 680)))
        .toolbar { SessionToolbarContent(model: model) }
        .task { model.start() }
        .onDisappear { model.shutdown() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.workspace")
    }

    @ViewBuilder
    private var workspace: some View {
        if model.showsPresets {
            HSplitView {
                ReceiveConsole(model: model)
                    .frame(minWidth: 700)
                PresetInspector(model: model)
                    .frame(minWidth: 220, idealWidth: 250, maxWidth: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ReceiveConsole(model: model)
        }
    }
}

private struct SessionToolbarContent: ToolbarContent {
    @ObservedObject var model: SessionViewModel
    @State private var showsAdvancedParameters = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Image(systemName: "cable.connector")
                .imageScale(.large)
                .accessibilityLabel(L10n.appName)
                .accessibilityIdentifier("session.title")
        }

        ToolbarItemGroup(placement: .automatic) {
            Picker(L10n.port, selection: $model.configuration.path) {
                if model.ports.isEmpty {
                    Text("—").tag("")
                }
                ForEach(model.ports) { port in
                    Text(port.displayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(port.path)
                        .tag(port.path)
                }
            }
            .labelsHidden()
            // NSToolbar compresses flexible SwiftUI frames to its 100 pt
            // default. A fixed width keeps long `/dev/cu.*` labels usable.
            .frame(width: DesignTokens.toolbarPortPickerWidth)
            .controlSize(.large)
            .disabled(model.isConfigurationLocked)
            .accessibilityLabel(L10n.port)
            .accessibilityIdentifier("session.port-picker")
            .help(model.configuration.path.isEmpty ? L10n.port : model.configuration.path)

            Button(L10n.refresh, systemImage: "arrow.clockwise") { model.refreshPorts() }
                .labelStyle(.iconOnly)
                .toolbarIconControl()
                .disabled(model.isConfigurationLocked)
                .accessibilityLabel(L10n.refresh)
                .accessibilityIdentifier("session.refresh")

            Picker(L10n.baudRate, selection: $model.configuration.baudRate) {
                ForEach(BaudRateCatalog.rates(including: model.configuration.baudRate), id: \.self) { rate in
                    Text(BaudRateCatalog.label(for: rate)).tag(rate)
                }
            }
            .labelsHidden()
            .frame(width: 124)
            .controlSize(.large)
            .disabled(model.isConfigurationLocked)
            .accessibilityLabel(L10n.baudRate)
            .accessibilityIdentifier("session.baud-rate")
            .accessibilityValue(BaudRateCatalog.label(for: model.configuration.baudRate))

            Button(parameterSummary, systemImage: "slider.horizontal.3") {
                showsAdvancedParameters.toggle()
            }
                .toolbarIconControl()
                .disabled(model.isConfigurationLocked)
                .popover(isPresented: $showsAdvancedParameters, arrowEdge: .bottom) {
                    AdvancedParametersPopover(configuration: $model.configuration)
                        .padding(DesignTokens.standardSpacing)
                        .sessionGlass(cornerRadius: DesignTokens.containerCornerRadius)
                }
                .accessibilityLabel(L10n.parameters)
                .accessibilityIdentifier("session.parameters")
                .help(L10n.advancedParameters)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            SessionStatusBadge(state: model.sessionState, title: model.statusTitle)
            Button(L10n.presets, systemImage: "sidebar.trailing") { model.showsPresets.toggle() }
                .toolbarIconControl()
                .accessibilityIdentifier("session.presets-toggle")
                .help(model.showsPresets ? "隐藏预设检查器" : "显示预设检查器")

            Button(logButtonTitle, systemImage: logSymbol) { model.toggleLogging() }
                .toolbarIconControl()
                .accessibilityIdentifier("log.toggle")
                .help(logButtonTitle)

            Button(connectionButtonTitle) { model.connectOrDisconnect() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(connectionButtonTint)
                .accessibilityIdentifier("session.connect-button")
        }
    }

    private var parameterSummary: String {
        let parity: String
        switch model.configuration.parity {
        case .none: parity = "N"
        case .even: parity = "E"
        case .odd: parity = "O"
        }
        return "\(model.configuration.dataBits.rawValue)\(parity)\(model.configuration.stopBits.rawValue)"
    }

    private var connectionButtonTitle: String {
        switch model.sessionState {
        case .disconnected: L10n.connect
        case .opening: L10n.cancel
        case .connected, .closing: L10n.disconnect
        case .error: L10n.reconnect
        }
    }

    private var connectionButtonTint: Color {
        switch model.sessionState {
        case .connected, .closing: .sessionError
        case .opening: .sessionAttention
        case .disconnected, .error: .accentColor
        }
    }

    private var logButtonTitle: String {
        if case .recording = model.logStatus { return "停止记录" }
        return "开始记录"
    }

    private var logSymbol: String {
        if case .recording = model.logStatus { return "stop.circle.fill" }
        return "record.circle"
    }
}

private struct SessionStatusBadge: View {
    let state: SessionState
    let title: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbolName)
                .symbolRenderingMode(.hierarchical)
        }
        .font(DesignTokens.statusFont)
        .foregroundStyle(color)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityState)
        .accessibilityIdentifier("session.connection-status")
    }

    private var color: Color {
        switch state {
        case .connected: .sessionConnected
        case .opening, .closing: .sessionAttention
        case .error: .sessionError
        case .disconnected: .secondary
        }
    }

    private var symbolName: String {
        switch state {
        case .connected: "checkmark.circle.fill"
        case .opening, .closing: "arrow.triangle.2.circlepath.circle.fill"
        case .error: "exclamationmark.circle.fill"
        case .disconnected: "circle.fill"
        }
    }

    private var accessibilityState: String {
        switch state {
        case .disconnected: "disconnected"
        case .opening: "opening"
        case .connected: "connected"
        case .closing: "closing"
        case .error: "error"
        }
    }
}

private struct AdvancedParametersPopover: View {
    @Binding var configuration: SerialConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.standardSpacing) {
            Text(L10n.advancedParameters).font(.headline)
            Picker(L10n.dataBits, selection: $configuration.dataBits) {
                ForEach(SerialConfiguration.DataBits.allCases, id: \.self) { bits in Text("\(bits.rawValue)").tag(bits) }
            }
            .accessibilityIdentifier("session.data-bits")
            Picker(L10n.parity, selection: $configuration.parity) {
                ForEach(SerialConfiguration.Parity.allCases, id: \.self) { parity in Text(parity.rawValue.uppercased()).tag(parity) }
            }
            .accessibilityIdentifier("session.parity")
            Picker(L10n.stopBits, selection: $configuration.stopBits) {
                ForEach(SerialConfiguration.StopBits.allCases, id: \.self) { bits in Text("\(bits.rawValue)").tag(bits) }
            }
            .accessibilityIdentifier("session.stop-bits")
            Picker(L10n.flowControl, selection: $configuration.flowControl) {
                ForEach(SerialConfiguration.FlowControl.allCases, id: \.self) { flow in
                    Text(flow == .none ? L10n.none : L10n.hardware).tag(flow)
                }
            }
            .accessibilityIdentifier("session.flow-control")
        }
        .frame(width: 220)
        .accessibilityIdentifier("session.advanced-parameters")
    }
}

private struct ReceiveConsole: View {
    @ObservedObject var model: SessionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ConsoleToolbar(model: model)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            if model.isPaused {
                HStack {
                    Image(systemName: "pause.circle.fill")
                    Text(L10n.pausedBanner)
                    Spacer()
                    Button(L10n.resume) { model.togglePause() }
                }
                .font(.subheadline)
                .foregroundStyle(Color.sessionAttention)
                .padding(.horizontal, DesignTokens.standardSpacing)
                .padding(.vertical, 6)
                .background(Color.sessionAttention.opacity(0.1))
                .zIndex(1)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("console.paused-banner")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if model.visibleRecords.isEmpty {
                            VStack(spacing: DesignTokens.compactSpacing) {
                                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                                    .font(.title3)
                                Text(L10n.noRecords)
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 280)
                        } else {
                            ForEach(model.visibleRecords) { record in
                                ConsoleRecordRow(
                                    record: record,
                                    format: model.receiveFormat,
                                    showsTimestamp: model.showsTimestamps,
                                    textEncoding: model.textEncoding,
                                    hexPresentation: model.hexPresentation,
                                    fontSize: model.consoleFontSize,
                                    lineSpacing: model.consoleLineSpacing.points
                                )
                                    .id(record.id)
                            }
                        }
                    }
                    .padding(.vertical, DesignTokens.compactSpacing)
                }
                .background(Color.consoleSurface)
                .onChange(of: model.visibleRecords.count) { _, _ in
                    guard model.followsLatest, !model.isPaused, let id = model.visibleRecords.last?.id else { return }
                    if reduceMotion {
                        proxy.scrollTo(id, anchor: .bottom)
                    } else {
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("console.records")
    }
}

private struct ConsoleToolbar: View {
    @ObservedObject var model: SessionViewModel

    var body: some View {
        HStack(spacing: DesignTokens.compactSpacing) {
            Text(L10n.records).font(.subheadline.weight(.semibold))
            ToolbarSeparator()
            ControlGroup {
                Button(model.isPaused ? L10n.resume : L10n.pause, systemImage: model.isPaused ? "play.fill" : "pause.fill") { model.togglePause() }
                    .toolbarIconControl()
                    .accessibilityIdentifier("console.pause")
                    .help(model.isPaused ? L10n.resume : L10n.pause)
                Button(L10n.clear, systemImage: "trash") { model.clearRecords() }
                    .toolbarIconControl()
                    .disabled(model.visibleRecords.isEmpty)
                    .accessibilityIdentifier("console.clear")
                    .help(L10n.clear)
            }
            ToolbarSeparator()
            Picker("", selection: $model.receiveFormat) {
                Text("ASCII").tag(DisplayFormat.ascii)
                Text("HEX").tag(DisplayFormat.hex)
            }
            .pickerStyle(.segmented)
            .frame(width: 112)
            .controlSize(.large)
            .accessibilityLabel("接收显示格式")
            .accessibilityIdentifier("console.display-format")
            Toggle(L10n.timestamp, isOn: $model.showsTimestamps)
                .toggleStyle(.button)
                .controlSize(.large)
                .accessibilityIdentifier("console.timestamps")
            Toggle(L10n.follow, isOn: $model.followsLatest)
                .toggleStyle(.button)
                .controlSize(.large)
                .accessibilityIdentifier("console.follow")
            Spacer()
            Text("\(model.visibleRecords.count) 条")
                .foregroundStyle(.secondary)
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, DesignTokens.standardSpacing)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct ConsoleRecordRow: View {
    let record: CommunicationRecord
    let format: DisplayFormat
    let showsTimestamp: Bool
    let textEncoding: TextEncodingPreference
    let hexPresentation: HexPresentation
    let fontSize: Double
    let lineSpacing: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.compactSpacing) {
            if showsTimestamp {
                Text(record.timestamp, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                    .foregroundStyle(.secondary)
            }
            Text(record.direction.rawValue)
                .foregroundStyle(record.direction == .received ? Color.sessionConnected : Color.accentColor)
                .fontWeight(.semibold)
            Text(RecordFormatter.string(for: record, format: format, textEncoding: textEncoding, hexPresentation: hexPresentation))
                .textSelection(.enabled)
            if case .failed(let error)? = record.sendResult {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.sessionError)
                    .help(error.localizedDescription)
            }
        }
        .font(.system(size: fontSize, weight: .regular, design: .monospaced))
        .lineSpacing(lineSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.standardSpacing)
        .padding(.vertical, 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(record.direction.rawValue) \(RecordFormatter.string(for: record, format: format, textEncoding: textEncoding, hexPresentation: hexPresentation))")
        .accessibilityIdentifier(recordAccessibilityIdentifier)
    }

    private var recordAccessibilityIdentifier: String {
        let bytes = record.rawBytes.map { String(format: "%02X", $0) }.joined()
        return "console.record.\(record.direction.rawValue).\(bytes)"
    }
}

private struct SendEditor: View {
    @ObservedObject var model: SessionViewModel
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.compactSpacing) {
                Text(L10n.send).font(.subheadline.weight(.semibold))
                ToolbarSeparator()
                Picker("", selection: $model.sendFormat) {
                    Text("ASCII").tag(DisplayFormat.ascii)
                    Text("HEX").tag(DisplayFormat.hex)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .accessibilityLabel("发送格式")
                .accessibilityIdentifier("send.format")
                Picker(L10n.lineEnding, selection: $model.lineEnding) {
                    Text(L10n.none).tag(LineEnding.none)
                    Text("CR").tag(LineEnding.cr)
                    Text("LF").tag(LineEnding.lf)
                    Text("CRLF").tag(LineEnding.crlf)
                }
                .frame(width: 120)
                .accessibilityIdentifier("send.line-ending")
                Spacer()
            }
            .padding(.horizontal, DesignTokens.standardSpacing)
            .frame(height: 36)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .background(.bar)

            HStack(alignment: .bottom, spacing: DesignTokens.standardSpacing) {
                TextEditor(text: $model.sendText)
                    .font(.system(size: model.consoleFontSize, weight: .regular, design: .monospaced))
                    .focused($editorFocused)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(minHeight: 82, maxHeight: 110)
                    .background(Color.consoleSurface)
                    .overlay {
                        Rectangle().stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        if model.sendText.isEmpty {
                            Text(model.isConnected ? L10n.sendPlaceholder : L10n.connectToSend)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }
                    .disabled(!model.isConnected)
                    .accessibilityLabel(L10n.send)
                    .accessibilityIdentifier("send.editor")

                Button(L10n.send, systemImage: "paperplane.fill") {
                    model.sendCurrentText()
                    editorFocused = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canSend)
                .accessibilityIdentifier("send.button")
            }
            .padding(.horizontal, DesignTokens.standardSpacing)
            .padding(.vertical, 8)

            HStack(spacing: DesignTokens.compactSpacing) {
                Label("自动发送", systemImage: "repeat")
                    .font(.caption.weight(.semibold))
                TextField("间隔 ms", value: $model.autoIntervalMilliseconds, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 96)
                    .accessibilityIdentifier("auto-send.interval")
                TextField("次数（留空无限）", text: $model.autoRepetitionCountText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 132)
                    .accessibilityIdentifier("auto-send.count")
                Button(model.isAutoSending ? "停止循环" : "开始循环") {
                    model.isAutoSending ? model.stopAutoSend() : model.startEditorAutoSend()
                }
                .disabled(model.isAutoSending ? false : !model.canSend)
                .accessibilityIdentifier("auto-send.toggle")
                if case .running(_, let remaining) = model.autoSendStatus {
                    Text(remaining.map { "剩余 \($0) 次" } ?? "持续发送中")
                        .font(.caption)
                        .foregroundStyle(Color.sessionConnected)
                        .accessibilityIdentifier("auto-send.status")
                }
                Spacer()
            }
            .padding(.horizontal, DesignTokens.standardSpacing)
            .padding(.bottom, 6)

            if let error = model.sendValidationError {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.sessionError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignTokens.standardSpacing)
                    .padding(.bottom, DesignTokens.compactSpacing)
                    .accessibilityIdentifier("send.validation-error")
            }
        }
        .background(Color.consoleSurface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("send.editor-container")
    }
}

private struct PresetInspector: View {
    @ObservedObject var model: SessionViewModel
    @State private var editor: PresetEditorState?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(L10n.presets, systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("新增", systemImage: "plus") {
                    editor = PresetEditorState()
                }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("presets.add")
            }
            .padding(.horizontal, DesignTokens.standardSpacing)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            if model.presets.isEmpty {
                VStack(spacing: DesignTokens.compactSpacing) {
                    ContentUnavailableView("暂无预设", systemImage: "tray", description: Text("新建后可单次发送或循环发送"))
                    Text("预设检查器为空")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("presets.placeholder")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.presets) { preset in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(preset.name).font(.subheadline.weight(.semibold))
                        Text("\(preset.format.rawValue.uppercased()) · \(preset.lineEnding.rawValue.uppercased())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("发送") { model.sendPreset(preset) }
                                .disabled(!model.isConnected)
                            Button(model.isAutoSending ? "停止" : "循环") {
                                model.isAutoSending ? model.stopAutoSend() : model.startPresetAutoSend(preset)
                            }
                            .disabled(!model.isConnected && !model.isAutoSending)
                            Button("编辑") { editor = PresetEditorState(preset: preset) }
                            Button("删除", role: .destructive) { model.deletePreset(preset) }
                                .accessibilityIdentifier("presets.delete.\(preset.id.uuidString)")
                        }
                        .buttonStyle(.borderless)
                    }
                    .contextMenu {
                        Button("删除", role: .destructive) { model.deletePreset(preset) }
                    }
                    .accessibilityElement(children: .contain)
                }
                .listStyle(.plain)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("presets.inspector")
        .sheet(item: $editor) { state in
            PresetEditorSheet(state: state, model: model)
        }
    }
}

private struct PresetEditorState: Identifiable {
    let id: UUID
    let presetID: UUID?
    var name: String
    var content: String
    var format: DisplayFormat
    var lineEnding: LineEnding

    init(preset: PresetSnapshot? = nil) {
        id = preset?.id ?? UUID()
        presetID = preset?.id
        name = preset?.name ?? ""
        content = preset?.content ?? ""
        format = preset?.format ?? .ascii
        lineEnding = preset?.lineEnding ?? .crlf
    }
}

private struct PresetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var state: PresetEditorState
    @ObservedObject var model: SessionViewModel
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.standardSpacing) {
            Text(state.presetID == nil ? "新建预设" : "编辑预设").font(.headline)
            TextField("名称", text: $state.name).accessibilityIdentifier("presets.editor.name")
            Picker("格式", selection: $state.format) {
                Text("ASCII").tag(DisplayFormat.ascii)
                Text("HEX").tag(DisplayFormat.hex)
            }
            Picker(L10n.lineEnding, selection: $state.lineEnding) {
                Text(L10n.none).tag(LineEnding.none)
                Text("CR").tag(LineEnding.cr)
                Text("LF").tag(LineEnding.lf)
                Text("CRLF").tag(LineEnding.crlf)
            }
            TextEditor(text: $state.content)
                .font(DesignTokens.consoleFont)
                .frame(minHeight: 120)
                .overlay { Rectangle().stroke(Color(nsColor: .separatorColor)) }
                .accessibilityIdentifier("presets.editor.content")
            if let error { Text(error).font(.caption).foregroundStyle(Color.sessionError) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    if let validationError = model.savePreset(id: state.presetID, name: state.name, content: state.content, format: state.format, lineEnding: state.lineEnding) {
                        error = validationError.localizedDescription
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("presets.editor.save")
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct SessionStatusBar: View {
    @ObservedObject var model: SessionViewModel

    var body: some View {
        HStack(spacing: DesignTokens.standardSpacing) {
            Label(portSummary, systemImage: "cable.connector")
            Divider()
            Text("RX \(formattedBytes(model.statistics?.receivedByteCount ?? 0))")
                .foregroundStyle(Color.sessionConnected)
                .accessibilityIdentifier("status.rx")
                .accessibilityValue("\(model.statistics?.receivedByteCount ?? 0)")
            Text("TX \(formattedBytes(model.statistics?.transmittedByteCount ?? 0))")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("status.tx")
                .accessibilityValue("\(model.statistics?.transmittedByteCount ?? 0)")
            Divider()
            Text("\(model.statistics?.recordCount ?? 0) 条 · \(formattedBytes(model.statistics?.storedByteCount ?? 0))")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("status.records")
                .accessibilityValue("\(model.statistics?.recordCount ?? 0)")
            if let statistics = model.statistics, statistics.truncationCount > 0 {
                Text("已截断 \(statistics.truncationCount) 次").foregroundStyle(Color.sessionAttention)
            }
            Spacer()
            Label(logTitle, systemImage: "record.circle")
                .foregroundStyle(logColor)
                .accessibilityIdentifier("status.log")
                .accessibilityValue(logStateValue)
            if let error = model.latestError {
                Divider()
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.sessionError)
                    .lineLimit(1)
                    .accessibilityIdentifier("status.error")
            }
        }
        .font(.caption)
        .padding(.horizontal, DesignTokens.standardSpacing)
        .frame(height: 26)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.status-bar")
    }

    private var portSummary: String {
        let path = model.configuration.path.isEmpty ? L10n.disconnected : URL(fileURLWithPath: model.configuration.path).lastPathComponent
        return "\(path) · \(model.configuration.baudRate)"
    }

    private var logTitle: String {
        switch model.logStatus {
        case .inactive: L10n.logInactive
        case .recording: L10n.logRecording
        case .failed: L10n.connectionError
        }
    }

    private var logColor: Color {
        if case .recording = model.logStatus { return .sessionConnected }
        if case .failed = model.logStatus { return .sessionError }
        return .secondary
    }

    private var logStateValue: String {
        switch model.logStatus {
        case .inactive: "inactive"
        case .recording: "recording"
        case .failed: "failed"
        }
    }

    private func formattedBytes(_ count: Int) -> String {
        if count < 1_024 { return "\(count) B" }
        if count < 1_024 * 1_024 { return String(format: "%.1f KB", Double(count) / 1_024) }
        return String(format: "%.1f MB", Double(count) / (1_024 * 1_024))
    }
}

private struct ToolbarSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1, height: 16)
            .accessibilityHidden(true)
    }
}

private extension View {
    func toolbarIconControl() -> some View {
        controlSize(.large)
            .imageScale(.large)
            .frame(minWidth: DesignTokens.toolbarIconTargetSize, minHeight: DesignTokens.toolbarIconTargetSize)
    }
}

#Preview("Disconnected") {
    SessionView(model: SessionViewModel(client: SessionPreviewClient(state: .disconnected)))
}

#Preview("Opening") {
    SessionView(model: SessionViewModel(client: SessionPreviewClient(state: .opening(SerialConfiguration(path: "/dev/cu.usbserial-demo")))))
}

#Preview("Connected") {
    SessionView(model: SessionViewModel(client: SessionPreviewClient(
        state: .connected(SerialConfiguration(path: "/dev/cu.usbserial-demo")),
        records: [
            CommunicationRecord(direction: .received, rawBytes: Data("ready\\r\\n".utf8), displayFormat: .ascii),
            CommunicationRecord(direction: .transmitted, rawBytes: Data("AT+RST\\r\\n".utf8), displayFormat: .ascii, source: .manual, sendResult: .sent)
        ]
    )))
}

#Preview("Error") {
    SessionView(model: SessionViewModel(client: SessionPreviewClient(state: .error(.unexpected("端口已被占用")))))
}
