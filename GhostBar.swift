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
    private let divider = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private let collapsedLength: CGFloat = 10_000
    private var isCollapsed = false
    private var autoHideTimer: Timer?
    private var clickMonitor: Any?

    private let defaults = UserDefaults.standard
    private var autoHideSeconds: Int {
        get { defaults.object(forKey: "autoHideSeconds") as? Int ?? 10 }
        set { defaults.set(newValue, forKey: "autoHideSeconds") }
    }

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
        autoHideTimer?.invalidate()
        isCollapsed = true
        divider.length = collapsedLength
        divider.button?.image = nil
    }

    private func expand() {
        isCollapsed = false
        divider.length = NSStatusItem.variableLength
        divider.button?.image = symbol("line.diagonal", size: 12)
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        autoHideTimer?.invalidate()
        guard autoHideSeconds > 0 else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(autoHideSeconds), repeats: false) { [weak self] _ in
            self?.collapse()
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

        let autoHide = NSMenuItem(title: "Auto-hide", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (label, secs) in [("Never", 0), ("After 5 seconds", 5), ("After 10 seconds", 10), ("After 30 seconds", 30), ("After 1 minute", 60)] {
            let item = NSMenuItem(title: label, action: #selector(setAutoHide(_:)), keyEquivalent: "")
            item.target = self
            item.tag = secs
            item.state = secs == autoHideSeconds ? .on : .off
            sub.addItem(item)
        }
        autoHide.submenu = sub
        menu.addItem(autoHide)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit GhostBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.popUp(positioning: nil, at: point, in: nil)
    }

    @objc private func setAutoHide(_ sender: NSMenuItem) {
        autoHideSeconds = sender.tag
        if !isCollapsed { scheduleAutoHide() }
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
