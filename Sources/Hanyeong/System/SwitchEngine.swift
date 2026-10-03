import Carbon
import CoreGraphics
import Foundation
import HanyeongCore
import os

/// Owns the keyboard event tap and turns 한영 key presses into input source switches.
///
/// Threading: the tap runs on its own thread so that a busy main thread can never stall
/// typing. Text Input Source calls are made only on the main thread. All mutable state
/// is guarded by `lock`, which is also held while posting so that replayed events keep
/// their order relative to keys passing through the tap.
final class SwitchEngine {
    struct Settings: Equatable {
        var options = SwitchCore<CGEvent>.Options()
        var longPressDuration: TimeInterval = 0.4
        var shortcut: SystemShortcut?
        /// While set, the 한영 key is left alone, so the system shortcut recorder can capture it.
        var passesTriggerThrough = false
    }

    private struct Flight {
        var generation: Int
        /// The source selected when the switch began; the switch is done once it differs.
        var baseline: String
        var startedAt: DispatchTime
        var usedShortcut: Bool
        var fellBack = false
        var isSettling = false
    }

    /// Stamped on events this engine posts so that the tap lets them through.
    private static let marker: Int64 = 0x4841_4E59
    private static let triggerKeyCode = Int64(SystemShortcut.f19KeyCode)
    /// How long to wait for a switch before giving up on it.
    private static let timeout: TimeInterval = 0.3
    private static let fallbackTimeout: TimeInterval = 0.15

