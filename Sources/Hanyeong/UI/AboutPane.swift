import SwiftUI

struct AboutPane: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("한영").font(.title2.weight(.semibold))
                        Text("버전 \(AppInfo.version)").foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Text("한영 키를 누르는 즉시 언어를 바꾸고, 전환되는 동안 친 글자를 놓치지 않는 macOS 한영 전환 앱입니다.")
                Link(destination: AppInfo.repositoryURL) {
                    LabeledContent("GitHub") {
                        Image(systemName: "arrow.up.forward")
                    }
                }
                LabeledContent("라이선스", value: "MIT")
            }
        }
        .formStyle(.grouped)
    }
}
