import AppKit
import SwiftUI

struct WindowMinimumSizeBridge: NSViewRepresentable {
    let minimumSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView.window)
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        // macOS 26 SwiftUI windows default to a full-size content view, which
        // places the console and preset toolbars underneath the window toolbar.
        window.styleMask.remove(.fullSizeContentView)
        window.contentMinSize = minimumSize
        window.isMovableByWindowBackground = true
    }
}

/// Installs a plain, non-interactive app glyph at the leading edge of the
/// titlebar. A `ToolbarItem` would be wrapped in a clickable Liquid Glass
/// capsule on macOS 26+, which is not what we want here.
struct TitlebarGlyphBridge: NSViewRepresentable {
    let systemImageName: String

    final class Coordinator {
        var installed = false
        weak var host: NSView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.host = view
        scheduleInstall(context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.host = nsView
        scheduleInstall(context)
    }

    private func scheduleInstall(_ context: Context) {
        for delay in [0.0, 0.15, 0.4, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let window = context.coordinator.host?.window else { return }
                install(on: window, context: context)
            }
        }
    }

    private func install(on window: NSWindow, context: Context) {
        guard !context.coordinator.installed else { return }
        context.coordinator.installed = true

        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let imageView = NSImageView(frame: NSRect(x: 6, y: 19, width: 14, height: 14))
        imageView.image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = .secondaryLabelColor

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 26, height: 52))
        container.addSubview(imageView)

        let controller = NSTitlebarAccessoryViewController()
        controller.view = container
        controller.layoutAttribute = .leading
        window.addTitlebarAccessoryViewController(controller)
    }
}

/// UI tests launch many windows; keep them off the primary display so the
/// developer's main screen stays usable. Only applies when the deterministic
/// scenario argument is present, and only when a second screen exists.
struct UITestWindowPlacementBridge: NSViewRepresentable {
    final class Coordinator {
        var didPlace = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { place(view.window, context: context) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { place(nsView.window, context: context) }
    }

    private func place(_ window: NSWindow?, context: Context) {
        guard !context.coordinator.didPlace,
              ProcessInfo.processInfo.arguments.contains("-ui-testing-scenario"),
              let window,
              NSScreen.screens.count > 1 else { return }
        context.coordinator.didPlace = true

        let target = NSScreen.screens[1].visibleFrame
        var frame = window.frame
        frame.origin.x = target.minX + 40
        frame.origin.y = target.maxY - frame.height - 40
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
    }
}
