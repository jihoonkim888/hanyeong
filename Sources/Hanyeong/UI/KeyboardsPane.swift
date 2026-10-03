import HanyeongCore
import SwiftUI

struct KeyboardsPane: View {
    @EnvironmentObject private var model: AppModel
    /// The keyboard being edited; `nil` means the settings shared by all keyboards.
    @State private var selection: KeyboardIdentity?
    @State private var pendingImport: KarabinerImport.Result?
    @State private var importFailed = false

    init(selection: KeyboardIdentity? = nil) {
        _selection = State(initialValue: selection)
    }

    private static let commonHanyeongKeys: [HIDKey] = [.capsLock, .keyboard(0xE7), .keyboard(0xE6), .keyboard(0xE4), .keyboard(0x90)]

    private var profile: KeyboardProfile { model.profile(for: selection) }

    var body: some View {
        Form {
            if model.scan.isKarabinerActive {
                Section {
                    Label {
                        Text("Karabiner-Elements가 실행 중입니다")
                        Text("Karabiner가 키보드를 직접 제어하는 동안에는 여기서 바꾼 키가 적용되지 않습니다. Karabiner를 종료하면 바로 적용됩니다.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                    }
                }
            }

            Section {
                Picker("키보드", selection: $selection) {
                    Text("모든 키보드").tag(KeyboardIdentity?.none)
                    if !model.keyboardChoices.isEmpty {
                        Divider()
                        ForEach(model.keyboardChoices) { keyboard in
                            Text(keyboard.isConnected ? keyboard.name : "\(keyboard.name) (연결 안 됨)")
                                .tag(KeyboardIdentity?.some(keyboard.identity))
                        }
                    }
                }
            } footer: {
                Text(selection == nil
                    ? "연결된 모든 키보드에 적용됩니다."
                    : "이 키보드에는 ‘모든 키보드’의 설정에 아래 설정이 더해집니다. 같은 키를 양쪽에서 지정하면 이 키보드의 설정을 따릅니다.")
            }

            Section {
                LabeledContent("한영 키") {
                    KeyMenu(selection: hanyeongKey, noneTitle: selection == nil ? "없음" : "따로 지정 안 함", quickKeys: Self.commonHanyeongKeys)
                }
            } footer: {
                if selection != nil, let shared = model.config.allKeyboards.hanyeongKey {
                    Text("‘모든 키보드’의 한영 키(\(KeyCatalog.name(for: shared)))도 이 키보드에서 함께 동작합니다.")
                }
            }

            Section("키 바꾸기") {
                ForEach(profile.remaps) { mapping in
                    HStack {
                        KeyMenu(selection: binding(mapping.id, \.from))
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        KeyMenu(selection: binding(mapping.id, \.to))
                        Spacer()
                        Button {
                            model.updateProfile(for: selection) { $0.mappings.removeAll { $0.id == mapping.id } }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("이 키 바꾸기 삭제")
                    }
                }
                Button {
                    model.updateProfile(for: selection) { $0.mappings.append(KeyMapping(from: nil, to: nil)) }
                } label: {
                    Label("키 바꾸기 추가", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            if FileManager.default.fileExists(atPath: AppModel.karabinerConfigurationURL.path) {
                Section {
                    LabeledContent {
                        Button("가져오기…") {
                            pendingImport = model.readKarabinerConfiguration()
                            importFailed = pendingImport == nil
                        }
                    } label: {
                        Text("Karabiner-Elements 설정 가져오기")
                        Text("단순 키 바꾸기(simple modifications)를 키보드별로 옮겨 옵니다.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Karabiner 설정을 읽을 수 없습니다", isPresented: $importFailed) {
            Button("확인", role: .cancel) {}
        }
        .alert(
            "Karabiner 설정을 가져올까요?",
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            presenting: pendingImport
        ) { result in
            Button("가져오기") { model.apply(result) }
            Button("취소", role: .cancel) {}
        } message: { result in
            Text(importSummary(result))
        }
    }

    private var hanyeongKey: Binding<HIDKey?> {
        Binding(
            get: { profile.hanyeongKey },
            set: { key in model.updateProfile(for: selection) { $0.hanyeongKey = key } }
        )
    }

    private func binding(_ id: KeyMapping.ID, _ keyPath: WritableKeyPath<KeyMapping, HIDKey?>) -> Binding<HIDKey?> {
        Binding(
            get: { profile.mappings.first { $0.id == id }?[keyPath: keyPath] },
            set: { key in
                model.updateProfile(for: selection) { profile in
                    guard let index = profile.mappings.firstIndex(where: { $0.id == id }) else { return }
                    profile.mappings[index][keyPath: keyPath] = key
                }
            }
        )
    }

    private func importSummary(_ result: KarabinerImport.Result) -> String {
        var lines = ["‘\(result.profileName)’ 프로필에서 키 바꾸기 \(result.mappingCount)개를 찾았습니다. 같은 키에 대한 기존 설정은 가져온 내용으로 바뀝니다."]
        if result.skippedComplexRuleCount > 0 {
            lines.append("복합 규칙(complex modifications) \(result.skippedComplexRuleCount)개는 가져올 수 없습니다.")
        }
        if !result.unsupportedKeys.isEmpty {
            lines.append("지원하지 않는 키: \(result.unsupportedKeys.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n\n")
    }
}

/// A pull-down for choosing a key, grouped into submenus so the full keyboard stays manageable.
struct KeyMenu: View {
    @Binding var selection: HIDKey?
    /// When set, the menu offers an item with this title that clears the selection.
    var noneTitle: String?
    /// Keys offered at the top level, ahead of the grouped submenus.
    var quickKeys: [HIDKey] = []

    var body: some View {
        Menu {
            if let noneTitle {
                item(noneTitle, key: nil)
                Divider()
            }
            if !quickKeys.isEmpty {
                ForEach(quickKeys, id: \.self) { key in
                    item(KeyCatalog.name(for: key), key: key)
                }
                Divider()
            }
            ForEach(KeyGroup.allCases) { group in
                Menu(group.title) {
                    // F19 is the internal 한영 signal; it is assigned through the 한영 key menu only.
                    ForEach(KeyCatalog.keys(in: group).filter { $0.key != .hanyeong }) { info in
                        item(info.name, key: info.key)
                    }
                }
            }
        } label: {
            Text(selection.map(KeyCatalog.name(for:)) ?? noneTitle ?? "키 선택")
        }
        .fixedSize()
    }

    private func item(_ title: String, key: HIDKey?) -> some View {
        Toggle(title, isOn: Binding(get: { selection == key }, set: { if $0 { selection = key } }))
    }
}
