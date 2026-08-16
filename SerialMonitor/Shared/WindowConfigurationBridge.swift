import AppKit
import SwiftUI

struct WindowMinimumSizeBridge: NSViewRepresentable {
    let minimumSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.contentMinSize = minimumSize
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.contentMinSize = minimumSize
    }
}
