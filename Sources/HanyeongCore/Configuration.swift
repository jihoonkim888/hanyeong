import Foundation

/// Identifies a physical keyboard model. The built-in keyboard is matched by its
/// built-in flag because its vendor/product IDs differ between Mac models.
public struct KeyboardIdentity: Hashable, Codable, Sendable {
    public var vendorID: Int
    public var productID: Int
    public var isBuiltIn: Bool

    public init(vendorID: Int, productID: Int, isBuiltIn: Bool = false) {
        self.vendorID = isBuiltIn ? 0 : vendorID
        self.productID = isBuiltIn ? 0 : productID
        self.isBuiltIn = isBuiltIn
    }

    public static let builtIn = KeyboardIdentity(vendorID: 0, productID: 0, isBuiltIn: true)
}

public struct KeyMapping: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    /// `nil` while the row is still being filled in; incomplete rows are ignored.
    public var from: HIDKey?
    public var to: HIDKey?

    public init(id: UUID = UUID(), from: HIDKey? = nil, to: HIDKey? = nil) {
        self.id = id
        self.from = from
        self.to = to
    }
}

public struct KeyboardProfile: Hashable, Codable, Sendable {
    public var mappings: [KeyMapping]

    public init(mappings: [KeyMapping] = []) {
        self.mappings = mappings
    }

    /// The key that acts as the 한영 key in this profile.
    public var hanyeongKey: HIDKey? {
        get { mappings.first { $0.to == .hanyeong }?.from }
        set {
            mappings.removeAll { $0.to == .hanyeong }
            if let newValue {
                mappings.removeAll { $0.from == newValue }
                mappings.insert(KeyMapping(from: newValue, to: .hanyeong), at: 0)
            }
        }
    }

    /// Plain key-to-key remaps, excluding the 한영 key.
    public var remaps: [KeyMapping] { mappings.filter { $0.to != .hanyeong } }

    public var isEmpty: Bool { mappings.isEmpty }
}

public struct DeviceProfile: Identifiable, Hashable, Codable, Sendable {
    public var identity: KeyboardIdentity
    public var name: String
    public var profile: KeyboardProfile

    public var id: KeyboardIdentity { identity }

    public init(identity: KeyboardIdentity, name: String, profile: KeyboardProfile = KeyboardProfile()) {
        self.identity = identity
        self.name = name
        self.profile = profile
    }
}

public struct Configuration: Equatable, Codable, Sendable {
    public var isEnabled = true
    public var allKeyboards = KeyboardProfile(mappings: [KeyMapping(from: .capsLock, to: .hanyeong)])
    public var devices: [DeviceProfile] = []
    public var shiftTogglesCapsLock = true
    public var longPressTogglesCapsLock = true
    public var longPressDuration: Double = 0.4
    public var showsMenuBarItem = true

    public init() {}

    // Decoded field by field so that a file written by an older version still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Configuration()
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        allKeyboards = try c.decodeIfPresent(KeyboardProfile.self, forKey: .allKeyboards) ?? defaults.allKeyboards
        devices = try c.decodeIfPresent([DeviceProfile].self, forKey: .devices) ?? defaults.devices
        shiftTogglesCapsLock = try c.decodeIfPresent(Bool.self, forKey: .shiftTogglesCapsLock) ?? defaults.shiftTogglesCapsLock
        longPressTogglesCapsLock = try c.decodeIfPresent(Bool.self, forKey: .longPressTogglesCapsLock) ?? defaults.longPressTogglesCapsLock
        longPressDuration = try c.decodeIfPresent(Double.self, forKey: .longPressDuration) ?? defaults.longPressDuration
        showsMenuBarItem = try c.decodeIfPresent(Bool.self, forKey: .showsMenuBarItem) ?? defaults.showsMenuBarItem
    }

    public func profile(for identity: KeyboardIdentity) -> KeyboardProfile {
        devices.first { $0.identity == identity }?.profile ?? KeyboardProfile()
    }

    /// The mapping to install on one keyboard: the all-keyboards profile, overridden
    /// key by key by that keyboard's own profile. Sorted so the result is stable.
    public func effectiveMappings(for identity: KeyboardIdentity, includeHanyeong: Bool) -> [(from: HIDKey, to: HIDKey)] {
        var table: [HIDKey: HIDKey] = [:]
        for mapping in allKeyboards.mappings + profile(for: identity).mappings {
            guard let from = mapping.from, let to = mapping.to else { continue }
            table[from] = to
        }
        return table
            .filter { $0.key != $0.value && (includeHanyeong || $0.value != .hanyeong) }
            .sorted { $0.key.code < $1.key.code }
            .map { (from: $0.key, to: $0.value) }
    }
}
