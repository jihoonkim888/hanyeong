import AppKit
import Combine

/// The menu bar item: shows the current language and offers the few actions needed day to day.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let showSettings: () -> Void
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "한영 사용", action: #selector(toggleEnabled), keyEquivalent: "")
    private var subscription: AnyCancellable?

    init(model: AppModel, showSettings: @escaping () -> Void) {
        self.model = model
        self.showSettings = showSettings
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        enabledItem.target = self
        menu.addItem(enabledItem)
        let settings = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "한영 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        // objectWillChange fires before the new values are set, so read them on the next turn.
        subscription = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update() }
        update()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        update()
    }

    private func update() {
        item.isVisible = model.config.showsMenuBarItem
        enabledItem.state = model.config.isEnabled ? .on : .off

        let image: NSImage?
        switch model.status {
        case .running, .secureInput:
            image = model.isCapsLockOn
                ? NSImage(systemSymbolName: "capslock.fill", accessibilityDescription: "대문자 고정")
                : Self.glyph(model.source.label, filled: model.source.isKorean)
            statusLine.title = model.status == .running ? "한영 전환 동작 중" : "보안 입력 중 — 시스템 기본 전환 사용"
        case .needsPermission:
            image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "권한 필요")
            statusLine.title = "손쉬운 사용 권한이 필요합니다"
        case .disabled:
            image = Self.glyph(model.source.label, filled: false)
            statusLine.title = "한영 꺼져 있음"
        case .safeMode:
            image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "안전 모드")
            statusLine.title = "안전 모드 — 키 매핑 해제됨"
        }
        item.button?.image = image
        item.button?.appearsDisabled = model.status == .disabled
    }

    /// Draws the language in a small rounded box, in the style of the system input menu:
    /// outlined for Latin, filled for Korean.
    private static func glyph(_ text: String, filled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 21, height: 16), flipped: false) { bounds in
            let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.25, dy: 0.75), xRadius: 3.5, yRadius: 3.5)
            let text = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.black,
            ])
            let size = text.size()
            let origin = NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)

            NSColor.black.set()
            if filled {
                box.fill()
                NSGraphicsContext.current?.compositingOperation = .destinationOut
            } else {
                box.lineWidth = 1.25
                box.stroke()
            }
            text.draw(at: origin)
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func toggleEnabled() {
        model.config.isEnabled.toggle()
    }

    @objc private func openSettings() {
        showSettings()
    }
}
