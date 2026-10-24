import AppKit
import SwiftUI
import SerialCore

/// App 持有、跨窗口共享的依赖。窗口只从这里取“新造一个独立会话”的工厂，
/// 串口、记录、发送队列与日志都由窗口自己的 `SessionViewModel` 持有。
@MainActor
struct SessionEnvironment {
    let preferencesStore: PreferencesStore
    let presetStore: PresetStore
    let scenario: SessionUITestScenario?

    static func bootstrap(arguments: [String]) -> SessionEnvironment {
        guard let scenario = SessionUITestScenario(arguments: arguments) else {
            return SessionEnvironment(
                preferencesStore: PreferencesStore(),
                presetStore: PresetStore(),
                scenario: nil
            )
        }
        // UI 测试必须不继承上一次手动运行的偏好，也不该每次运行都往
        // ~/Library/Preferences 里多留一个 plist；固定 suite 并在启动时清空。
        let suiteName = "serial-monitor.ui-test"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let preferencesStore = PreferencesStore(defaults: defaults, key: "preferences")
        let presetStore = PresetStore(defaults: defaults, key: "presets")
        var preferences = preferencesStore.load()
        preferences.logDirectoryPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("serial-monitor-ui-test-logs", isDirectory: true)
            .path
        if let index = arguments.firstIndex(of: "-ui-testing-font-scale"),
           arguments.indices.contains(index + 1),
           let scale = AppFontScale(rawValue: arguments[index + 1]) {
            preferences.fontScale = scale
        }
        preferencesStore.save(preferences)
        return SessionEnvironment(preferencesStore: preferencesStore, presetStore: presetStore, scenario: scenario)
    }

    func makeViewModel() -> SessionViewModel {
        SessionViewModel(client: makeClient(), preferencesStore: preferencesStore, presetStore: presetStore)
    }

    private func makeClient() -> any SessionClient {
        if let scenario {
            return SessionScenarioClient(scenario: scenario)
        }
        return SessionCoordinator(
            serialPort: POSIXSerialPortAdapter(),
            logService: FileLogService(),
            portLeases: .shared
        )
    }
}

/// 记录当前打开的会话窗口。设置窗口与 App 级命令通过它定位“当前窗口”，
/// 而不是像单会话时期那样共用同一个 `SessionViewModel`。
@MainActor
final class SessionWindowRegistry: ObservableObject {
    @Published private(set) var activeModel: SessionViewModel?
    private var models: [ObjectIdentifier: SessionViewModel] = [:]

    func register(_ model: SessionViewModel) {
        models[ObjectIdentifier(model)] = model
        if activeModel == nil {
            activeModel = model
        }
    }

    func unregister(_ model: SessionViewModel) {
        models.removeValue(forKey: ObjectIdentifier(model))
        guard activeModel === model else { return }
        activeModel = models.values.first
    }

    /// 成为 key window 时调用；顺带补登记，避免窗口先成为 key、后触发 onAppear。
    func activate(_ model: SessionViewModel) {
        models[ObjectIdentifier(model)] = model
        guard activeModel !== model else { return }
        activeModel = model
    }
}

/// 一个窗口 = 一个独立会话。窗口关闭只结束自己的串口、日志与循环发送。
@MainActor
struct SessionWindowView: View {
    let environment: SessionEnvironment
    @ObservedObject var registry: SessionWindowRegistry
    @StateObject private var model: SessionViewModel

    init(environment: SessionEnvironment, registry: SessionWindowRegistry) {
        self.environment = environment
        self.registry = registry
        _model = StateObject(wrappedValue: environment.makeViewModel())
    }

    var body: some View {
        SessionView(model: model)
            .preferredColorScheme(model.appearance.colorScheme)
            .environment(\.appFontScale, model.fontScale)
            .focusedSceneObject(model)
            .background(SessionWindowActivityBridge { registry.activate(model) })
            .onAppear { registry.register(model) }
            .onDisappear { registry.unregister(model) }
    }
}

/// 设置窗口作用于最近激活的会话窗口：外观、字号以及串口默认参数仍是各自的
/// `SessionViewModel` 属性，改动即时生效在被选中的窗口上。
struct SettingsHost: View {
    @ObservedObject var registry: SessionWindowRegistry

    var body: some View {
        if let model = registry.activeModel {
            SettingsView(model: model)
                .id(ObjectIdentifier(model))
        } else {
            ContentUnavailableView(
                "没有打开的会话窗口",
                systemImage: "macwindow",
                description: Text("新建或激活一个串口窗口后再调整设置。")
            )
            .frame(width: 760, height: 560)
            .background(SettingsWindowConfigurationBridge())
            .accessibilityIdentifier("settings.empty")
        }
    }
}

/// 把 SwiftUI 窗口与它的 `NSWindow` 关联起来，用于跟踪哪个窗口处于激活状态。
struct SessionWindowActivityBridge: NSViewRepresentable {
    let onActivate: @MainActor () -> Void

    func makeNSView(context: Context) -> WindowActivityView {
        let view = WindowActivityView()
        view.onActivate = onActivate
        return view
    }

    func updateNSView(_ nsView: WindowActivityView, context: Context) {
        nsView.onActivate = onActivate
    }

    final class WindowActivityView: NSView {
        var onActivate: (@MainActor () -> Void)?
        private weak var observedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observedWindow {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.didBecomeKeyNotification,
                    object: observedWindow
                )
            }
            observedWindow = window
            guard let window else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidBecomeKey),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
            if window.isKeyWindow {
                onActivate?()
            }
        }

        @objc private func windowDidBecomeKey() {
            onActivate?()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
