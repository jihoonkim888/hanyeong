import SwiftUI

struct GeneralPane: View {
    @EnvironmentObject private var model: AppModel

    private static let longPressDurations: [Double] = [0.3, 0.4, 0.5, 0.7, 1.0]

    var body: some View {
        Form {
            Section {
                StatusRow(status: model.status)
                Toggle("한영 사용", isOn: $model.config.isEnabled)
            }

            Section {
                Toggle("Shift + 한영 키로 켜고 끄기", isOn: $model.config.shiftTogglesCapsLock)
                Toggle("한영 키를 길게 눌러 켜고 끄기", isOn: $model.config.longPressTogglesCapsLock)
                if model.config.longPressTogglesCapsLock {
                    Picker("길게 누르는 시간", selection: $model.config.longPressDuration) {
                        ForEach(Self.longPressDurations, id: \.self) { duration in
                            Text("\(duration, format: .number.precision(.fractionLength(1)))초").tag(duration)
                        }
                    }
                }
            } header: {
                Text("대문자 고정 (Caps Lock)")
            } footer: {
                Text("한영 키는 누르는 즉시 언어를 바꿉니다. 길게 누른 것으로 확인되면 언어를 되돌리고 대문자 고정을 바꿉니다.")
            }

            Section {
                LabeledContent("입력 소스 단축키") {
                    Text(model.shortcut.map { "\($0.displayName) · \($0.kindName)" } ?? "꺼져 있음")
                }
                if model.shortcut?.isBareF19 != true {
                    LabeledContent {
                        Button("키보드 설정 열기") { SystemSettings.openKeyboard() }
                    } label: {
                        Text("권장: 단축키를 한영 키로 지정")
                        Text("키보드 단축키 > 입력 소스에서 ‘이전 입력 소스 선택’을 한영 키로 다시 지정하면, 암호를 입력할 때나 한영이 꺼져 있을 때도 한영 키가 동작합니다.")
                    }
                }
            } header: {
                Text("시스템 연동")
            } footer: {
                Text(shortcutFootnote)
            }

            Section {
                Toggle("로그인할 때 열기", isOn: $model.launchesAtLogin)
                Toggle(isOn: $model.config.showsMenuBarItem) {
                    Text("메뉴 막대에 현재 언어 표시")
                    if !model.config.showsMenuBarItem {
                        Text("이 창은 한영을 다시 실행하면 열립니다.")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var shortcutFootnote: String {
        guard let shortcut = model.shortcut else {
            return "시스템의 입력 소스 단축키가 꺼져 있어 입력 소스를 직접 선택합니다."
        }
        if shortcut.isBareF19 {
            return "한영은 이 단축키를 대신 눌러 언어를 바꿉니다. 한영 키가 단축키로 지정되어 있어, 암호를 입력할 때나 한영이 꺼져 있을 때도 한영 키가 동작합니다."
        }
        return "한영은 이 단축키를 대신 눌러 언어를 바꿉니다."
    }
}

private struct StatusRow: View {
    @EnvironmentObject private var model: AppModel
    let status: AppModel.Status

    var body: some View {
        LabeledContent {
            switch status {
            case .needsPermission:
                Button("권한 허용…") { model.requestPermission() }
            case .safeMode:
                Button("다시 시작") { AppDelegate.relaunch() }
            default:
                EmptyView()
            }
        } label: {
            Label {
                Text(title)
                Text(detail)
            } icon: {
                Image(systemName: symbol)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, tint)
                    .font(.title2)
            }
        }
    }

    private var title: String {
        switch status {
        case .running: "동작 중"
        case .secureInput: "보안 입력 중"
        case .needsPermission: "손쉬운 사용 권한이 필요합니다"
        case .disabled: "꺼져 있음"
        case .safeMode: "안전 모드"
        }
    }

    private var detail: String {
        switch status {
        case .running: "한영 키를 누르는 즉시 전환하고, 전환되는 동안 친 글자는 새 언어로 입력합니다."
        case .secureInput: "암호 입력 중에는 키 입력을 받을 수 없어 시스템 기본 전환을 사용합니다."
        case .needsPermission: "한영 키를 받아 언어를 전환하려면 권한을 허용해야 합니다. 그때까지 키 바꾸기만 적용됩니다."
        case .disabled: "키 바꾸기와 한영 전환이 모두 해제되어 키보드가 원래대로 동작합니다."
        case .safeMode: "한영이 반복해서 예기치 않게 종료되어 키 매핑을 해제했습니다."
        }
    }

    private var symbol: String {
        switch status {
        case .running: "checkmark.circle.fill"
        case .secureInput: "lock.circle.fill"
        case .needsPermission, .safeMode: "exclamationmark.circle.fill"
        case .disabled: "pause.circle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .running: .green
        case .secureInput: .orange
        case .needsPermission, .safeMode: .orange
        case .disabled: .gray
        }
    }
}
