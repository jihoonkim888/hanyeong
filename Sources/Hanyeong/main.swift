import AppKit

// The same executable also runs as the watchdog child, which must stay free of AppKit.
if CommandLine.arguments.contains(Watchdog.argument) {
    Watchdog.run()
}

if let index = CommandLine.arguments.firstIndex(of: Preview.argument) {
    Preview.run(CommandLine.arguments.dropFirst(index + 1).first ?? "general")
}

if let index = CommandLine.arguments.firstIndex(of: SelfTest.argument), index + 1 < CommandLine.arguments.count {
    SelfTest.run(reportPath: CommandLine.arguments[index + 1])
}

// Only one instance may own the keyboard. A second launch just brings up the first one's settings.
let others = NSRunningApplication.runningApplications(withBundleIdentifier: AppInfo.bundleIdentifier)
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if !others.isEmpty && Bundle.main.bundleIdentifier != nil {
    DistributedNotificationCenter.default().postNotificationName(
        AppInfo.showSettingsNotification, object: nil, userInfo: nil, deliverImmediately: true
    )
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
