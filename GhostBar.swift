// GhostBar — hides menu bar icons; click empty menu bar space to toggle.
//
// How it works: GhostBar owns one status item, a thin divider. Any icon you
// ⌘-drag to the LEFT of the divider gets pushed off-screen when collapsed,
// because the divider grows to a huge width and shoves everything to its left
// out of view. A global mouse monitor watches for clicks on empty menu bar
// space (not on an app menu or an icon) and toggles.

import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Created first so it sits to the right of the divider and never gets hidden.
    private let claude = ClaudeStatus()
    private let divider = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private let collapsedLength: CGFloat = 10_000
    private var isCollapsed = false
    private var clickMonitor: Any?

    // Where macOS remembers the user's ⌘-drag position for the divider. Growing
    // the divider to collapsedLength makes the system re-lay out the bar, which
    // can overwrite this, so we snapshot it and write it straight back.
    private let dividerPositionKey = "NSStatusItem Preferred Position GhostBarDivider"
    private let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Autosave name makes macOS remember where the user dragged the divider.
        divider.autosaveName = "GhostBarDivider"
        if let button = divider.button {
            button.target = self
            button.action = #selector(dividerClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Accessibility lets us tell empty bar space apart from app menus.
        // Without it we fall back to a coarser check (see isEmptyMenuBarSpace).
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleGlobalClick(event)
        }

        // Start collapsed shortly after launch so the bar has laid out first.
        // After this, the bar only opens and closes when clicked.
        expand()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.collapse() }
    }

    // MARK: - Clicks

    private func handleGlobalClick(_ event: NSEvent) {
        guard !event.modifierFlags.contains(.command) else { return } // ⌘-drag rearranging
        let point = NSEvent.mouseLocation
        guard isEmptyMenuBarSpace(point) else { return }
        if event.type == .rightMouseDown {
            showMenu(at: point)
        } else {
            toggle()
        }
    }

    // When collapsed, the stretched divider covers the empty bar, so clicks land here.
    @objc private func dividerClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu(at: NSEvent.mouseLocation)
        } else {
            toggle()
        }
    }

    private func isEmptyMenuBarSpace(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return false }
        let barHeight = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        guard point.y >= screen.frame.maxY - barHeight else { return false }

        // AX uses top-left origin relative to the primary screen.
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let axPoint = CGPoint(x: point.x, y: primaryHeight - point.y)

        if AXIsProcessTrusted() {
            var element: AXUIElement?
            let systemWide = AXUIElementCreateSystemWide()
            guard AXUIElementCopyElementAtPosition(systemWide, Float(axPoint.x), Float(axPoint.y), &element) == .success,
                  let element else { return false }
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            // Empty space reports the menu bar itself; app menus and icons are menu bar items.
            return (role as? String) == kAXMenuBarRole
        }

        // Fallback: right half of the screen, and not on another app's status item.
        guard point.x > screen.frame.midX else { return false }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        for info in windows where (info[kCGWindowLayer as String] as? Int) == statusLevel {
            if let dict = info[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: dict), rect.contains(axPoint) {
                return false
            }
        }
        return true
    }

    // MARK: - Toggling

    private func toggle() {
        isCollapsed ? expand() : collapse()
    }

    private func collapse() {
        isCollapsed = true
        withPinnedDividerPosition {
            divider.length = collapsedLength
            divider.button?.image = nil
        }
    }

    private func expand() {
        isCollapsed = false
        withPinnedDividerPosition {
            divider.length = NSStatusItem.variableLength
            divider.button?.image = symbol("line.diagonal", size: 12)
        }
    }

    // Reads the divider's remembered position, resizes it, then puts the
    // position back — including once more after the bar has re-laid out.
    private func withPinnedDividerPosition(_ resize: () -> Void) {
        let saved = defaults.object(forKey: dividerPositionKey)
        resize()
        guard let saved else { return }
        defaults.set(saved, forKey: dividerPositionKey)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.defaults.set(saved, forKey: self.dividerPositionKey)
        }
    }

    // MARK: - Menu

    private func showMenu(at point: NSPoint) {
        let menu = NSMenu()

        let help = NSMenuItem(title: "Click empty menu bar space to hide/show", action: nil, keyEquivalent: "")
        help.isEnabled = false
        menu.addItem(help)
        let help2 = NSMenuItem(title: "⌘-drag icons left of the divider to hide them", action: nil, keyEquivalent: "")
        help2.isEnabled = false
        menu.addItem(help2)
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit GhostBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.popUp(positioning: nil, at: point, in: nil)
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    // MARK: - Helpers

    private func symbol(_ name: String, size: CGFloat) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "GhostBar")?.withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }
}

