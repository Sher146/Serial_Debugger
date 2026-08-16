import SwiftUI
import SerialCore

struct SessionView: View {
    @StateObject private var model: SessionViewModel
    @State private var showsPresets = true

    init(client: any SessionClient) {
        _model = StateObject(wrappedValue: SessionViewModel(client: client))
    }

    var body: some View {
        VStack(spacing: 0) {
            SessionToolbar(model: model, showsPresets: $showsPresets)
                .padding(DesignTokens.compactSpacing)
                .sessionGlass(cornerRadius: DesignTokens.panelCornerRadius)
                .padding([.horizontal, .top], DesignTokens.compactSpacing)

            HStack(spacing: DesignTokens.compactSpacing) {
                VStack(spacing: 0) {
                    ReceiveConsole(model: model)
                    SendEditor(model: model)
                }
                .background(Color.consoleSurface, in: RoundedRectangle(cornerRadius: DesignTokens.containerCornerRadius, style: .continuous))

                if showsPresets {
                    PresetPlaceholder()
                        .frame(minWidth: 220, idealWidth: 250, maxWidth: 280)
                        .sessionGlass(cornerRadius: DesignTokens.panelCornerRadius)
                }
            }
            .padding(DesignTokens.compactSpacing)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            SessionStatusBar(model: model)
                .padding(.horizontal, DesignTokens.compactSpacing)
                .padding(.bottom, DesignTokens.compactSpacing)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowMinimumSizeBridge(minimumSize: NSSize(width: 980, height: 680)))
        .task { model.start() }
        .accessibilityIdentifier("session.workspace")
    }
}

private struct SessionToolbar: View {
    @ObservedObject var model: SessionViewModel
    @Binding var showsPresets: Bool
    @State private var showsAdvancedParameters = false

    private let baudRates = [300, 1_200, 2_400, 4_800, 9_600, 19_200, 38_400, 57_600, 115_200, 230_400]

