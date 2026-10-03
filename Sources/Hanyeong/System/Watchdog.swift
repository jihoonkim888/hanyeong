import Foundation

/// A small child process that brings the app back if it dies unexpectedly.
///
/// The app holds the write end of a pipe and the watchdog blocks reading the other end.
/// A normal quit writes one byte first. If the pipe closes without that byte, the app
/// crashed or was killed: the watchdog relaunches it. Key mappings are left in place
/// meanwhile, so the keyboard keeps its layout across the restart. After repeated
/// crashes it removes the mappings instead, so a broken build can never leave the
/// keyboard remapped with nothing handling it.
enum Watchdog {
    static let argument = "--watchdog"
    static let historyArgument = "--crash-history"

    private static let cleanExit = UInt8(ascii: "Q")
    private static let pipeDescriptor: Int32 = 3
    private static let crashWindow: TimeInterval = 60
    private static let crashLimit = 3

    /// Crash times handed over by the watchdog that relaunched this process.
    static var inheritedHistory: [TimeInterval] {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: historyArgument), index + 1 < arguments.count else { return [] }
        return parse(arguments[index + 1])
    }

    /// The app was relaunched so often that it should not install key mappings.
    static var isCrashLooping: Bool {
        recent(inheritedHistory).count >= crashLimit - 1
    }

    // MARK: - App side

    /// Starts the watchdog. Returns the descriptor to pass to `signalCleanExit`.
    static func spawn() -> Int32? {
        guard let executable = Bundle.main.executablePath else { return nil }
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else { return nil }
        let (readEnd, writeEnd) = (descriptors[0], descriptors[1])

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        // dup2 onto the same number would not mark the descriptor as inherited.
        if readEnd == pipeDescriptor {
            posix_spawn_file_actions_addinherit_np(&actions, readEnd)
        } else {
            posix_spawn_file_actions_adddup2(&actions, readEnd, pipeDescriptor)
        }
        for standard in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            posix_spawn_file_actions_addinherit_np(&actions, standard)
        }

        // Only the descriptors named above reach the child; in particular not the write end,
        // which would keep the pipe open after the app dies.
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

        let history = inheritedHistory.map { String(Int($0)) }.joined(separator: ",")
        let arguments = [executable, argument, Bundle.main.bundlePath, history]
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable, &actions, &attributes, argv, environ)
        close(readEnd)
        guard status == 0 else {
            close(writeEnd)
            return nil
        }
        _ = fcntl(writeEnd, F_SETFD, FD_CLOEXEC)
        return writeEnd
    }

    static func signalCleanExit(_ descriptor: Int32?) {
        guard let descriptor else { return }
        var byte = cleanExit
        _ = write(descriptor, &byte, 1)
        close(descriptor)
    }

    // MARK: - Watchdog side

    static func run() -> Never {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: argument), index + 2 < arguments.count else { exit(2) }
        let bundlePath = arguments[index + 1]
        let history = parse(arguments[index + 2])

        var byte: UInt8 = 0
        var count = read(pipeDescriptor, &byte, 1)
        while count < 0 && errno == EINTR { count = read(pipeDescriptor, &byte, 1) }
        if count == 1 && byte == cleanExit { exit(0) }

        let crashes = recent(history) + [Date().timeIntervalSince1970]
        if crashes.count >= crashLimit {
            HIDRemapper.clearAll()
            Log.app.error("watchdog: app exited unexpectedly \(crashes.count) times in a minute; removed key mappings and stopped relaunching")
            Log.flush()
            exit(0)
        }
        Log.app.error("watchdog: app exited unexpectedly; relaunching (\(crashes.count) of \(crashLimit))")
        Log.flush()

        // Give the system a moment to finish tearing the old process down.
        usleep(500_000)
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = [bundlePath, "--args", historyArgument, crashes.map { String(Int($0)) }.joined(separator: ",")]
        try? open.run()
        open.waitUntilExit()
        exit(0)
    }

    private static func parse(_ text: String) -> [TimeInterval] {
        text.split(separator: ",").compactMap { TimeInterval($0) }
    }

    private static func recent(_ history: [TimeInterval]) -> [TimeInterval] {
        let now = Date().timeIntervalSince1970
        return history.filter { now - $0 < crashWindow }
    }
}
