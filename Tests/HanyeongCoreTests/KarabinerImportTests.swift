import Foundation
import Testing
@testable import HanyeongCore

private let sample = #"""
{
    "profiles": [
        {
            "name": "Unselected",
            "simple_modifications": [
                { "from": { "key_code": "a" }, "to": [{ "key_code": "b" }] }
            ]
        },
        {
            "name": "Main",
            "selected": true,
            "complex_modifications": { "rules": [{ "description": "one" }, { "description": "two" }] },
            "devices": [
                {
                    "identifiers": { "is_keyboard": true, "product_id": 5678, "vendor_id": 1234 },
                    "simple_modifications": [
                        { "from": { "key_code": "left_command" }, "to": [{ "key_code": "left_option" }] },
                        { "from": { "key_code": "right_control" }, "to": [{ "apple_vendor_top_case_key_code": "keyboard_fn" }] },
                        { "from": { "key_code": "right_option" }, "to": [{ "key_code": "f19" }] }
                    ]
                },
                { "identifiers": { "is_keyboard": true, "product_id": 1, "vendor_id": 2 }, "simple_modifications": [] }
            ],
            "simple_modifications": [
                { "from": { "key_code": "caps_lock" }, "to": [{ "key_code": "f19" }] },
                { "from": { "key_code": "non_us_pound" }, "to": { "key_code": "grave_accent_and_tilde" } },
                { "from": { "key_code": "f5" }, "to": [{ "consumer_key_code": "play_or_pause" }] }
            ]
        }
    ]
}
"""#

@Suite struct KarabinerImportTests {
    @Test func importsTheSelectedProfile() throws {
        let result = try KarabinerImport.parse(Data(sample.utf8))
        #expect(result.profileName == "Main")
        #expect(result.skippedComplexRuleCount == 2)
    }

    @Test func f19TargetsBecomeTheHanyeongKey() throws {
        let result = try KarabinerImport.parse(Data(sample.utf8))
        #expect(KeyboardProfile(mappings: result.allKeyboards).hanyeongKey == .capsLock)
        #expect(result.devices.first?.profile.hanyeongKey == .keyboard(0xE6))
    }

    @Test func convertsGlobalAndPerDeviceMappings() throws {
        let result = try KarabinerImport.parse(Data(sample.utf8))
        #expect(result.allKeyboards.map { [$0.from?.code, $0.to?.code] } == [
            [0x7_0000_0039, 0x7_0000_006E],
            [0x7_0000_0032, 0x7_0000_0035],
        ])
        #expect(result.devices.count == 1)
        #expect(result.devices[0].identity == KeyboardIdentity(vendorID: 1234, productID: 5678))
        #expect(result.devices[0].profile.mappings.map { $0.to } == [.keyboard(0xE2), .fn, .hanyeong])
        #expect(result.mappingCount == 5)
    }

    @Test func reportsKeysItCannotMap() throws {
        let result = try KarabinerImport.parse(Data(sample.utf8))
        #expect(result.unsupportedKeys == ["play_or_pause"])
    }

    @Test func rejectsUnrelatedJSON() {
        #expect(throws: KarabinerImport.ImportError.self) {
            try KarabinerImport.parse(Data(#"{"hello": 1}"#.utf8))
        }
    }

    @Test func everyCatalogKeyHasAUniqueCodeAndName() {
        #expect(Set(KeyCatalog.all.map(\.key)).count == KeyCatalog.all.count)
        #expect(Set(KeyCatalog.all.map(\.karabinerName)).count == KeyCatalog.all.count)
        #expect(KeyCatalog.key(karabinerName: "fn") == .fn)
        #expect(KeyCatalog.key(karabinerName: "right_gui") == .keyboard(0xE7))
        #expect(KeyCatalog.name(for: .hanyeong) == "한영 전환")
    }
}