    /// Called on the main thread after this engine changes the Caps Lock state.
    var onCapsLockToggled: (() -> Void)?

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "hanyeong.engine", qos: .userInteractive)
    private let capsLock: CapsLockController
    /// Time given to the frontmost app to act on a switch after it becomes visible here.
    private let settleDelay: TimeInterval

    private var core = SwitchCore<CGEvent>()
    private var settings = Settings()
    private var flight: Flight?
    private var knownSourceID = ""
    /// Consecutive presses where the shortcut did nothing but a direct switch worked.
    private var shortcutMisses = 0

    private var tap: CFMachPort?
    private var tapRunLoop: CFRunLoop?
    private var pollTimer: DispatchSourceTimer?

    init(capsLock: CapsLockController) {
        self.capsLock = capsLock
        let override = UserDefaults.standard.double(forKey: "settleDelayMilliseconds")
        settleDelay = (override > 0 ? override : 8) / 1000
    }

    var isRunning: Bool { tap != nil }

    // MARK: - Lifecycle (main thread)

    /// Returns `false` when the tap cannot be created, which means Accessibility permission is missing.
    func start() -> Bool {
        if tap != nil { return true }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let sourceID = InputSources.currentID()
        lock.withLock { knownSourceID = sourceID }
        tap = port

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0), .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            self?.tapRunLoop = runLoop
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "hanyeong.tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        Log.engine.notice("event tap started")
        return true
    }

    func stop() {
        guard let port = tap else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let tapRunLoop { CFRunLoopStop(tapRunLoop) }
        CFMachPortInvalidate(port)
        tap = nil
        tapRunLoop = nil
        pollTimer?.cancel()
        pollTimer = nil
        lock.withLock {
            flight = nil
            core.reset().forEach(post)
        }
        Log.engine.notice("event tap stopped")
    }

    /// The system disables a tap that it considers unresponsive; turn it back on.
    func ensureEnabled() {
        guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.engine.notice("event tap re-enabled")
    }

    func update(_ newSettings: Settings) {
        lock.withLock {
            if newSettings.shortcut != settings.shortcut { shortcutMisses = 0 }
            settings = newSettings
            core.options = newSettings.options
        }
    }

    /// Call on the main thread whenever the selected input source is seen to change.
    func sourceDidChange(to id: String) {
        lock.withLock {
            knownSourceID = id
            guard var current = flight, core.inFlight == current.generation,
                  !current.isSettling, id != current.baseline
            else { return }
            current.isSettling = true
            flight = current

            if current.usedShortcut {
                shortcutMisses = 0
            } else if current.fellBack {
                shortcutMisses += 1
            }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - current.startedAt.uptimeNanoseconds) / 1_000_000
            Log.engine.notice(String(format: "switched in %.1f ms (%@)", elapsed, current.usedShortcut ? "shortcut" : "direct"))

            let generation = current.generation
            queue.asyncAfter(deadline: .now() + settleDelay) { [weak self] in self?.complete(generation) }
        }
    }

    // MARK: - Event tap (tap thread)

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .keyDown, .keyUp, .flagsChanged:
            break
        default:
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker { return pass }

        lock.lock()
        defer { lock.unlock() }

        let isTrigger = type != .flagsChanged && event.getIntegerValueField(.keyboardEventKeycode) == Self.triggerKeyCode
        if isTrigger && !settings.passesTriggerThrough {
            if type == .keyDown {
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                run(core.triggerDown(shift: event.flags.contains(.maskShift), isRepeat: isRepeat))
            } else {
                core.triggerUp()
            }
            return nil
        }
        // A held event outlives this callback, so it has to be a copy.
        return core.keyEvent(event.copy() ?? event, isKeyDown: type == .keyDown) ? nil : pass
    }

    // MARK: - Switching (lock held)

    private func run(_ effects: [SwitchCore<CGEvent>.Effect]) {
        for effect in effects {
            switch effect {
            case .performToggle(let generation):
                performToggle(generation)
            case .post(let events):
                events.forEach(post)
            case .toggleCapsLock:
                capsLock.toggle()
                DispatchQueue.main.async { [weak self] in self?.onCapsLockToggled?() }
            case .armLongPress(let press):
                queue.asyncAfter(deadline: .now() + settings.longPressDuration) { [weak self] in
                    guard let self else { return }
                    self.lock.withLock { self.run(self.core.longPressFired(press: press)) }
                }
            }
        }
    }

    private func performToggle(_ generation: Int) {
        // After repeated misses the shortcut is assumed to be off, and switching goes direct.
        let shortcut = shortcutMisses < 2 ? settings.shortcut : nil
        let baseline = knownSourceID
        flight = Flight(generation: generation, baseline: baseline, startedAt: .now(), usedShortcut: shortcut != nil)

        if let shortcut { Self.press(shortcut) }
        DispatchQueue.main.async { [weak self] in
            if shortcut == nil { InputSources.selectOther(than: baseline) }
            self?.startPolling(baseline: baseline)
        }
        queue.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in self?.timedOut(generation) }
    }

    private func timedOut(_ generation: Int) {
        lock.withLock {
            guard let current = flight, current.generation == generation,
                  core.inFlight == generation, !current.isSettling
            else { return }

            if current.usedShortcut {
                // The shortcut did nothing; it may be turned off. Try once more, directly.
                flight?.usedShortcut = false
                flight?.fellBack = true
                let baseline = current.baseline
                DispatchQueue.main.async { [weak self] in
                    InputSources.selectOther(than: baseline)
                    self?.startPolling(baseline: baseline)
                }
                queue.asyncAfter(deadline: .now() + Self.fallbackTimeout) { [weak self] in self?.timedOut(generation) }
                return
            }
            Log.engine.notice("switch timed out; releasing held keys")
            finish(generation)
        }
    }

    private func complete(_ generation: Int) {
        lock.withLock { finish(generation) }
    }

    private func finish(_ generation: Int) {
        guard core.inFlight == generation else { return }
        flight = nil
        run(core.switchCompleted(generation: generation))
    }

    private func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: .cgSessionEventTap)
    }

    /// Presses the system's input source shortcut. Posted at the HID level, which is
    /// where the system looks for its own shortcuts.
    static func press(_ shortcut: SystemShortcut) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: isDown) else { continue }
            event.flags = CGEventFlags(rawValue: shortcut.modifiers)
            event.setIntegerValueField(.eventSourceUserData, value: marker)
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Completion detection (main thread)

    /// The change notification can lag, so the selected source is also polled until it changes.
    private func startPolling(baseline: String) {
        pollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(2), repeating: .milliseconds(2), leeway: .microseconds(500))
        let deadline = DispatchTime.now() + Self.timeout + Self.fallbackTimeout
        timer.setEventHandler { [weak self, weak timer] in
            let id = InputSources.currentID()
            if id != baseline {
                InputSources.noteCurrent(id)
                self?.sourceDidChange(to: id)
                timer?.cancel()
            } else if DispatchTime.now() > deadline {
                timer?.cancel()
            }
        }
        pollTimer = timer
        timer.resume()
    }
}

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<SwitchEngine>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
}
