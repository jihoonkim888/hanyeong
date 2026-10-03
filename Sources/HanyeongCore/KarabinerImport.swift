import Foundation

/// Converts the simple modifications of a Karabiner-Elements `karabiner.json` into 한영 profiles.
public enum KarabinerImport {
    public struct Result: Equatable, Sendable {
        public var profileName: String
        public var allKeyboards: [KeyMapping]
        public var devices: [DeviceProfile]
        /// Complex modification rules cannot be expressed as key-to-key remaps and are skipped.
        public var skippedComplexRuleCount: Int
        /// Key names that have no equivalent here, such as media keys.
        public var unsupportedKeys: [String]

        public var mappingCount: Int {
            allKeyboards.count + devices.reduce(0) { $0 + $1.profile.mappings.count }
        }
    }

    public enum ImportError: Error {
        case notKarabinerConfiguration
    }

    public static func parse(_ data: Data) throws -> Result {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = root["profiles"] as? [[String: Any]], !profiles.isEmpty
        else { throw ImportError.notKarabinerConfiguration }

        let profile = profiles.first { ($0["selected"] as? Bool) == true } ?? profiles[0]
        var unsupported: [String] = []

        func mappings(_ value: Any?) -> [KeyMapping] {
            (value as? [[String: Any]] ?? []).compactMap { entry in
                // Older files store `to` as a single object rather than an array.
                let target = (entry["to"] as? [[String: Any]])?.first ?? entry["to"] as? [String: Any]
                guard let from = key(entry["from"] as? [String: Any], &unsupported),
                      let to = key(target, &unsupported)
                else { return nil }
                return KeyMapping(from: from, to: to)
            }
        }

        let devices = (profile["devices"] as? [[String: Any]] ?? []).compactMap { device -> DeviceProfile? in
            let identifiers = device["identifiers"] as? [String: Any] ?? [:]
            let converted = mappings(device["simple_modifications"])
            guard !converted.isEmpty else { return nil }
            let isBuiltIn = identifiers["is_built_in_keyboard"] as? Bool ?? false
            let vendorID = identifiers["vendor_id"] as? Int ?? 0
            let productID = identifiers["product_id"] as? Int ?? 0
            guard isBuiltIn || vendorID != 0 || productID != 0 else { return nil }
            return DeviceProfile(
                identity: KeyboardIdentity(vendorID: vendorID, productID: productID, isBuiltIn: isBuiltIn),
                name: isBuiltIn ? "내장 키보드" : "키보드 \(vendorID):\(productID)",
                profile: KeyboardProfile(mappings: converted)
            )
        }

        let rules = (profile["complex_modifications"] as? [String: Any])?["rules"] as? [Any] ?? []
        return Result(
            profileName: profile["name"] as? String ?? "",
            allKeyboards: mappings(profile["simple_modifications"]),
            devices: devices,
            skippedComplexRuleCount: rules.count,
            unsupportedKeys: unsupported
        )
    }

    private static func key(_ entry: [String: Any]?, _ unsupported: inout [String]) -> HIDKey? {
        guard let entry else { return nil }
        let keyFields = ["key_code", "apple_vendor_top_case_key_code", "apple_vendor_keyboard_key_code", "consumer_key_code", "pointing_button"]
        for field in keyFields {
            guard let name = entry[field] as? String else { continue }
            if let key = KeyCatalog.key(karabinerName: name) { return key }
            if !unsupported.contains(name) { unsupported.append(name) }
            return nil
        }
        return nil
    }
}
