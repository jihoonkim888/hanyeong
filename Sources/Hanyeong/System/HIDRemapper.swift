import Foundation
import HanyeongCore
import IOKit
import IOKit.hid
import IOKit.hidsystem

struct ConnectedKeyboard: Identifiable, Hashable {
    var identity: KeyboardIdentity
    var name: String

    var id: KeyboardIdentity { identity }
}

struct KeyboardScan: Equatable {
    var keyboards: [ConnectedKeyboard] = []
    /// Karabiner-Elements is grabbing the keyboards, so mappings set on the physical
    /// devices have no effect until it is quit.
    var isKarabinerActive = false
}

/// Installs key remaps on keyboards through the HID `UserKeyMapping` property, the same
/// mechanism `hidutil` uses. The mapping lives in the HID driver, so it applies before
/// macOS's Caps Lock delay and needs no special permission. It is lost when a keyboard
/// reconnects or the Mac restarts, which is why it is re-applied on those events.
enum HIDRemapper {
    private static let mappingKey = "UserKeyMapping" as CFString
    private static let sourceKey = "HIDKeyboardModifierMappingSrc"
    private static let destinationKey = "HIDKeyboardModifierMappingDst"

    /// Makes every keyboard's mapping match `mappings(identity)`, touching only those that differ.
    @discardableResult
    static func apply(_ mappings: (KeyboardIdentity) -> [(from: HIDKey, to: HIDKey)]) -> KeyboardScan {
        visit { service, identity in
            let desired = Dictionary(mappings(identity).map { ($0.from.code, $0.to.code) }, uniquingKeysWith: { _, last in last })
            guard desired != installed(on: service) else { return }
            let value = desired.sorted { $0.key < $1.key }.map {
                [sourceKey: NSNumber(value: $0.key), destinationKey: NSNumber(value: $0.value)]
            }
            IOHIDServiceClientSetProperty(service, mappingKey, value as CFArray)
        }
    }

    /// Removes the mapping from every keyboard, returning them to their normal behaviour.
    @discardableResult
    static func clearAll() -> KeyboardScan {
        visit { service, _ in
            guard !installed(on: service).isEmpty else { return }
            IOHIDServiceClientSetProperty(service, mappingKey, [] as CFArray)
        }
    }

    static func scan() -> KeyboardScan {
        visit { _, _ in }
    }

    private static func visit(_ body: (IOHIDServiceClient, KeyboardIdentity) -> Void) -> KeyboardScan {
        // A fresh client each time: a long-lived one does not see keyboards connected later.
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
        var scan = KeyboardScan()
        for service in services {
            let isKeyboard = IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)) != 0
            guard isKeyboard else { continue }
            let product = IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) as? String ?? ""
            if product.localizedCaseInsensitiveContains("Karabiner") { scan.isKarabinerActive = true }

            let isBuiltIn = (IOHIDServiceClientCopyProperty(service, kIOHIDBuiltInKey as CFString) as? NSNumber)?.boolValue ?? false
            let identity = KeyboardIdentity(
                vendorID: (IOHIDServiceClientCopyProperty(service, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0,
                productID: (IOHIDServiceClientCopyProperty(service, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0,
                isBuiltIn: isBuiltIn
            )
            body(service, identity)

            if !scan.keyboards.contains(where: { $0.identity == identity }) {
                let name = isBuiltIn ? "내장 키보드" : (product.isEmpty ? "키보드 \(identity.vendorID):\(identity.productID)" : product)
                scan.keyboards.append(ConnectedKeyboard(identity: identity, name: name))
            }
        }
        scan.keyboards.sort { ($0.identity.isBuiltIn ? 0 : 1, $0.name) < ($1.identity.isBuiltIn ? 0 : 1, $1.name) }
        return scan
    }

    private static func installed(on service: IOHIDServiceClient) -> [UInt64: UInt64] {
        let entries = IOHIDServiceClientCopyProperty(service, mappingKey) as? [[String: NSNumber]] ?? []
        var table: [UInt64: UInt64] = [:]
        for entry in entries {
            guard let source = entry[sourceKey], let destination = entry[destinationKey] else { continue }
            table[source.uint64Value] = destination.uint64Value
        }
        return table
    }
}

/// Calls back on the main thread whenever a keyboard is connected or disconnected.
final class KeyboardWatcher {
    private let manager: IOHIDManager
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = [[kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard]]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            Unmanaged<KeyboardWatcher>.fromOpaque(context).takeUnretainedValue().onChange()
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, callback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, callback, context)
        // The manager is never opened: matching notifications alone need no Input Monitoring permission.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }
}
