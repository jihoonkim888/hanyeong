import AppKit
import HanyeongCore
import SwiftUI

/// Shows the settings window with sample data, without touching the keyboard or asking
/// for permission. Used to check the UI and to take README screenshots:
/// `Hanyeong --preview general|permission|keyboards|keyboards-device|about`
enum Preview {
    static let argument = "--preview"

    static func run(_ name: String) -> Never {
        let application = NSApplication.shared
        // A regular app here, so screenshot tools can find the window.
        application.setActivationPolicy(.regular)

        let external = KeyboardIdentity(vendorID: 1234, productID: 5678)
        var config = Configuration()
        config.allKeyboards.mappings.append(KeyMapping(from: .keyboard(0xE4), to: .fn))
        config.devices = [DeviceProfile(identity: external, name: "USB Keyboard", profile: KeyboardProfile(mappings: [
            KeyMapping(from: .keyboard(0xE6), to: .hanyeong),
            KeyMapping(from: .keyboard(0xE3), to: .keyboard(0xE2)),
            KeyMapping(from: .keyboard(0xE2), to: .keyboard(0xE3)),
        ]))]
        let model = AppModel(
            preview: config,
            keyboards: [
                ConnectedKeyboard(identity: .builtIn, name: "내장 키보드"),
                ConnectedKeyboard(identity: external, name: "USB Keyboard"),
            ],
            // "permission" shows a first launch: no Accessibility permission, default shortcut.
            shortcut: name == "permission"
                ? SystemShortcut(kind: .previousSource, keyCode: 49, modifiers: 0x40000)
                : SystemShortcut(kind: .nextSource, keyCode: SystemShortcut.f19KeyCode, modifiers: 0x800000),
            isTrusted: name != "permission"
        )

        let view: SettingsView
        switch name {
        case "keyboards": view = SettingsView(pane: .keyboards)
        case "keyboards-device": view = SettingsView(pane: .keyboards, keyboard: external)
        case "about": view = SettingsView(pane: .about)
        default: view = SettingsView(pane: .general)
        }
        let window = SettingsWindowController.makeWindow(rootView: view.environmentObject(model))
        window.center()
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
        // The window number lets a script capture exactly this window.
        print(window.windowNumber)
        fflush(stdout)
        application.run()
        exit(0)
    }
}
