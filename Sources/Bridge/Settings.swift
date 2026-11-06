import AppKit
import BridgeCore
import KeyboardShortcuts
import ServiceManagement

extension KeyboardShortcuts.Name {
    static let freezeScreen = Self("freezeScreen")
}

enum Settings {
    static let endedChoices: [(title: String, seconds: Double)] = [("1 hour", 3600), ("24 hours", 24 * 3600), ("1 week", 7 * 24 * 3600), ("Never", 0)]
    static let appearances = ["System", "Light", "Dark"]

    static var endedAfter: Double {
        get { ProcessInfo.processInfo.environment["BRIDGE_ENDED_AFTER"].flatMap(Double.init) ?? Model.remembered("endedAfter") as? Double ?? 24 * 3600 }
        set { Model.remember(newValue, "endedAfter") }
    }

    static var arrivalSound: Bool {
        get { Model.remembered("arrivalSound") as? Bool ?? true }
        set { Model.remember(newValue, "arrivalSound") }
    }

    static var updateNotices: Bool {
        get { Model.remembered("updateNotices") as? Bool ?? true }
        set { Model.remember(newValue, "updateNotices") }
    }

    static var appearance: String {
        get { Model.remembered("appearance") as? String ?? "System" }
        set { Model.remember(newValue, "appearance"); applyAppearance() }
    }

    static func applyAppearance() {
        if Env.test { NSApp.appearance = NSAppearance(named: ProcessInfo.processInfo.environment["BRIDGE_APPEARANCE"] == "dark" ? .darkAqua : .aqua); return }
        switch appearance {
        case "Light": NSApp.appearance = NSAppearance(named: .aqua)
        case "Dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}

final class SettingsWindow: NSWindowController {
    let recorder = KeyboardShortcuts.RecorderCocoa(for: .freezeScreen)
    let login = NSButton(checkboxWithTitle: "Open at Login", target: nil, action: nil)
    let approve = NSButton(title: "Login Items…", target: nil, action: nil)
    let ended = NSPopUpButton()
    let sound = NSButton(checkboxWithTitle: "Sound when a bridge arrives", target: nil, action: nil)
    let updates = NSButton(checkboxWithTitle: "Tell me when a page is updated", target: nil, action: nil)
    let appearance = NSPopUpButton()

    init() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Bridge Settings"
        super.init(window: window)

        login.target = self
        login.action = #selector(toggleLogin)
        approve.target = self
        approve.action = #selector(openLoginItems)
        approve.controlSize = .small
        let loginRow = NSStackView(views: [login, approve])
        ended.addItems(withTitles: Settings.endedChoices.map(\.title))
        ended.selectItem(at: Settings.endedChoices.firstIndex { $0.seconds == Settings.endedAfter } ?? 1)
        ended.target = self
        ended.action = #selector(chooseEnded)
        sound.state = Settings.arrivalSound ? .on : .off
        sound.target = self
        sound.action = #selector(toggleSound)
        updates.state = Settings.updateNotices ? .on : .off
        updates.target = self
        updates.action = #selector(toggleUpdates)
        appearance.addItems(withTitles: Settings.appearances)
        appearance.selectItem(withTitle: Settings.appearance)
        appearance.target = self
        appearance.action = #selector(chooseAppearance)
        let separator = NSBox()
        separator.boxType = .separator

        let grid = NSGridView(views: [
            [label("Freeze the screen:"), recorder],
            [NSGridCell.emptyContentView, hint("Starts a new bridge from any app.")],
            [NSGridCell.emptyContentView, loginRow],
            [separator],
            [label("Clear ended sessions after:"), ended],
            [NSGridCell.emptyContentView, hint("Bridges whose agent is gone are crossed off.")],
            [label("Notifications:"), sound],
            [NSGridCell.emptyContentView, updates],
            [label("Appearance:"), appearance],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.column(at: 1).width = 240
        grid.row(at: 3).mergeCells(in: NSRange(location: 0, length: 2))
        grid.row(at: 2).topPadding = 4
        grid.row(at: 3).topPadding = 6
        grid.row(at: 3).bottomPadding = 6
        grid.row(at: 6).topPadding = 6
        grid.row(at: 8).topPadding = 6
        for row in [1, 5] { grid.row(at: row).topPadding = -4 }
        grid.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            separator.widthAnchor.constraint(equalTo: grid.widthAnchor),
            recorder.widthAnchor.constraint(equalToConstant: 160),
        ])
        window.contentView = content
        NotificationCenter.default.addObserver(self, selector: #selector(updateLogin), name: NSWindow.didBecomeKeyNotification, object: window)
        updateLogin()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        if window?.isVisible == false { window?.center() }
        updateLogin()
        super.showWindow(sender)
        window?.makeFirstResponder(nil)
    }

    private func label(_ text: String) -> NSTextField { NSTextField(labelWithString: text) }

    private func hint(_ text: String) -> NSTextField {
        let hint = NSTextField(wrappingLabelWithString: text)
        hint.preferredMaxLayoutWidth = 240
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        return hint
    }

    @objc func chooseEnded() { Settings.endedAfter = Settings.endedChoices[ended.indexOfSelectedItem].seconds }
    @objc func toggleSound() { Settings.arrivalSound = sound.state == .on }
    @objc func toggleUpdates() { Settings.updateNotices = updates.state == .on }
    @objc func chooseAppearance() { Settings.appearance = appearance.titleOfSelectedItem ?? "System" }

    @objc func toggleLogin() {
        try? login.state == .on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        updateLogin()
    }

    @objc func updateLogin() {
        let status = SMAppService.mainApp.status
        login.state = status == .enabled || status == .requiresApproval ? .on : .off
        approve.isHidden = status != .requiresApproval
    }

    @objc func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

    func state() -> JSONValue {
        .object([
            "visible": .bool(window?.isVisible ?? false), "ended": .string(ended.titleOfSelectedItem ?? ""),
            "sound": .bool(sound.state == .on), "updates": .bool(updates.state == .on), "appearance": .string(appearance.titleOfSelectedItem ?? ""),
            "shortcut": .string(KeyboardShortcuts.getShortcut(for: .freezeScreen)?.description ?? ""),
        ])
    }
}