// MARK: - Claude Code status

// Shows whether Claude Code is working, done, or waiting on you. Claude Code
// hooks (claude-status.sh) write one file per session into
// ~/.ghostbar/sessions; this polls that folder. The icon disappears entirely
// when there's nothing to report.
final class ClaudeStatus: NSObject, NSMenuDelegate {
    enum State: Int, Comparable {
        case idle, done, working, attention
        static func < (a: State, b: State) -> Bool { a.rawValue < b.rawValue }
    }

    struct Session {
        let id: String
        let state: State
        let path: String   // project folder Claude is running in ("" if unknown)
        var folder: String { path.isEmpty ? "Claude Code" : (path as NSString).lastPathComponent }
    }

    private let cursorBundleID = "com.todesktop.230313mzl4w4u92"

    private let item = NSStatusBar.system.statusItem(withLength: 0)
    private let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ghostbar/sessions")
    private let customIcon = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ghostbar/icon.png")
    // Last resort for a session file with no pid to check; see refresh().
    private let staleAfter: TimeInterval = 60 * 60
    private var sessions: [Session] = []
    private var shown: State?
    private var animation: Timer?
    private let animationStart = Date()

    override init() {
        super.init()
        item.autosaveName = "GhostBarClaude"
        keepRightOfDivider()
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        refresh()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    // This icon reports what Claude is doing, so the divider must never hide
    // it. macOS stores each item's spot as points from the right edge of the
    // bar — smaller is further right — so anything at or past the divider's
    // spot sits on the hidden side. Nudge it back, leaving a position the user
    // dragged somewhere safe alone. Runs before the item is laid out.
    private func keepRightOfDivider() {
        let defaults = UserDefaults.standard
        let dividerKey = "NSStatusItem Preferred Position GhostBarDivider"
        let myKey = "NSStatusItem Preferred Position GhostBarClaude"
        guard defaults.object(forKey: dividerKey) != nil else { return } // divider not placed yet
        let divider = defaults.double(forKey: dividerKey)
        let mine = defaults.object(forKey: myKey) != nil ? defaults.double(forKey: myKey) : Double.infinity
        guard mine >= divider else { return }
        defaults.set(max(divider - 24, 1), forKey: myKey) // one icon's width to the right
    }

    private func refresh() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        sessions = files.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let state: State
            switch lines.first {
            case "working": state = .working
            case "done": state = .done
            case "attention": state = .attention
            default: state = .idle
            }
            // A session that quit without running its SessionEnd hook — Cursor
            // closed, a crash — would otherwise sit in the bar forever asking
            // for help nobody can give. Its file names the Claude process that
            // wrote it, so a dead owner means the file can go.
            let pid = lines.count > 2 ? pid_t(lines[2]) ?? 0 : 0
            if pid != 0, !isClaudeRunning(pid) {
                try? fm.removeItem(at: url)
                return nil
            }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            // Fallback for files written before the pid was recorded.
            if pid == 0, state != .done, Date().timeIntervalSince(modified) > staleAfter { return nil }
            let path = lines.count > 1 ? lines[1] : ""
            return Session(id: url.lastPathComponent, state: state, path: path)
        }
        render(sessions.map(\.state).max() ?? .idle)
    }

    // True while that pid is still a Claude Code process. The name check keeps a
    // recycled pid from passing for the session that first claimed it.
    private func isClaudeRunning(_ pid: pid_t) -> Bool {
        guard pid > 1 else { return false }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return false }
        return String(cString: path).contains("claude")
    }

    private func render(_ state: State) {
        guard state != shown else { return }
        shown = state
        // Never set isVisible = false: an item that leaves the bar comes back
        // as the newest one, which lands it left of the divider and gets it
        // hidden. A zero length is invisible but keeps its place.
        item.length = state == .idle ? 0 : NSStatusItem.variableLength
        guard let button = item.button else { return }
        switch state {
        case .idle:
            button.image = nil
            button.toolTip = nil
        case .working:
            button.image = workingFrame()
            button.toolTip = "Claude is working…"
        case .done:
            button.image = customDoneIcon() ?? symbol("checkmark.circle", color: .systemGreen)
            button.toolTip = "Claude is done"
        case .attention:
            button.image = symbol("exclamationmark.circle", color: .systemOrange)
            button.toolTip = "Claude needs you"
        }
        animate(state == .working)
    }

    // MARK: Working animation

    private func animate(_ on: Bool) {
        animation?.invalidate()
        animation = nil
        guard on else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.item.button?.image = self.workingFrame()
        }
        RunLoop.main.add(timer, forMode: .common) // keep animating while a menu is open
        animation = timer
    }

    // The same outline circle as the other icons, with three dots that hop
    // up one after another like a wave.
    private func workingFrame() -> NSImage? {
        guard let circle = symbol("circle", color: nil) else { return nil }
        let size = circle.size
        let t = Date().timeIntervalSince(animationStart)
        let period = 1.5, hopLength = 0.5, stagger = 0.18
        let image = NSImage(size: size, flipped: false) { rect in
            circle.draw(in: rect)
            NSColor.black.setFill() // template image: only the alpha matters
            let d = size.width * 0.125
            let spacing = size.width * 0.23
            for i in 0..<3 {
                let u = (t - Double(i) * stagger).truncatingRemainder(dividingBy: period)
                let phase = u < 0 ? u + period : u
                let hop = phase < hopLength ? sin(.pi * phase / hopLength) : 0
                let x = rect.midX + CGFloat(i - 1) * spacing - d / 2
                let y = rect.midY - d / 2 + CGFloat(hop) * size.height * 0.15
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: d, height: d)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    // Left-click jumps to Cursor, at the project that most needs you.
    // Right-click lists every session; pick one to open its project.
    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showSessions()
        } else {
            let order: [State] = [.attention, .done, .working]
            let target = order.lazy.compactMap { st in self.sessions.first { $0.state == st } }.first
            openInCursor(target?.path ?? "")
            clearDone()
        }
    }

    private func showSessions() {
        let menu = NSMenu()
        menu.delegate = self
        for state in [State.attention, .working, .done] {
            for s in sessions where s.state == state {
                let label: String
                switch state {
                case .attention: label = "⚠︎ \(s.folder) — needs you"
                case .working: label = "… \(s.folder) — working"
                default: label = "✓ \(s.folder) — done"
                }
                let row = NSMenuItem(title: label, action: #selector(openSession(_:)), keyEquivalent: "")
                row.target = self
                row.representedObject = s.path
                menu.addItem(row)
            }
        }
        item.menu = menu
        item.button?.performClick(nil)
    }

    @objc private func openSession(_ sender: NSMenuItem) {
        openInCursor(sender.representedObject as? String ?? "")
    }

    // Opening a folder Cursor already has open just brings that window forward.
    private func openInCursor(_ path: String) {
        guard let cursor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: cursorBundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: cursor, configuration: config)
        } else {
            NSWorkspace.shared.openApplication(at: cursor, configuration: config)
        }
    }

    private func clearDone() {
        for s in sessions where s.state == .done {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(s.id))
        }
        refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        item.menu = nil
        clearDone()
    }

    private func customDoneIcon() -> NSImage? {
        guard let image = NSImage(contentsOf: customIcon) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private func symbol(_ name: String, color: NSColor?) -> NSImage? {
        var config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        if let color { config = config.applying(.init(paletteColors: [color])) }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Claude status")?.withSymbolConfiguration(config)
        image?.isTemplate = color == nil
        return image
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
