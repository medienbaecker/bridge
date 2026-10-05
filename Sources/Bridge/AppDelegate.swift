import AppKit
import BridgeCore
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = Model()
    var server: Server?
    var window: MainWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let server = Server { [self] request, reply in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.handle(request, reply: reply) }
            }
        }
        buildMenu()
        if !Env.test, Bundle.main.bundleIdentifier != nil { UNUserNotificationCenter.current().delegate = self }
        window = MainWindow(model: model)
        window.showWindow(nil)
        // The socket opens only once there is a window: building the toolbar spins the
        // run loop, and a present arriving in that gap was handled against no window.
        if let reason = server.start() {
            let text = "\(Flavor.appName) could not start: \(reason)\n"
            try? text.write(to: Paths.launchError, atomically: true, encoding: .utf8)
            if ProcessInfo.processInfo.environment["BRIDGE_LAUNCHED_BY_CLI"] == nil { FileHandle.standardError.write(Data(text.utf8)) }
            exit(1)
        }
        self.server = server
        if model.scope == .waiting, model.bridges(in: .waiting).isEmpty { model.scope = .all }
        let remembered = Model.remembered("selected") as? String
        model.selected = model.listing.bridges.contains { $0.location == remembered } ? remembered : nil
        model.settleSelection()
        model.changed()
        Timer.scheduledTimer(timeInterval: 30, target: self, selector: #selector(updateTick), userInfo: nil, repeats: true)
        Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(waitersTick), userInfo: nil, repeats: true)
        pollWaiters()
    }

    // MARK: Waiters

    var pileupText: String?
    static let pileupCount = ProcessInfo.processInfo.environment["BRIDGE_PILEUP_COUNT"].flatMap(Int.init) ?? 10
    static let pileupBytes: UInt64 = 1_000_000_000

    @objc func waitersTick() { pollWaiters() }

    func pollWaiters() {
        let found = Waiters.all()
        let listeningBefore = Set(model.waiters.map { "\($0.pid) \($0.session)" })
        let livesBefore = model.lives
        model.waiters = found
        model.lives = Dictionary(Set(model.listing.bridges.filter { !$0.crossed }.map(\.session)).map { ($0, ClaudeSessions.life(of: $0)) }, uniquingKeysWith: { a, _ in a })
        let total = found.reduce(0) { $0 + ($1.bytes ?? 0) }
        let size = total >= Self.pileupBytes ? String(format: "%.1f GB", Double(total) / 1e9) : "\(total / 1_000_000) MB"
        let text = found.count >= Self.pileupCount || total >= Self.pileupBytes
            ? "\(found.count) agent\(found.count == 1 ? "" : "s") waiting · \(size)" : nil
        if text != pileupText { pileupText = text; window?.projects.showPileup(text) }
        if Set(found.map { "\($0.pid) \($0.session)" }) != listeningBefore || model.lives != livesBefore { window?.sidebar.reload() }
    }

    func applicationDidBecomeActive(_ notification: Notification) { checkUpdate() }

    // MARK: Update

    // The Stop hook keeps the app alive for hours, so a build installed underneath
    // this process would otherwise go unnoticed.
    let launchedAt = Date()
    var updateText: String?

    var updateReady: Bool {
        if ProcessInfo.processInfo.environment["BRIDGE_UPDATE_READY"] == "1" { return true }
        guard let exe = Bundle.main.executableURL,
              let modified = (try? FileManager.default.attributesOfItem(atPath: exe.path))?[.modificationDate] as? Date else { return false }
        return modified > launchedAt
    }

    @objc func updateTick() {
        checkUpdate()
        window?.sidebar.refreshTimes()
    }

    func checkUpdate() {
        if updateReady { if updateText == nil { updateText = "Update ready" } } else { updateText = nil }
        window?.projects.showUpdate(updateText)
    }

    func relaunch() {
        guard updateReady, let exe = Bundle.main.executableURL else { return }
        let page = model.selectedPage
        Task { @MainActor in
            // A half-written note would not survive the relaunch.
            if let page, page.ready,
               let typed = try? await page.evaluate("return document.querySelector('.bridge-thread:popover-open textarea')?.value || ''"),
               case .string(let text) = typed, !text.isEmpty {
                updateText = "Finish your note first"
                window?.projects.showUpdate(updateText)
                return
            }
            // The new process inherits this one's environment (state dir, test mode).
            let sh = Process()
            sh.executableURL = URL(fileURLWithPath: "/bin/sh")
            sh.arguments = ["-c", "sleep 1; exec \"$0\"", exe.path]
            try? sh.run()
            NSApp.terminate(nil)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let location = response.notification.request.content.userInfo["location"] as? String
        await MainActor.run {
            NSApp.activate()
            window.showWindow(nil)
            _ = window.select(location)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    func handle(_ request: Request, reply: @escaping @Sendable (Response) -> Void) {
        switch request {
        case .present(let locations, let cwd, let session, let ground, let links):
            let wasActive = NSApp.isActive
            model.present(locations, cwd: cwd, session: session, ground: ground, links: links)
            if !Env.test { NSApp.activate() }
            window.showWindow(nil)
            if !Env.test, !wasActive, let loc = locations.first { Notify.arrived(model.listing.entry(loc)) }
            reply(.ok(.null))
        case .state:
            reply(.ok(state()))
        case .audit(let loc):
            let page = model.page(for: loc)
            let onDisk = try? Data(contentsOf: URL(fileURLWithPath: loc))
            reply(.ok(.object(["ready": .bool(page.ready), "unknownClasses": .array(page.unknownClasses.map { .string($0) }),
                               "collidingClasses": .array(page.collidingClasses.map { .string($0) }),
                               "errors": .array(page.errors.map { .string($0) }),
                               "version": .number(Double(page.sidecar.version)),
                               "current": .bool(onDisk != nil && page.shapedContent == onDisk),
                               "bumpedByThis": .bool(onDisk != nil && page.bump?.content == onDisk),
                               "why": page.bump.map { .string($0.why) } ?? .null])))
        case .cross(let loc):
            model.cross(loc, true); reply(.ok(.null))
        case .uncross(let loc):
            model.cross(loc, false); reply(.ok(.null))
        case .remove(let loc):
            model.remove(loc); reply(.ok(.null))
        case .reset(let loc):
            model.reset(loc); reply(.ok(.null))
        case .reply(let loc, let id, let text):
            let page = model.page(for: loc)
            if let why = page.unreadable { reply(.error(why)); return }
            page.reply(to: id, text: text); reply(.ok(.null))
        case .note(let loc, let id, let state):
            let page = model.page(for: loc)
            if let why = page.unreadable { reply(.error(why)); return }
            page.setNote(id, state: state); reply(.ok(.null))
        case .collect(let loc, let session):
            let page = model.page(for: loc)
            if let why = page.unreadable { reply(.error(why)); return }
            page.collected(by: session); reply(.ok(.null))
        case .js(let loc, let code):
            guard Env.test, let page = loc.map({ model.page(for: $0) }) ?? model.selectedPage else {
                reply(.error("no page")); return
            }
            Task { @MainActor in
                do { reply(.ok(try await page.evaluate(code))) } catch { reply(.error("\(error)")) }
            }
        case .command(let name, let argument):
            guard Env.test else { reply(.error("test mode only")); return }
            reply(window.perform(command: name, argument: argument) ? .ok(state()) : .error("unknown command \(name)"))
        case .shot(let path, let screen):
            Task { @MainActor in
                do {
                    // A tooltip is a window of the app too; one under a resting mouse would widen the union.
                    let windows = NSApp.windows.filter { $0.isVisible && !String(describing: type(of: $0)).contains("ToolTip") }
                    let r = try await Shot.capture(screen: screen, windows: windows, to: path)
                    reply(.ok(.object(["path": .string(path), "width": .number(Double(r.width)), "height": .number(Double(r.height)),
                                       "colours": .number(Double(r.colours)), "windows": .array(r.windows.map { .string($0) }),
                                       "missing": .array(r.missing.map { .string($0) }), "clipped": .bool(r.clipped),
                                       "frames": .array(r.frames.map { .string($0) }), "display": .string(r.display), "scale": .number(r.scale)])))
                } catch let error as NSError where error.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && error.code == -3801 {
                    reply(.error("\(Flavor.appName) may not capture its own window: allow it in System Settings, Privacy & Security, Screen & System Audio Recording, then relaunch it. (\(error.localizedDescription))"))
                } catch { reply(.error("\(error)")) }
            }
        case .snapshot(let path):
            guard Env.test else { reply(.error("test mode only")); return }
            Task { @MainActor in
                await Snapshot.write(window: window.window!, webView: model.selectedPage?.webView, to: path)
                reply(.ok(.string(path)))
            }
        case .quit:
            reply(.ok(.null))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { NSApp.terminate(nil) }
        }
    }

    func state() -> JSONValue {
        var out: [String: JSONValue] = ["running": .bool(true), "test": .bool(Env.test)]
        if let page = model.selectedPage {
            out["selected"] = .string(page.location)
            out["title"] = .string(page.title)
            out["missing"] = .bool(page.missing)
            out["status"] = .string(page.sidecar.status)
            out["version"] = .number(Double(page.sidecar.version))
            out["viewingVersion"] = page.viewingVersion.map { .number(Double($0)) } ?? .null
            out["answers"] = .number(Double(page.sidecar.answers.count))
            out["notes"] = .number(Double(page.sidecar.openComments.count))
            out["pointing"] = .bool(page.pointing)
            out["ready"] = .bool(page.ready)
            out["buildMs"] = page.buildMs.map { .number(Double($0)) } ?? .null
            out["zoom"] = .number(Double((page.zoom * 100).rounded() / 100))
            out["links"] = .string(page.links.rawValue)
        }
        if let w = window.window {
            out["windowNumber"] = .number(Double(w.windowNumber))
            out["windowKey"] = .bool(w.isKeyWindow)
            out["backingScale"] = .number(Double(w.backingScaleFactor))
            out["titlebarHeight"] = .number(Double(w.frame.height - w.contentLayoutRect.height))
            let f = w.frame
            out["windowFrame"] = .object(["x": .number(Double(f.minX)), "y": .number(Double(f.minY)), "width": .number(Double(f.width)), "height": .number(Double(f.height))])
            if let screen = w.screen {
                // Top-left origin, as CoreGraphics and ScreenCaptureKit have it.
                let top = screen.frame.maxY - f.maxY
                out["screenFrame"] = .object(["x": .number(Double(f.minX)), "y": .number(Double(top)), "width": .number(Double(f.width)), "height": .number(Double(f.height))])
            }
        }
        checkUpdate()
        out["openedExternally"] = .array(Page.openedExternally.map { .string($0.absoluteString) })
        out["updateReady"] = .bool(updateReady)
        out["updateText"] = updateText.map { .string($0) } ?? .null
        out["banner"] = window.bannerText.map { .string($0) } ?? .null
        out["selectedRows"] = .array(window.sidebar.selectedLocations.map { .string($0) })
        out["rowMenu"] = .array(window.rowMenuTitles.map { .string($0) })
        out["rowMenuTargets"] = .array(window.rowMenuTargets.map { .string($0) })
        out["notesPopoverShown"] = .bool(window.notesPopover.isShown)
        out["notesPopoverSize"] = .object(["width": .number(Double(window.notesPopover.contentSize.width)), "height": .number(Double(window.notesPopover.contentSize.height))])
        out["notesRows"] = .array(window.notes.shown.map { .string($0.text) })
        out["notesRowsFit"] = .array(window.notes.shown.map { .bool($0.fits) })
        out["sidebarGeometry"] = .object(window.sidebar.geometry())
        out["updateRow"] = .object(window.projects.updateGeometry())
        pollWaiters()
        out["pileupRow"] = .object(window.projects.pileupGeometry())
        out["projects"] = .object(window.projects.dump())
        out["columnWidths"] = .array(window.split.splitView.arrangedSubviews.map { .number(Double($0.frame.width)) })
        // The layout viewport starts under the titlebar, so the page's origin is offset by that inset.
        let pageBox = window.content.view.convert(window.content.view.bounds, to: nil)
        out["pageX"] = .number(Double(pageBox.minX))
        out["pageY"] = .number(Double((window.window?.frame.height ?? 0) - pageBox.maxY + window.content.view.safeAreaInsets.top))
        out["crossedShown"] = .bool(model.showCrossed)
        out["listEmpty"] = .string(window.sidebar.emptyText)
        out["listHeader"] = .string(window.listHeader.stringValue)
        out["listHeaderX"] = .number(Double(window.listHeader.convert(window.listHeader.bounds, to: nil).minX))
        out["documentTitle"] = .string(window.docTitleView.stringValue)
        out["documentTitleX"] = .number(Double(window.docTitleView.convert(window.docTitleView.bounds, to: nil).minX))
        out["listEmptyFrame"] = .object(window.sidebar.emptyFrame)
        out["bridgesColumn"] = .array(model.shown().map { .string($0.location) })
        out["quietRows"] = .array(model.shown().filter { model.isQuiet($0) }.map { .string($0.location) })
        out["toolbar"] = .array(window.toolbarItems.map {
            .object(["id": .string($0.itemIdentifier.rawValue), "label": .string($0.label), "enabled": .bool($0.isEnabled),
                     "symbol": .string($0.image?.accessibilityDescription ?? ""),
                     "on": .bool($0.itemIdentifier == MainWindow.point && window.pointShownOn)])
        })
        out["toolbarLabelsShown"] = .bool(window.window?.toolbar?.displayMode == .iconAndLabel)
        out["subtitle"] = .string(window.window?.subtitle ?? "")
        out["sidebar"] = .array(model.listing.projects.map { project in
            .object([
                "project": .string((project as NSString).lastPathComponent),
                "bridges": .array(model.listing.bridges.filter { $0.project == project }.sorted { $0.presentedAt > $1.presentedAt }.map { b in
                    .object([
                        "title": .string(b.title), "location": .string(b.location), "unread": .bool(b.unread),
                        "crossed": .bool(b.crossed), "status": .string(model.pages[b.location]?.sidecar.status ?? Sidecar.peek(Paths.sidecar(for: b.location)).status),
                        "row": .string(window.sidebar.rowText(for: b)),
                        "subtitle": window.sidebar.subtitle(for: b).map { JSONValue.string($0) } ?? .null,
                        "listening": .bool(model.listening(b)),
                        "resolved": model.resolved(b).map { JSONValue.string($0) } ?? .null,
                    ])
                }),
            ])
        })
        return .object(out)
    }

    func buildMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide Bridge", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Bridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Bridge", action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let bridge = NSMenu(title: "Bridge")
        func item(_ title: String, _ command: String, _ key: String, _ mods: NSEvent.ModifierFlags = .command) {
            let i = bridge.addItem(withTitle: title, action: #selector(MainWindow.menuCommand(_:)), keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.representedObject = command
        }
        item("Point", "point", "p", [.command, .shift])
        item("Send", "send", "\r", [.command, .shift])
        bridge.addItem(.separator())
        item("Hide Crossed", "crossed", "c", [.command, .option])
        item("Cross", "cross", "e")
        item("Uncross", "uncross", "E", [.command, .shift])
        item("Remove from List", "remove", "\u{8}")
        item("Reveal in Finder", "reveal", "R", [.command, .shift])
        bridge.addItem(.separator())
        item("Zoom In", "zoom-in", "+")
        item("Zoom Out", "zoom-out", "-")
        item("Actual Size", "zoom-reset", "0")
        bridge.addItem(.separator())
        item("Previous Version", "previous", "[")
        item("Next Version", "next", "]")
        main.addItem(withTitle: "Bridge", action: nil, keyEquivalent: "").submenu = bridge

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}
