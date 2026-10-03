import ApplicationServices
import AppKit
import Foundation
import HanyeongCore
import os
import ServiceManagement

enum AppInfo {
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "io.github.jihoonkim888.hanyeong"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "개발 빌드"
    static let repositoryURL = URL(string: "https://github.com/jihoonkim888/hanyeong")!
    /// Posted by a second launch so the running instance shows its settings window.
    static let showSettingsNotification = Notification.Name("\(bundleIdentifier).showSettings")
}

/// Lifecycle and timing events, written to the unified log and to a small file so that
/// an unexpected exit can be looked into afterwards. Key presses are never logged.
enum Log {
    static let app = Channel(category: "app")
    static let engine = Channel(category: "engine")

    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Hanyeong/hanyeong.log")

    private static let queue = DispatchQueue(label: "hanyeong.log")
    private static let maximumSize = 512 * 1024
    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    struct Channel {
        let category: String
        private let logger: Logger

        init(category: String) {
            self.category = category
            logger = Logger(subsystem: AppInfo.bundleIdentifier, category: category)
        }

        func notice(_ message: String) {
            logger.notice("\(message, privacy: .public)")
            Log.write(category, message)
        }

        func error(_ message: String) {
            logger.error("\(message, privacy: .public)")
            Log.write(category, "ERROR \(message)")
        }
    }

    /// Waits for pending lines to reach the file. Call before the process exits.
    static func flush() {
        queue.sync {}
    }

    private static func write(_ category: String, _ message: String) {
        let date = Date()
        let pid = ProcessInfo.processInfo.processIdentifier
        queue.async {
            let line = "\(timestamp.string(from: date)) [\(pid)] \(category): \(message)\n"
            let manager = FileManager.default
            try? manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = try? manager.attributesOfItem(atPath: fileURL.path)[.size] as? Int, size > maximumSize {
                let previous = fileURL.deletingPathExtension().appendingPathExtension("previous.log")
                try? manager.removeItem(at: previous)
                try? manager.moveItem(at: fileURL, to: previous)
            }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            } else {
                try? Data(line.utf8).write(to: fileURL)
            }
        }
    }
}

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt, which also adds the app to the Accessibility list.
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
}

enum SystemSettings {
    static let bundleIdentifier = "com.apple.systempreferences"

    static func openKeyboard() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }
}

private func open(_ url: String) {
    guard let url = URL(string: url) else { return }
    NSWorkspace.shared.open(url)
}

enum ShortcutReader {
    private static let domain = "com.apple.symbolichotkeys" as CFString

    static func current() -> SystemShortcut? {
        CFPreferencesAppSynchronize(domain)
        let hotKeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain) as? [String: Any]
        return SystemShortcut.resolve(symbolicHotKeys: hotKeys)
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("login item change failed: \(error.localizedDescription)")
        }
    }
}

enum ConfigurationStore {
    private static let key = "configuration"

    static func load() -> Configuration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let configuration = try? JSONDecoder().decode(Configuration.self, from: data)
        else { return Configuration() }
        return configuration
    }

    static func save(_ configuration: Configuration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
