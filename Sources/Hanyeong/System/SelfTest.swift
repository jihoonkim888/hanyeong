import AppKit
import HanyeongCore

/// An end-to-end check of the switching engine against the real input method.
///
/// It types into its own window: a 한영 key press followed, after a short delay, by the
/// keys G K S. If the switch took effect first the result is "한" (or "gks" going the
/// other way); if keys slipped in ahead of the switch the result is mixed. Each case is
/// run without buffering, with the engine using the system shortcut, and with the
/// engine selecting the input source directly, and the time each switch took is recorded.
///
///     open Hanyeong.app --args --selftest /path/to/report.txt
///
/// Needs the Accessibility permission, and the regular app must not be running.
enum SelfTest {
    static let argument = "--selftest"

    private enum Mode: String, CaseIterable {
        case unbuffered = "버퍼링 없음 (시스템 단축키만)"
        case shortcut = "한영 엔진 · 시스템 단축키"
        case direct = "한영 엔진 · 직접 선택"
    }

    private struct Trial {
        var mode: Mode
        var delay: Int
        var expected: String
        var typed: String
        var latency: Double?

        var isCorrect: Bool { typed == expected }
    }

    private static let delays = [0, 25, 60]
    private static let trialsPerCase = 6
    private static let keys: [CGKeyCode] = [5, 40, 1]  // G K S: "gks" in English, "한" in Korean

    static func run(reportPath: String) -> Never {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)

        func fail(_ message: String) -> Never {
            try? message.write(toFile: reportPath, atomically: true, encoding: .utf8)
            exit(1)
        }
        guard Accessibility.isTrusted else { fail("손쉬운 사용 권한이 없어 점검할 수 없습니다.\n") }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: AppInfo.bundleIdentifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard others.isEmpty else { fail("한영이 실행 중입니다. 종료한 뒤 다시 점검하세요.\n") }

        let textView = NSTextView(frame: NSRect(x: 20, y: 20, width: 380, height: 60))
        textView.font = .systemFont(ofSize: 28)
        let label = NSTextField(wrappingLabelWithString: "한영 자체 점검 중입니다. 약 45초 동안 키보드를 누르지 말아 주세요.")
        label.frame = NSRect(x: 20, y: 90, width: 380, height: 40)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 150),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.title = "한영 자체 점검"
        window.contentView?.addSubview(label)
        window.contentView?.addSubview(textView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        application.activate(ignoringOtherApps: true)

        let engine = SwitchEngine(capsLock: CapsLockController())
        DistributedNotificationCenter.default().addObserver(forName: InputSources.changedNotification, object: nil, queue: .main) { _ in
            let id = InputSources.currentID()
            InputSources.noteCurrent(id)
            engine.sourceDidChange(to: id)
        }

        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 1)
            let report = measure(engine: engine, textView: textView)
            try? report.write(toFile: reportPath, atomically: true, encoding: .utf8)
            exit(0)
        }
        application.run()
        exit(0)
    }

    // MARK: - Measurement (background thread)

    private static func onMain<Value>(_ body: () -> Value) -> Value {
        DispatchQueue.main.sync(execute: body)
    }

    private static func measure(engine: SwitchEngine, textView: NSTextView) -> String {
        let shortcut = onMain { ShortcutReader.current() }
        let original = onMain { InputSources.currentID() }
        var trials: [Trial] = []

        for mode in Mode.allCases {
            if shortcut == nil && mode != .direct { continue }
            onMain {
                switch mode {
                case .unbuffered:
                    engine.stop()
                case .shortcut, .direct:
                    var settings = SwitchEngine.Settings()
                    settings.options = .init(shiftTogglesCapsLock: false, longPressTogglesCapsLock: false)
                    settings.shortcut = mode == .shortcut ? shortcut : nil
                    engine.update(settings)
                    _ = engine.start()
                }
            }
            for delay in delays {
                for _ in 0..<trialsPerCase {
                    trials.append(runTrial(mode: mode, delay: delay, shortcut: shortcut, textView: textView))
                }
            }
        }

        onMain {
            engine.stop()
            if InputSources.currentID() != original { InputSources.selectOther(than: InputSources.currentID()) }
        }
        return report(trials, shortcut: shortcut)
    }

    private static func runTrial(mode: Mode, delay: Int, shortcut: SystemShortcut?, textView: NSTextView) -> Trial {
        let before = onMain { () -> InputSourceInfo in
            textView.inputContext?.discardMarkedText()
            textView.string = ""
            return InputSources.current()
        }
        let start = DispatchTime.now()

        if mode == .unbuffered, let shortcut {
            SwitchEngine.press(shortcut)
        } else {
            // An unmarked F19, exactly what a remapped 한영 key sends.
            post(CGKeyCode(SystemShortcut.f19KeyCode), flags: .maskSecondaryFn)
        }
        if delay > 0 { usleep(useconds_t(delay * 1000)) }
        keys.forEach { post($0) }

        var latency: Double?
        while elapsed(since: start) < 650 {
            if latency == nil, onMain({ InputSources.currentID() }) != before.id {
                latency = elapsed(since: start)
            }
            usleep(1000)
        }
        return Trial(
            mode: mode, delay: delay,
            expected: before.isKorean ? "gks" : "한",
            typed: onMain { textView.string },
            latency: latency
        )
    }

    private static func post(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
            usleep(300)
        }
    }

    private static func elapsed(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    // MARK: - Report

    private static func report(_ trials: [Trial], shortcut: SystemShortcut?) -> String {
        var lines = [
            "한영 자체 점검",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "시스템 단축키: \(shortcut.map { "\($0.displayName) (\($0.kindName))" } ?? "꺼져 있음")",
            "",
            "각 시험: 한영 키 → (지연) → G K S 입력. 한글로 바뀔 때 ‘한’, 영문으로 바뀔 때 ‘gks’가 나와야 정상입니다.",
            "",
        ]
        for mode in Mode.allCases {
            let ofMode = trials.filter { $0.mode == mode }
            guard !ofMode.isEmpty else { continue }
            lines.append("■ \(mode.rawValue)")
            for delay in delays {
                let group = ofMode.filter { $0.delay == delay }
                let correct = group.filter(\.isCorrect).count
                let wrong = group.filter { !$0.isCorrect }.map { "‘\($0.typed)’" }
                var line = "  한영 키 뒤 \(delay)ms에 입력: \(correct)/\(group.count) 정상"
                if !wrong.isEmpty { line += " · 잘못 입력된 결과: \(wrong.joined(separator: " "))" }
                lines.append(line)
            }
            let latencies = ofMode.compactMap(\.latency).sorted()
            if let first = latencies.first, let last = latencies.last {
                let median = latencies[latencies.count / 2]
                lines.append(String(format: "  전환 시간: 중앙값 %.0fms, 최소 %.0fms, 최대 %.0fms (%d/%d회 전환됨)", median, first, last, latencies.count, ofMode.count))
            } else {
                lines.append("  전환이 한 번도 일어나지 않았습니다.")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
