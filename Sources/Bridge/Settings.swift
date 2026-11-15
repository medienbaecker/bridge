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
    let loginError = SettingsWindow.hint("")
    let denied = NSStackView()
    var grid: NSGridView!

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

        let open = NSButton(title: "System Settings…", target: self, action: #selector(openNotifications))
        open.controlSize = .small
        denied.orientation = .vertical
        denied.alignment = .leading
        denied.spacing = 6
        denied.addArrangedSubview(Self.hint("Notifications are turned off for Bridge in System Settings."))
        denied.addArrangedSubview(open)

        let grid = NSGridView(views: [
            [label("Point at the screen:"), recorder],
            [NSGridCell.emptyContentView, Self.hint("Starts a new bridge from any app.")],
            [NSGridCell.emptyContentView, loginRow],
            [NSGridCell.emptyContentView, loginError],
            [separator],
            [label("Clear ended sessions after:"), ended],
            [NSGridCell.emptyContentView, Self.hint("Bridges whose agent is gone are crossed off.")],
            [label("Notifications:"), sound],
            [NSGridCell.emptyContentView, updates],
            [NSGridCell.emptyContentView, denied],
            [label("Appearance:"), appearance],
        ])
        self.grid = grid
        grid.cell(for: loginError)?.row?.isHidden = true
        grid.cell(for: denied)?.row?.isHidden = true
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.column(at: 1).width = 240
        grid.row(at: 4).mergeCells(in: NSRange(location: 0, length: 2))
        grid.row(at: 2).topPadding = 4
        grid.row(at: 4).topPadding = 6
        grid.row(at: 4).bottomPadding = 6
        grid.row(at: 7).topPadding = 6
        grid.row(at: 10).topPadding = 6
        for row in [1, 3, 6] { grid.row(at: row).topPadding = -4 }
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
        if let window, !window.isVisible {
            window.layoutIfNeeded()
            let screen = ((NSApp.delegate as? AppDelegate)?.window.window?.screen ?? window.screen)?.visibleFrame ?? .zero
            window.setFrameOrigin(NSPoint(x: screen.midX - window.frame.width / 2, y: screen.midY - window.frame.height / 2))
        }
        updateLogin()
        Task { show(denied, await Notify.denied()) }
        super.showWindow(sender)
        window?.makeFirstResponder(nil)
    }

    private func label(_ text: String) -> NSTextField { NSTextField(labelWithString: text) }

    private func show(_ view: NSView, _ shown: Bool) {
        grid.cell(for: view)?.row?.isHidden = !shown
    }

    @objc func openNotifications() { Notify.openSystemSettings() }

    private static func hint(_ text: String) -> NSTextField {
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
        do {
            if Env.test { throw CocoaError(.featureUnsupported) }
            try login.state == .on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            show(loginError, false)
        } catch {
            loginError.stringValue = "Open at Login could not be changed: \(error.localizedDescription)"
            show(loginError, true)
        }
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
            "loginError": .string(grid.cell(for: loginError)?.row?.isHidden == false ? loginError.stringValue : ""),
            "notificationsDenied": .bool(grid.cell(for: denied)?.row?.isHidden == false),
            "screen": .string(window?.screen?.localizedName ?? ""),
            "shortcut": .string(KeyboardShortcuts.getShortcut(for: .freezeScreen)?.description ?? ""),
        ])
    }
}
