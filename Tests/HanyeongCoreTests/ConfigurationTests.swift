import Foundation
import Testing
@testable import HanyeongCore

private let rightOption = HIDKey.keyboard(0xE6)
private let leftCommand = HIDKey.keyboard(0xE3)
private let leftOption = HIDKey.keyboard(0xE2)
private let external = KeyboardIdentity(vendorID: 1234, productID: 5678)

private func pairs(_ mappings: [(from: HIDKey, to: HIDKey)]) -> [[UInt64]] {
    mappings.map { [$0.from.code, $0.to.code] }
}

@Suite struct ConfigurationTests {
    @Test func usageCodeMatchesTheHIDUtilFormat() {
        #expect(HIDKey.capsLock.code == 0x7_0000_0039)
        #expect(HIDKey.hanyeong.code == 0x7_0000_006E)
        #expect(HIDKey.fn.code == 0xFF_0000_0003)
        #expect(HIDKey(code: 0xFF_0000_0003) == .fn)
    }

    @Test func defaultMapsCapsLockToHanyeong() {
        let config = Configuration()
        #expect(config.allKeyboards.hanyeongKey == .capsLock)
        #expect(pairs(config.effectiveMappings(for: .builtIn, includeHanyeong: true)) == [[HIDKey.capsLock.code, HIDKey.hanyeong.code]])
    }

    @Test func hanyeongMappingsAreDroppedWhenNotIncluded() {
        var config = Configuration()
        config.allKeyboards.mappings.append(KeyMapping(from: leftCommand, to: leftOption))
        #expect(pairs(config.effectiveMappings(for: .builtIn, includeHanyeong: false)) == [[leftCommand.code, leftOption.code]])
    }

    @Test func deviceProfileAddsToAndOverridesAllKeyboards() {
        var config = Configuration()
        config.allKeyboards.mappings.append(KeyMapping(from: leftCommand, to: leftOption))
        config.devices = [DeviceProfile(identity: external, name: "External", profile: KeyboardProfile(mappings: [
            KeyMapping(from: rightOption, to: .hanyeong),
            KeyMapping(from: leftCommand, to: .fn),
        ]))]

        let onExternal = Dictionary(uniqueKeysWithValues: config.effectiveMappings(for: external, includeHanyeong: true).map { ($0.from, $0.to) })
        #expect(onExternal == [.capsLock: .hanyeong, rightOption: .hanyeong, leftCommand: .fn])

        let onBuiltIn = Dictionary(uniqueKeysWithValues: config.effectiveMappings(for: .builtIn, includeHanyeong: true).map { ($0.from, $0.to) })
        #expect(onBuiltIn == [.capsLock: .hanyeong, leftCommand: leftOption])
    }

    @Test func incompleteAndIdentityRowsAreIgnored() {
        var config = Configuration()
        config.allKeyboards.mappings = [
            KeyMapping(from: leftCommand, to: nil),
            KeyMapping(from: nil, to: leftOption),
            KeyMapping(from: leftOption, to: leftOption),
        ]
        #expect(config.effectiveMappings(for: .builtIn, includeHanyeong: true).isEmpty)
    }

    @Test func settingTheHanyeongKeyReplacesThePreviousOne() {
        var profile = KeyboardProfile(mappings: [
            KeyMapping(from: .capsLock, to: .hanyeong),
            KeyMapping(from: rightOption, to: leftOption),
        ])
        profile.hanyeongKey = rightOption
        #expect(profile.hanyeongKey == rightOption)
        #expect(profile.mappings.count == 1)

        profile.hanyeongKey = nil
        #expect(profile.mappings.isEmpty)
    }

    @Test func builtInIdentityIgnoresVendorAndProduct() {
        #expect(KeyboardIdentity(vendorID: 1452, productID: 835, isBuiltIn: true) == .builtIn)
    }

    @Test func configurationSurvivesARoundTrip() throws {
        var config = Configuration()
        config.longPressDuration = 0.7
        config.devices = [DeviceProfile(identity: external, name: "External", profile: KeyboardProfile(mappings: [KeyMapping(from: rightOption, to: .hanyeong)]))]
        let decoded = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
    }

    @Test func missingFieldsFallBackToDefaults() throws {
        let decoded = try JSONDecoder().decode(Configuration.self, from: Data(#"{"isEnabled": false}"#.utf8))
        #expect(decoded.isEnabled == false)
        #expect(decoded.allKeyboards.hanyeongKey == .capsLock)
        #expect(decoded.longPressDuration == 0.4)
    }
}

@Suite struct SystemShortcutTests {
    private func entry(enabled: Bool, _ parameters: [Int]) -> [String: Any] {
        ["enabled": enabled, "value": ["type": "standard", "parameters": parameters]]
    }

    @Test func untouchedPreferencesMeanControlSpace() {
        let shortcut = SystemShortcut.resolve(symbolicHotKeys: nil)
        #expect(shortcut == SystemShortcut(kind: .previousSource, keyCode: 49, modifiers: 0x40000))
        #expect(shortcut?.displayName == "⌃Space")
        #expect(shortcut?.isBareF19 == false)
    }

    @Test func fallsBackToNextSourceWhenPreviousIsDisabled() {
        // "Previous source" turned off and "next source" bound to F19.
        let shortcut = SystemShortcut.resolve(symbolicHotKeys: [
            "60": entry(enabled: false, [32, 49, 262144]),
            "61": entry(enabled: true, [65535, 80, 8388608]),
        ])
        #expect(shortcut == SystemShortcut(kind: .nextSource, keyCode: 80, modifiers: 0x800000))
        #expect(shortcut?.displayName == "F19")
        #expect(shortcut?.isBareF19 == true)
    }

    @Test func noShortcutWhenBothAreDisabled() {
        let shortcut = SystemShortcut.resolve(symbolicHotKeys: [
            "60": entry(enabled: false, [32, 49, 262144]),
            "61": entry(enabled: false, [32, 49, 786432]),
        ])
        #expect(shortcut == nil)
    }

    @Test func modifiedF19IsNotBare() {
        let shortcut = SystemShortcut(kind: .previousSource, keyCode: 80, modifiers: 0x800000 | 0x100000)
        #expect(shortcut.isBareF19 == false)
        #expect(shortcut.displayName == "⌘F19")
    }
}
