import SwiftUI
import AppKit
import SerialCore

struct SessionView: View {
    @ObservedObject var model: SessionViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            workspace
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .clipped()
            SendEditor(model: model)

            SessionStatusBar(model: model)
                .frame(height: 28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowMinimumSizeBridge(minimumSize: NSSize(width: 980, height: 680)))
        .background(TitlebarGlyphBridge(systemImageName: "cable.connector"))
        .background(UITestWindowPlacementBridge())
        .toolbar { SessionToolbarContent(model: model) }
        .task { model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshPorts() }
        }
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
        ToolbarItemGroup(placement: .automatic) {
            // A plain Picker in an NSToolbar does not reliably draw its selected
            // value on macOS 26/27, so the port and baud selectors are Menus with
            // an explicit label that always shows the current value.
            Menu {
                if model.ports.isEmpty {
                    Text("—")
                } else {
                    ForEach(model.ports) { port in
                        Button(port.displayName) { model.configuration.path = port.path }
                    }
                }
            } label: {
                Text(currentPortName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: DesignTokens.toolbarPortPickerWidth - 40, alignment: .leading)
            }
            .fixedSize()
            .controlSize(.large)
            .disabled(model.isConfigurationLocked)
            .accessibilityLabel(L10n.port)
            .accessibilityValue(currentPortName)
            .accessibilityIdentifier("session.port-picker")
            .help(model.configuration.path.isEmpty ? L10n.port : model.configuration.path)

            Button(L10n.refresh, systemImage: "arrow.clockwise") { model.refreshPorts() }
                .labelStyle(.iconOnly)
                .toolbarIconControl()
                .disabled(model.isConfigurationLocked)
                .accessibilityLabel(L10n.refresh)
                .accessibilityIdentifier("session.refresh")

            Menu {
                ForEach(BaudRateCatalog.rates(including: model.configuration.baudRate), id: \.self) { rate in
                    Button(BaudRateCatalog.label(for: rate)) { model.configuration.baudRate = rate }
                }
            } label: {
                Text(BaudRateCatalog.label(for: model.configuration.baudRate))
                    .frame(width: 80, alignment: .leading)
            }
            .fixedSize()
            .controlSize(.large)
            .disabled(model.isConfigurationLocked)
            .accessibilityLabel(L10n.baudRate)
            .accessibilityValue(BaudRateCatalog.label(for: model.configuration.baudRate))
            .accessibilityIdentifier("session.baud-rate")

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

    private var currentPortName: String {
        guard !model.configuration.path.isEmpty else { return "—" }
        if let port = model.ports.first(where: { $0.path == model.configuration.path }) {
            return port.displayName
        }
        return URL(fileURLWithPath: model.configuration.path).lastPathComponent
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
        .appFont(.control, weight: .medium)
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
            Text(L10n.advancedParameters).appFont(.headline)
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
    @Environment(\.appFontScale) private var fontScale

    var body: some View {
        let revision = model.recordsRevision
        VStack(spacing: 0) {
            ConsoleToolbar(model: model)

            if model.isPaused {
                HStack {
                    Image(systemName: "pause.circle.fill")
                    Text(L10n.pausedBanner)
                    Spacer()
                    Button(L10n.resume) { model.togglePause() }
                }
                .appFont(.callout)
                .foregroundStyle(Color.sessionAttention)
                .padding(.horizontal, DesignTokens.contentInset)
                .padding(.vertical, 6)
                .background(Color.sessionAttention.opacity(0.1))
                .zIndex(1)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("console.paused-banner")
            }

            ZStack {
                ConsoleTextView(
                    records: model.visibleRecords,
                    revision: revision,
                    format: model.receiveFormat,
                    showsTimestamp: model.showsTimestamps,
                    textEncoding: model.textEncoding,
                    hexPresentation: model.hexPresentation,
                    fontSize: DesignTokens.monoFontSize(scale: fontScale),
                    lineSpacing: model.consoleLineSpacing.points,
                    followsLatest: model.followsLatest && !model.isPaused
                )

                if model.visibleRecords.isEmpty {
                    VStack(spacing: DesignTokens.compactSpacing) {
                        Image(systemName: "text.line.first.and.arrowtriangle.forward")
                            .appFont(.title)
                        Text(L10n.noRecords)
                            .appFont(.callout)
                    }
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
                }
            }
            .containerSurface()
            .padding(.horizontal, DesignTokens.contentInset)
            .padding(.bottom, DesignTokens.compactSpacing + 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ConsoleToolbar: View {
    @ObservedObject var model: SessionViewModel

    var body: some View {
        HStack(spacing: DesignTokens.standardSpacing) {
            Text(L10n.records).appFont(.headline)
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
            Picker("", selection: $model.receiveFormat) {
                Text("ASCII").tag(DisplayFormat.ascii)
                Text("HEX").tag(DisplayFormat.hex)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)
            .accessibilityLabel("接收显示格式")
            .accessibilityIdentifier("console.display-format")
            Toggle(L10n.timestamp, isOn: $model.showsTimestamps)
                .toggleStyle(.button)
                .controlSize(.large)
                .frame(minWidth: 66)
                .accessibilityIdentifier("console.timestamps")
            Toggle(L10n.follow, isOn: $model.followsLatest)
                .toggleStyle(.button)
                .controlSize(.large)
                .frame(minWidth: 56)
                .accessibilityIdentifier("console.follow")
            Spacer()
            Text("\(model.visibleRecords.count) 条")
                .foregroundStyle(.secondary)
                .appFont(.caption)
        }
        .padding(.horizontal, DesignTokens.contentInset)
        .frame(height: DesignTokens.barHeight)
        .background(.bar)
    }
}

private struct ConsoleLine {
    let timestamp: Date
    let direction: RecordDirection
    let text: String
}

/// Assembles a byte stream into display lines. ASCII/GB18030 data is buffered
/// until a newline so a device line is not split across rows by arrival timing;
/// HEX mode emits one line per record.
private struct ConsoleLineAssembler {
    private var pendingBytes: [UInt8] = []
    private var pendingTimestamp = Date.distantPast
    private var pendingDirection: RecordDirection = .received

    mutating func reset() {
        pendingBytes.removeAll(keepingCapacity: true)
        pendingTimestamp = .distantPast
        pendingDirection = .received
    }

    mutating func consume(
        _ record: CommunicationRecord,
        format: DisplayFormat,
        encoding: TextEncodingPreference,
        hexPresentation: HexPresentation
    ) -> [ConsoleLine] {
        if format == .hex {
            let text = HexCodec.encode(record.rawBytes, presentation: hexPresentation)
            return text.isEmpty ? [] : [ConsoleLine(timestamp: record.timestamp, direction: record.direction, text: text)]
        }
        if record.direction == .transmitted {
            let text = Self.trim(TextPayloadCodec.decodeForDisplay(record.rawBytes, encoding: encoding))
            return [ConsoleLine(timestamp: record.timestamp, direction: .transmitted, text: text)]
        }

        if pendingBytes.isEmpty {
            pendingTimestamp = record.timestamp
            pendingDirection = .received
        }
        pendingBytes.append(contentsOf: record.rawBytes)

        var lines: [ConsoleLine] = []
        while let newlineIndex = pendingBytes.firstIndex(of: 0x0A) {
            let lineBytes = pendingBytes[0..<newlineIndex]
            pendingBytes.removeSubrange(0...newlineIndex)
            let text = Self.trim(TextPayloadCodec.decodeForDisplay(Data(lineBytes), encoding: encoding))
            lines.append(ConsoleLine(timestamp: pendingTimestamp, direction: pendingDirection, text: text))
            if !pendingBytes.isEmpty {
                pendingTimestamp = record.timestamp
                pendingDirection = .received
            }
        }
        return lines
    }

    func pendingLine(format: DisplayFormat, encoding: TextEncodingPreference) -> ConsoleLine? {
        guard format != .hex, !pendingBytes.isEmpty else { return nil }
        let text = TextPayloadCodec.decodeForDisplay(Data(pendingBytes), encoding: encoding)
        let timestamp = pendingTimestamp == .distantPast ? Date() : pendingTimestamp
        return ConsoleLine(timestamp: timestamp, direction: pendingDirection, text: text)
    }

    private static func trim(_ text: String) -> String {
        var result = text
        while result.hasSuffix("\r") || result.hasSuffix("\n") { result.removeLast() }
        return result
    }
}

/// Single-selectable NSTextView console. Unlike per-row SwiftUI text, it offers
/// native wrapping and cross-line selection/copy, and appends incrementally.
private struct ConsoleTextView: NSViewRepresentable {
    let records: [CommunicationRecord]
    let revision: Int
    let format: DisplayFormat
    let showsTimestamp: Bool
    let textEncoding: TextEncodingPreference
    let hexPresentation: HexPresentation
    let fontSize: Double
    let lineSpacing: CGFloat
    let followsLatest: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = (scrollView.documentView as? NSTextView) ?? NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        // Avoid relaying out the entire (potentially huge) document on each append.
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.setAccessibilityIdentifier("console.records")
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            records: records,
            format: format,
            showsTimestamp: showsTimestamp,
            textEncoding: textEncoding,
            hexPresentation: hexPresentation,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            followsLatest: followsLatest
        )
    }

    @MainActor
    final class Coordinator {
        weak var textView: NSTextView?
        private var assembler = ConsoleLineAssembler()
        private var renderedCount = 0
        private var lastRenderedID: UUID?
        private var renderKey = ""
        private var committedLength = 0
        private var scrollScheduled = false
        /// Soft cap on rendered characters; old text is trimmed from the top.
        private let maximumCharacters = 2_000_000
        private let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter
        }()

        func update(
            records: [CommunicationRecord],
            format: DisplayFormat,
            showsTimestamp: Bool,
            textEncoding: TextEncodingPreference,
            hexPresentation: HexPresentation,
            fontSize: Double,
            lineSpacing: CGFloat,
            followsLatest: Bool
        ) {
            guard let textView else { return }
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = lineSpacing

            let key = "\(format.rawValue)|\(showsTimestamp)|\(textEncoding.rawValue)|\(hexPresentation.separator.rawValue)|\(hexPresentation.usesUppercase)|\(fontSize)|\(lineSpacing)"
            let canAppend = key == renderKey
                && records.count >= renderedCount
                && (renderedCount == 0 || records[renderedCount - 1].id == lastRenderedID)

            if canAppend {
                if records.count > renderedCount {
                    append(
                        Array(records[renderedCount...]),
                        into: textView,
                        font: font,
                        paragraph: paragraph,
                        format: format,
                        showsTimestamp: showsTimestamp,
                        textEncoding: textEncoding,
                        hexPresentation: hexPresentation
                    )
                }
            } else {
                rebuild(
                    records,
                    into: textView,
                    font: font,
                    paragraph: paragraph,
                    format: format,
                    showsTimestamp: showsTimestamp,
                    textEncoding: textEncoding,
                    hexPresentation: hexPresentation
                )
                renderKey = key
            }

            renderedCount = records.count
            lastRenderedID = records.last?.id
            if followsLatest {
                scheduleScrollToEnd()
            }
        }

        /// Coalesce follow-scrolling to at most once per runloop turn and never
        /// steal the scroll position while the user is selecting text.
        private func scheduleScrollToEnd() {
            guard !scrollScheduled else { return }
            scrollScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scrollScheduled = false
                guard let textView = self.textView else { return }
                guard textView.selectedRange().length == 0 else { return }
                textView.scrollToEndOfDocument(nil)
            }
        }

        private func trimIfNeeded(_ storage: NSTextStorage) {
            guard storage.length > maximumCharacters else { return }
            // Trim to half the cap so the O(n) edit is amortized.
            let target = storage.length - maximumCharacters / 2
            let string = storage.string as NSString
            var cut = target
            let searchRange = NSRange(location: target, length: min(4_096, string.length - target))
            let newline = string.range(of: "\n", options: [], range: searchRange)
            if newline.location != NSNotFound {
                cut = newline.location + newline.length
            }
            storage.deleteCharacters(in: NSRange(location: 0, length: cut))
            committedLength = max(0, committedLength - cut)
        }

        private func rebuild(
            _ records: [CommunicationRecord],
            into textView: NSTextView,
            font: NSFont,
            paragraph: NSParagraphStyle,
            format: DisplayFormat,
            showsTimestamp: Bool,
            textEncoding: TextEncodingPreference,
            hexPresentation: HexPresentation
        ) {
            assembler.reset()
            let complete = NSMutableAttributedString()
            for record in records {
                for line in assembler.consume(record, format: format, encoding: textEncoding, hexPresentation: hexPresentation) {
                    complete.append(attributed(line, font: font, paragraph: paragraph, showsTimestamp: showsTimestamp))
                }
            }
            let storage = textView.textStorage!
            storage.beginEditing()
            storage.setAttributedString(complete)
            committedLength = storage.length
            if let pending = assembler.pendingLine(format: format, encoding: textEncoding) {
                storage.append(attributed(pending, font: font, paragraph: paragraph, showsTimestamp: showsTimestamp))
            }
            trimIfNeeded(storage)
            storage.endEditing()
        }

        private func append(
            _ newRecords: [CommunicationRecord],
            into textView: NSTextView,
            font: NSFont,
            paragraph: NSParagraphStyle,
            format: DisplayFormat,
            showsTimestamp: Bool,
            textEncoding: TextEncodingPreference,
            hexPresentation: HexPresentation
        ) {
            let complete = NSMutableAttributedString()
            for record in newRecords {
                for line in assembler.consume(record, format: format, encoding: textEncoding, hexPresentation: hexPresentation) {
                    complete.append(attributed(line, font: font, paragraph: paragraph, showsTimestamp: showsTimestamp))
                }
            }
            let storage = textView.textStorage!
            storage.beginEditing()
            storage.replaceCharacters(
                in: NSRange(location: committedLength, length: storage.length - committedLength),
                with: complete
            )
            committedLength += complete.length
            if let pending = assembler.pendingLine(format: format, encoding: textEncoding) {
                storage.append(attributed(pending, font: font, paragraph: paragraph, showsTimestamp: showsTimestamp))
            }
            trimIfNeeded(storage)
            storage.endEditing()
        }

        private func attributed(
            _ line: ConsoleLine,
            font: NSFont,
            paragraph: NSParagraphStyle,
            showsTimestamp: Bool
        ) -> NSAttributedString {
            let result = NSMutableAttributedString()
            if showsTimestamp {
                result.append(NSAttributedString(
                    string: formatter.string(from: line.timestamp) + " ",
                    attributes: [.font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.secondaryLabelColor]
                ))
            }
            let directionColor: NSColor = line.direction == .received ? .systemGreen : .controlAccentColor
            result.append(NSAttributedString(
                string: line.direction.rawValue + " ",
                attributes: [.font: font, .paragraphStyle: paragraph, .foregroundColor: directionColor]
            ))
            result.append(NSAttributedString(
                string: line.text + "\n",
                attributes: [.font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.labelColor]
            ))
            return result
        }
    }
}

private struct SendEditor: View {
    @ObservedObject var model: SessionViewModel
    @Environment(\.appFontScale) private var fontScale

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.standardSpacing) {
                Text(L10n.send).appFont(.headline)
                Picker("", selection: $model.sendFormat) {
                    Text("ASCII").tag(DisplayFormat.ascii)
                    Text("HEX").tag(DisplayFormat.hex)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
                .accessibilityLabel("发送格式")
                .accessibilityIdentifier("send.format")
                Menu {
                    Button(L10n.none) { model.lineEnding = .none }
                    Button("CR") { model.lineEnding = .cr }
                    Button("LF") { model.lineEnding = .lf }
                    Button("CRLF") { model.lineEnding = .crlf }
                } label: {
                    Text("\(L10n.lineEnding) \(model.lineEnding.shortLabel)")
                }
                .controlSize(.large)
                .accessibilityIdentifier("send.line-ending")
                .accessibilityValue(model.lineEnding.shortLabel)
                Spacer()
            }
            .padding(.horizontal, DesignTokens.contentInset)
            .frame(height: 36)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .background(.bar)

            HStack(alignment: .bottom, spacing: DesignTokens.standardSpacing) {
                ZStack(alignment: .topLeading) {
                    PlainTextEditor(
                        text: $model.sendText,
                        isEditable: model.isConnected,
                        fontSize: DesignTokens.monoFontSize(scale: fontScale),
                        accessibilityIdentifier: "send.editor"
                    )
                    .accessibilityLabel(L10n.send)

                    if model.sendText.isEmpty {
                        Text(model.isConnected ? L10n.sendPlaceholder : L10n.connectToSend)
                            .appFont(.mono)
                            .foregroundStyle(.tertiary)
                            .padding(PlainTextEditor.textInset)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 96)
                .containerSurface(cornerRadius: DesignTokens.controlCornerRadius)

                Button(L10n.send, systemImage: "paperplane.fill") {
                    model.sendCurrentText()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canSend)
                .accessibilityIdentifier("send.button")
            }
            .padding(.horizontal, DesignTokens.contentInset)
            .padding(.vertical, DesignTokens.compactSpacing + 4)

            HStack(spacing: DesignTokens.compactSpacing) {
                Label("自动发送", systemImage: "repeat")
                    .appFont(.caption, weight: .semibold)
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
                        .appFont(.caption)
                        .foregroundStyle(Color.sessionConnected)
                        .accessibilityIdentifier("auto-send.status")
                }
                Spacer()
            }
            .padding(.horizontal, DesignTokens.contentInset)
            .padding(.bottom, DesignTokens.compactSpacing + 4)

            if let error = model.sendValidationError {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .appFont(.caption)
                    .foregroundStyle(Color.sessionError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignTokens.contentInset)
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
                    .appFont(.headline)
                Spacer()
                Button("新增", systemImage: "plus") {
                    editor = PresetEditorState()
                }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("presets.add")
            }
            .padding(.horizontal, 4)
            .frame(height: DesignTokens.barHeight)
            .background(.bar)

            if model.presets.isEmpty {
                VStack(spacing: DesignTokens.compactSpacing) {
                    ContentUnavailableView("暂无预设", systemImage: "tray", description: Text("新建后可单次发送或循环发送"))
                    Text("预设检查器为空")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("presets.placeholder")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.presets) { preset in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(preset.name).appFont(.headline)
                        Text(preset.content)
                            .appFont(.mono)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                            .help(preset.content)
                            .accessibilityIdentifier("presets.content.\(preset.id.uuidString)")
                        Text("\(preset.format.rawValue.uppercased()) · \(preset.lineEnding.rawValue.uppercased())")
                            .appFont(.caption)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignTokens.compactSpacing + 4)
                    .padding(.vertical, DesignTokens.compactSpacing)
                    .containerSurface()
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                    .listRowBackground(Color.clear)
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
        .padding(.bottom, DesignTokens.compactSpacing + 4)
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
    @Environment(\.appFontScale) private var fontScale
    @State var state: PresetEditorState
    @ObservedObject var model: SessionViewModel
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.standardSpacing) {
            Text(state.presetID == nil ? "新建预设" : "编辑预设").appFont(.headline)
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
            PlainTextEditor(
                text: $state.content,
                isEditable: true,
                fontSize: DesignTokens.monoFontSize(scale: fontScale),
                accessibilityIdentifier: "presets.editor.content"
            )
            .frame(minHeight: 120)
            .containerSurface(cornerRadius: DesignTokens.controlCornerRadius)
            .onChange(of: state.content) { _, newValue in
                guard state.format == .hex else { return }
                let formatted = HexInputFormatter.format(newValue)
                if formatted != newValue { state.content = formatted }
            }
            .onChange(of: state.format) { _, format in
                guard format == .hex else { return }
                let formatted = HexInputFormatter.format(state.content)
                if formatted != state.content { state.content = formatted }
            }
            if let error { Text(error).appFont(.caption).foregroundStyle(Color.sessionError) }
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
            Text("RX \(formattedBytes(model.statistics?.receivedByteCount ?? 0))")
                .foregroundStyle(Color.sessionConnected)
                .accessibilityIdentifier("status.rx")
                .accessibilityValue("\(model.statistics?.receivedByteCount ?? 0)")
            Text("TX \(formattedBytes(model.statistics?.transmittedByteCount ?? 0))")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("status.tx")
                .accessibilityValue("\(model.statistics?.transmittedByteCount ?? 0)")
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
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.sessionError)
                    .lineLimit(1)
                    .accessibilityIdentifier("status.error")
            }
        }
        .appFont(.subheadline)
        .padding(.horizontal, DesignTokens.contentInset)
        .frame(height: 28)
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

/// Plain monospaced editor with deterministic insets so a placeholder overlay
/// can line up exactly with the caret/text.
private struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    var fontSize: CGFloat
    var accessibilityIdentifier: String

    static let textInset: CGFloat = 8

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = (scrollView.documentView as? NSTextView) ?? NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: Self.textInset, height: Self.textInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityIdentifier(accessibilityIdentifier)
        textView.string = text
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if !context.coordinator.isEditing, textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        var isEditing = false

        init(_ parent: PlainTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isEditing = true
            parent.text = textView.string
            isEditing = false
        }
    }
}

private extension LineEnding {
    var shortLabel: String {
        switch self {
        case .none: "无"
        case .cr: "CR"
        case .lf: "LF"
        case .crlf: "CRLF"
        }
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
