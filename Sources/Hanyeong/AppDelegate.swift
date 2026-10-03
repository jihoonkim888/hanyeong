import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: StatusItemController?
    private lazy var settings = SettingsWindowController(model: model)
    private var watchdog: Int32?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.notice("launched \(AppInfo.version), trusted=\(Accessibility.isTrusted), safeMode=\(model.isSafeMode), earlierCrashes=\(Watchdog.inheritedHistory.count)")
        watchdog = Watchdog.spawn()
        NSApp.mainMenu = Self.makeMainMenu()
        statusItem = StatusItemController(model: model) { [weak self] in self?.settings.show() }
        model.start()

        DistributedNotificationCenter.default().addObserver(
            forName: AppInfo.showSettingsNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.settings.show() }

        // Quit through the normal path on these signals so key mappings are removed.
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                Log.app.notice("received signal \(number)")
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }

        // Open settings when there is something to do there, or no menu bar item to reach them from.
        if model.status == .needsPermission || model.status == .safeMode || !model.config.showsMenuBarItem {
            settings.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settings.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
        Watchdog.signalCleanExit(watchdog)
        Log.app.notice("quit normally")
        Log.flush()
    }

    static func relaunch() {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", Bundle.main.bundlePath]
        try? open.run()
        NSApp.terminate(nil)
    }

    /// A menu bar app shows no menu bar of its own, but the standard shortcuts still come from the main menu.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "한영 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = app

        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = edit

        let window = NSMenu(title: "윈도우")
        window.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = window

        return main
    }
}
