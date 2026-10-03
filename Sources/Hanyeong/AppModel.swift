import AppKit
import Carbon
import Combine
import HanyeongCore

/// A keyboard that can be chosen in settings: connected now, or remembered from a saved profile.
struct KeyboardChoice: Identifiable, Hashable {
    var identity: KeyboardIdentity
    var name: String
    var isConnected: Bool

    var id: KeyboardIdentity { identity }
}

/// The app's state and the place where configuration is turned into system state.
/// Everything here runs on the main thread.
final class AppModel: ObservableObject {
    enum Status {
        case safeMode, disabled, needsPermission, secureInput, running
    }

    @Published var config: Configuration {
        didSet {
            guard config != oldValue, !isPreview else { return }
            ConfigurationStore.save(config)
            refresh(full: true)
        }
    }
    @Published var launchesAtLogin: Bool {
        didSet {
            guard launchesAtLogin != oldValue, !isPreview else { return }
            LoginItem.setEnabled(launchesAtLogin)
        }
    }
    @Published private(set) var isTrusted = false
    @Published private(set) var isEngineRunning = false
    @Published private(set) var isSecureInputActive = false
    @Published private(set) var isCapsLockOn = false
    @Published private(set) var source = InputSourceInfo(id: "", label: "A", isKorean: false)
    @Published private(set) var shortcut: SystemShortcut?
    @Published private(set) var scan = KeyboardScan()
    let isSafeMode: Bool

    private let isPreview: Bool
    private let capsLock = CapsLockController()
    private lazy var engine = SwitchEngine(capsLock: capsLock)
    private var watcher: KeyboardWatcher?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var tick = 0
    private var isSessionActive = true
    private var isSystemSettingsFrontmost = false
    private var installedSignature: String?

    init() {
        isPreview = false
        isSafeMode = Watchdog.isCrashLooping
        config = ConfigurationStore.load()
        launchesAtLogin = LoginItem.isEnabled
    }

    /// A model with fixed state and no side effects, for rendering the settings UI on its own.
    init(preview config: Configuration, keyboards: [ConnectedKeyboard], shortcut: SystemShortcut?, isTrusted: Bool = true) {
        isPreview = true
        isSafeMode = false
        self.config = config
        launchesAtLogin = true
        self.isTrusted = isTrusted
        isEngineRunning = isTrusted
        self.shortcut = shortcut
        scan = KeyboardScan(keyboards: keyboards)
    }

    var status: Status {
        if isSafeMode { return .safeMode }
        if !config.isEnabled { return .disabled }
        if !isTrusted || !isEngineRunning { return .needsPermission }
        if isSecureInputActive { return .secureInput }
        return .running
    }

    // MARK: - Lifecycle

