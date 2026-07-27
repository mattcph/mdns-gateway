import AppKit
import SwiftUI

final class DevicesWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let viewModel = DevicesViewModel()

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            Task { await viewModel.refresh() }
            return
        }

        let host = NSHostingView(rootView: DevicesView(viewModel: viewModel))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "OCA Devices"
        win.contentView = host
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.minSize = NSSize(width: 720, height: 420)
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.disappear()
    }
}
