import HanyeongCore
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, keyboards, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "일반"
        case .keyboards: "키보드"
        case .about: "정보"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .keyboards: "keyboard.fill"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .keyboards: .blue
        case .about: .indigo
        }
    }
}

struct SettingsView: View {
    @State var pane: SettingsPane? = .general
    /// The keyboard the keyboards pane opens on; `nil` for the settings shared by all keyboards.
    var keyboard: KeyboardIdentity?

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    PaneIcon(symbol: pane.symbol, tint: pane.tint)
                }
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch pane ?? .general {
                case .general: GeneralPane()
                case .keyboards: KeyboardsPane(selection: keyboard)
                case .about: AboutPane()
                }
            }
        }
        .frame(minWidth: 680, minHeight: 460)
        .background(WindowTitle(title: (pane ?? .general).title))
    }
}

/// Sets the title of the window this view is in. The settings window is created in AppKit,
/// where `navigationTitle` does not reach the title bar.
private struct WindowTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        // The view is not in a window yet during the first update.
        DispatchQueue.main.async { view.window?.title = title }
    }
}

/// A sidebar icon in the System Settings style: a white symbol on a tinted rounded square.
struct PaneIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
