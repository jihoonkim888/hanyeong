import AppKit
import SwiftUI

/// Hosts the SwiftUI settings in an AppKit window. A menu bar app has no scene of its own
/// to open, and managing the window directly keeps showing it reliable.
final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        model.refresh(full: true)
    }

    private func makeWindow() -> NSWindow {
        let window = Self.makeWindow(rootView: SettingsView().environmentObject(model))
        window.center()
        window.setFrameAutosaveName("HanyeongSettings")
        return window
    }

    static func makeWindow(rootView: some View) -> NSWindow {
        let hosting = NSHostingController(rootView: rootView)
        // Lets the split view lay itself out around this window's title bar.
        hosting.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 720, height: 640))
        return window
    }
}