    var body: some View {
        HStack(spacing: DesignTokens.compactSpacing) {
            Label(L10n.appName, systemImage: "cable.connector")
                .font(.headline)
                .accessibilityIdentifier("session.title")
            Divider()

            Picker(L10n.port, selection: $model.configuration.path) {
                if model.ports.isEmpty {
                    Text("—").tag("")
                }
                ForEach(model.ports) { port in
                    Text(port.displayName).tag(port.path)
                }
            }
            .labelsHidden()
            .frame(minWidth: 150, maxWidth: 220)
            .disabled(model.isConfigurationLocked)
            .accessibilityLabel(L10n.port)
            .accessibilityIdentifier("session.port-picker")

            Button(L10n.refresh, systemImage: "arrow.clockwise") { model.refreshPorts() }
                .labelStyle(.iconOnly)
                .disabled(model.isConfigurationLocked)
                .accessibilityLabel(L10n.refresh)
                .accessibilityIdentifier("session.refresh")

            Picker(L10n.baudRate, selection: $model.configuration.baudRate) {
                ForEach(baudRates, id: \.self) { Text("\($0)").tag($0) }
            }
            .labelsHidden()
            .frame(width: 105)
            .disabled(model.isConfigurationLocked)
            .accessibilityLabel(L10n.baudRate)

            Button(parameterSummary, systemImage: "slider.horizontal.3") { showsAdvancedParameters.toggle() }
                .disabled(model.isConfigurationLocked)
                .popover(isPresented: $showsAdvancedParameters, arrowEdge: .bottom) {
                    AdvancedParametersPopover(configuration: $model.configuration)
                        .padding(DesignTokens.standardSpacing)
                        .sessionGlass(cornerRadius: DesignTokens.containerCornerRadius)
                }
                .accessibilityLabel(L10n.parameters)
                .accessibilityIdentifier("session.parameters")

            SessionStatusBadge(state: model.sessionState, title: model.statusTitle)
            Spacer(minLength: 0)

            Button(L10n.presets, systemImage: "sidebar.trailing") { showsPresets.toggle() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("session.presets-toggle")

            Button(connectionButtonTitle) { model.connectOrDisconnect() }
                .buttonStyle(.borderedProminent)
                .tint(connectionButtonTint)
                .accessibilityIdentifier("session.connect-button")
        }
        .controlSize(.small)
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
}

private struct AdvancedParametersPopover: View {
    @Binding var configuration: SerialConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.standardSpacing) {
            Text(L10n.advancedParameters).font(.headline)
            Picker(L10n.dataBits, selection: $configuration.dataBits) {
                ForEach(SerialConfiguration.DataBits.allCases, id: \.self) { bits in Text("\(bits.rawValue)").tag(bits) }
            }
            Picker(L10n.parity, selection: $configuration.parity) {
                ForEach(SerialConfiguration.Parity.allCases, id: \.self) { parity in Text(parity.rawValue.uppercased()).tag(parity) }
            }
            Picker(L10n.stopBits, selection: $configuration.stopBits) {
                ForEach(SerialConfiguration.StopBits.allCases, id: \.self) { bits in Text("\(bits.rawValue)").tag(bits) }
            }
            Picker(L10n.flowControl, selection: $configuration.flowControl) {
                ForEach(SerialConfiguration.FlowControl.allCases, id: \.self) { flow in
                    Text(flow == .none ? L10n.none : L10n.hardware).tag(flow)
                }
            }
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
            HStack(spacing: DesignTokens.compactSpacing) {
                Text(L10n.records).font(.subheadline.weight(.semibold))
                Divider()
                Button(model.isPaused ? L10n.resume : L10n.pause, systemImage: model.isPaused ? "play.fill" : "pause.fill") { model.togglePause() }
                    .accessibilityIdentifier("console.pause")
                Button(L10n.clear, systemImage: "trash") { model.clearRecords() }
                    .disabled(model.visibleRecords.isEmpty)
                    .accessibilityIdentifier("console.clear")
                Picker("", selection: $model.receiveFormat) {
                    Text("ASCII").tag(DisplayFormat.ascii)
                    Text("HEX").tag(DisplayFormat.hex)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .accessibilityLabel("接收显示格式")
                .accessibilityIdentifier("console.display-format")
                Toggle(L10n.timestamp, isOn: $model.showsTimestamps).toggleStyle(.button)
                Toggle(L10n.follow, isOn: $model.followsLatest).toggleStyle(.button)
                Spacer()
                Text("\(model.visibleRecords.count) 条").foregroundStyle(.secondary).font(.caption.monospacedDigit())
            }
            .padding(DesignTokens.compactSpacing)
            .background(.bar)

            if model.isPaused {
                HStack {
                    Label(L10n.pausedBanner, systemImage: "pause.circle.fill")
                    Spacer()
                    Button(L10n.resume) { model.togglePause() }
                }
                .font(.subheadline)
                .foregroundStyle(Color.sessionAttention)
                .padding(.horizontal, DesignTokens.standardSpacing)
                .padding(.vertical, 6)
                .background(Color.sessionAttention.opacity(0.1))
                .accessibilityIdentifier("console.paused-banner")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if model.visibleRecords.isEmpty {
                            ContentUnavailableView(L10n.noRecords, systemImage: "text.line.first.and.arrowtriangle.forward")
                                .frame(maxWidth: .infinity, minHeight: 280)
                        } else {
                            ForEach(model.visibleRecords) { record in
                                ConsoleRecordRow(record: record, format: model.receiveFormat, showsTimestamp: model.showsTimestamps)
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
        .accessibilityIdentifier("console.records")
    }
}

private struct ConsoleRecordRow: View {
    let record: CommunicationRecord
    let format: DisplayFormat
    let showsTimestamp: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.compactSpacing) {
            if showsTimestamp {
                Text(record.timestamp, format: .dateTime.hour().minute().second().secondFraction(.fractional(3)))
                    .foregroundStyle(.secondary)
            }
            Text(record.direction.rawValue)
                .foregroundStyle(record.direction == .received ? Color.sessionConnected : Color.accentColor)
                .fontWeight(.semibold)
            Text(RecordFormatter.string(for: record, format: format))
                .textSelection(.enabled)
            if case .failed(let error)? = record.sendResult {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.sessionError)
                    .help(error.localizedDescription)
            }
        }
        .font(DesignTokens.consoleFont)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.standardSpacing)
        .padding(.vertical, 2)
        .accessibilityLabel("\(record.direction.rawValue) \(RecordFormatter.string(for: record, format: format))")
    }
}

private struct SendEditor: View {
    @ObservedObject var model: SessionViewModel
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.compactSpacing) {
                Text(L10n.send).font(.subheadline.weight(.semibold))
                Divider()
                Picker("", selection: $model.sendFormat) {
                    Text("ASCII").tag(DisplayFormat.ascii)
                    Text("HEX").tag(DisplayFormat.hex)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .onChange(of: model.sendFormat) { _, _ in model.validateSendText() }
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
            .padding(DesignTokens.compactSpacing)
            .background(.bar)

            HStack(alignment: .bottom, spacing: DesignTokens.standardSpacing) {
                TextEditor(text: $model.sendText)
                    .font(DesignTokens.consoleFont)
                    .focused($editorFocused)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.consoleSurface, in: RoundedRectangle(cornerRadius: DesignTokens.controlCornerRadius, style: .continuous))
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
                    .onChange(of: model.sendText) { _, _ in model.validateSendText() }
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
            .padding(DesignTokens.standardSpacing)

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
        .accessibilityIdentifier("send.editor-container")
    }
}

private struct PresetPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.standardSpacing) {
            Label(L10n.presets, systemImage: "list.bullet.rectangle")
                .font(.headline)
            Divider()
            ContentUnavailableView(L10n.presetsPlaceholder, systemImage: "clock.badge.questionmark")
                .font(.subheadline)
            Spacer()
        }
        .padding(DesignTokens.standardSpacing)
        .accessibilityIdentifier("presets.placeholder")
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
            Text("TX \(formattedBytes(model.statistics?.transmittedByteCount ?? 0))")
                .foregroundStyle(.secondary)
            Divider()
            Text("\(model.statistics?.recordCount ?? 0) 条 · \(formattedBytes(model.statistics?.storedByteCount ?? 0))")
                .foregroundStyle(.secondary)
            if let statistics = model.statistics, statistics.truncationCount > 0 {
                Text("已截断 \(statistics.truncationCount) 次").foregroundStyle(Color.sessionAttention)
            }
            Spacer()
            Label(logTitle, systemImage: "record.circle")
                .foregroundStyle(logColor)
            if let error = model.latestError {
                Divider()
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.sessionError)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .padding(.horizontal, DesignTokens.standardSpacing)
        .padding(.vertical, 7)
        .sessionGlass(cornerRadius: DesignTokens.controlCornerRadius)
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

    private func formattedBytes(_ count: Int) -> String {
        if count < 1_024 { return "\(count) B" }
        if count < 1_024 * 1_024 { return String(format: "%.1f KB", Double(count) / 1_024) }
        return String(format: "%.1f MB", Double(count) / (1_024 * 1_024))
    }
}

#Preview("Disconnected") {
    SessionView(client: SessionPreviewClient(state: .disconnected))
}

#Preview("Opening") {
    SessionView(client: SessionPreviewClient(state: .opening(SerialConfiguration(path: "/dev/cu.usbserial-demo"))))
}

#Preview("Connected") {
    SessionView(client: SessionPreviewClient(
        state: .connected(SerialConfiguration(path: "/dev/cu.usbserial-demo")),
        records: [
            CommunicationRecord(direction: .received, rawBytes: Data("ready\\r\\n".utf8), displayFormat: .ascii),
            CommunicationRecord(direction: .transmitted, rawBytes: Data("AT+RST\\r\\n".utf8), displayFormat: .ascii, source: .manual, sendResult: .sent)
        ]
    ))
}

#Preview("Error") {
    SessionView(client: SessionPreviewClient(state: .error(.unexpected("端口已被占用"))))
}
