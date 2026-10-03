import Foundation
import IOKit
import IOKit.hidsystem

/// Reads and sets the Caps Lock state directly. Needed because a remapped Caps Lock key
/// no longer reaches the system as Caps Lock.
final class CapsLockController {
    private var connection: io_connect_t = 0

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection)
        IOObjectRelease(service)
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    var isOn: Bool {
        var state = false
        IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &state)
        return state
    }

    func toggle() {
        IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), !isOn)
    }
}
