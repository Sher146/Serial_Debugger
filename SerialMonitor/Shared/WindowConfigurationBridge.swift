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
    }
}