    func start() {
        engine.onCapsLockToggled = { [weak self] in self?.refresh(full: false) }

        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: InputSources.changedNotification, object: nil, queue: .main) { [weak self] _ in
            self?.inputSourceChanged()
        })

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.didWake()
            })
        }
        // Key mappings are system-wide, so they are removed while another user has the screen.
        observers.append(workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isSessionActive = false
            self?.refresh(full: true)
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isSessionActive = true
            self?.refreshSoon()
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.isSystemSettingsFrontmost = app?.bundleIdentifier == SystemSettings.bundleIdentifier
            self?.refresh(full: false)
        })

        watcher = KeyboardWatcher { [weak self] in self?.refreshSoon() }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh(full: false) }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        InputSources.noteCurrent(InputSources.currentID())
        refresh(full: true)
    }

    func shutdown() {
        timer?.invalidate()
        engine.stop()
        HIDRemapper.clearAll()
    }

    // MARK: - Applying state

    /// Brings the event tap and key mappings in line with the configuration and the system.
    /// A light refresh checks cheap things every second; a full one also re-verifies the
    /// mapping on every keyboard.
    func refresh(full: Bool) {
        guard !isPreview else { return }
        tick += 1
        let full = full || tick % 10 == 0

        let wasTrusted = isTrusted, wasSecure = isSecureInputActive
        assign(\.isTrusted, Accessibility.isTrusted)
        assign(\.isSecureInputActive, IsSecureEventInputEnabled())
        if isTrusted != wasTrusted { Log.app.notice("accessibility permission: \(isTrusted)") }
        if isSecureInputActive != wasSecure { Log.app.notice("secure input: \(isSecureInputActive)") }
        assign(\.isCapsLockOn, capsLock.isOn)
        assign(\.source, InputSources.current())
        if full || tick % 5 == 0 { assign(\.shortcut, ShortcutReader.current()) }

        let isActive = config.isEnabled && !isSafeMode && isSessionActive
        if isActive && isTrusted {
            if engine.isRunning {
                engine.ensureEnabled()
            } else if !engine.start() {
                Log.app.error("could not create the event tap")
            }
        } else if engine.isRunning {
            engine.stop()
        }
        engine.update(SwitchEngine.Settings(
            options: .init(
                shiftTogglesCapsLock: config.shiftTogglesCapsLock,
                longPressTogglesCapsLock: config.longPressTogglesCapsLock
            ),
            longPressDuration: config.longPressDuration,
            shortcut: shortcut,
            passesTriggerThrough: isSystemSettingsFrontmost
        ))
        assign(\.isEngineRunning, engine.isRunning)

        // The 한영 key is only remapped while something will act on it: either this app's
        // tap, or the system itself when its shortcut is F19. Otherwise the key would go dead,
        // for instance in password fields, where taps receive no key events.
        let includeHanyeong = shortcut?.isBareF19 == true || (engine.isRunning && !isSecureInputActive)
        let signature = "\(isActive)/\(includeHanyeong)"
        if full || signature != installedSignature {
            if signature != installedSignature {
                Log.app.notice("key mappings: active=\(isActive), hanyeongKey=\(includeHanyeong)")
            }
            installedSignature = signature
            let config = self.config
            let scan = isActive
                ? HIDRemapper.apply { config.effectiveMappings(for: $0, includeHanyeong: includeHanyeong) }
                : HIDRemapper.clearAll()
            if scan.keyboards != self.scan.keyboards {
                Log.app.notice("keyboards: \(scan.keyboards.map(\.name).joined(separator: ", "))")
            }
            assign(\.scan, scan)
            rememberNames(of: scan.keyboards)
        }
    }

    /// Keyboards take a moment to become ready after connecting or waking, so check more than once.
    private func refreshSoon() {
        for delay in [0.2, 1.0, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refresh(full: true) }
        }
    }

    private func didWake() {
        Log.app.notice("woke from sleep")
        // A tap created before sleep can silently stop delivering events; start a fresh one.
        if engine.isRunning { engine.stop() }
        refresh(full: true)
        refreshSoon()
    }

    private func inputSourceChanged() {
        let id = InputSources.currentID()
        InputSources.noteCurrent(id)
        engine.sourceDidChange(to: id)
        assign(\.source, InputSources.current())
    }

    private func assign<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppModel, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    /// Replaces a placeholder name, such as one from an import, once the keyboard is seen.
    private func rememberNames(of keyboards: [ConnectedKeyboard]) {
        var devices = config.devices
        for keyboard in keyboards {
            guard let index = devices.firstIndex(where: { $0.identity == keyboard.identity }),
                  devices[index].name != keyboard.name
            else { continue }
            devices[index].name = keyboard.name
        }
        if devices != config.devices {
            DispatchQueue.main.async { [weak self] in self?.config.devices = devices }
        }
    }

    // MARK: - Settings support

    var keyboardChoices: [KeyboardChoice] {
        var choices = scan.keyboards.map { KeyboardChoice(identity: $0.identity, name: $0.name, isConnected: true) }
        for device in config.devices where !choices.contains(where: { $0.identity == device.identity }) {
            choices.append(KeyboardChoice(identity: device.identity, name: device.name, isConnected: false))
        }
        return choices
    }

    /// The profile for one keyboard, or for all keyboards when `identity` is `nil`.
    func profile(for identity: KeyboardIdentity?) -> KeyboardProfile {
        guard let identity else { return config.allKeyboards }
        return config.profile(for: identity)
    }

    func updateProfile(for identity: KeyboardIdentity?, _ change: (inout KeyboardProfile) -> Void) {
        guard let identity else {
            change(&config.allKeyboards)
            return
        }
        var devices = config.devices
        if let index = devices.firstIndex(where: { $0.identity == identity }) {
            change(&devices[index].profile)
            if devices[index].profile.isEmpty { devices.remove(at: index) }
        } else {
            var profile = KeyboardProfile()
            change(&profile)
            guard !profile.isEmpty else { return }
            let name = keyboardChoices.first { $0.identity == identity }?.name ?? "키보드"
            devices.append(DeviceProfile(identity: identity, name: name, profile: profile))
        }
        config.devices = devices
    }

    func requestPermission() {
        Accessibility.request()
        Accessibility.openSettings()
    }

    // MARK: - Karabiner import

    static let karabinerConfigurationURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/karabiner/karabiner.json")

    func readKarabinerConfiguration() -> KarabinerImport.Result? {
        guard let data = try? Data(contentsOf: Self.karabinerConfigurationURL) else { return nil }
        return try? KarabinerImport.parse(data)
    }

    /// Merges imported mappings into the configuration; an imported key replaces an existing mapping of the same key.
    func apply(_ imported: KarabinerImport.Result) {
        func merge(_ incoming: [KeyMapping], into profile: inout KeyboardProfile) {
            let keys = Set(incoming.compactMap(\.from))
            profile.mappings.removeAll { $0.from.map(keys.contains) ?? false }
            profile.mappings.append(contentsOf: incoming)
        }
        var updated = config
        merge(imported.allKeyboards, into: &updated.allKeyboards)
        for device in imported.devices {
            if let index = updated.devices.firstIndex(where: { $0.identity == device.identity }) {
                merge(device.profile.mappings, into: &updated.devices[index].profile)
            } else {
                updated.devices.append(device)
            }
        }
        config = updated
    }
}
