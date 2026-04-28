import SwiftUI
import AppKit
import Combine

@main
struct WorkStopwatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings scene satisfies the App protocol's "at least one scene" requirement
        // without ever auto-opening a window. We never trigger it from SwiftUI
        // (we use AppDelegate to manage all windows manually), so no warnings appear.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var floatingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private let stopwatch = StopwatchModel.shared
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Use .regular so the Dock icon and app menu show normally.
        // (.accessory hides the Dock icon — use that if you want a pure menu-bar app.)
        NSApp.setActivationPolicy(.regular)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "00:00"
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 420)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: StopwatchView().environmentObject(stopwatch)
        )

        stopwatch.$elapsed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] e in
                self?.statusItem.button?.title = StopwatchModel.format(e)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStateChange),
            name: .stopwatchStateChanged,
            object: nil
        )

        // Hijack the standard "Settings..." / "Preferences..." menu item so it
        // opens our custom NSWindow instead of the empty SwiftUI Settings scene.
        DispatchQueue.main.async { [weak self] in
            self?.rewireSettingsMenuItem()
        }

        print("=== WorkStopwatch launched ===")
    }

    private func rewireSettingsMenuItem() {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }
        for item in appMenu.items {
            // macOS 13+: "Settings…", earlier: "Preferences…"
            if item.title.hasPrefix("Settings") || item.title.hasPrefix("Preferences") {
                item.target = self
                item.action = #selector(openSettingsFromAppMenu)
                item.keyEquivalent = ","
                item.keyEquivalentModifierMask = [.command]
            }
        }
    }

    @objc private func openSettingsFromAppMenu() {
        openSettings()
    }

    // MARK: - Status item click

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Open Settings...",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit WorkStopwatch",
            action: #selector(quitApp),
            keyEquivalent: "q"
        ))
        for item in menu.items { item.target = self }

        // Show menu under the status item, then clear so left-click still triggers action.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - State change

    @objc private func handleStateChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("=== state changed: running=\(self.stopwatch.isRunning), phase=\(self.stopwatch.phase.rawValue) ===")
            if self.stopwatch.isRunning && self.stopwatch.showFloatingWindowOnStart {
                self.showFloatingWindow()
            }
        }
    }

    // MARK: - Floating window

    private func showFloatingWindow() {
        if let win = floatingWindow {
            // Already exists; do not steal focus from whatever the user is doing.
            if !win.isVisible { win.orderFront(nil) }
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "WorkStopwatch"
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.center()
        win.contentViewController = NSHostingController(
            rootView: FloatingView().environmentObject(stopwatch)
        )
        win.isReleasedWhenClosed = false
        win.delegate = FloatingWindowDelegate.shared
        FloatingWindowDelegate.shared.onClose = { [weak self] in
            self?.floatingWindow = nil
        }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        floatingWindow = win
        print("=== floating window shown ===")
    }

    // MARK: - Settings window

    func openSettings() {
        if let win = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 900),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "WorkStopwatch Settings"
        win.minSize = NSSize(width: 600, height: 600)
        win.center()
        win.contentViewController = NSHostingController(
            rootView: SettingsView().environmentObject(stopwatch)
        )
        win.isReleasedWhenClosed = false
        win.delegate = SettingsWindowDelegate.shared
        SettingsWindowDelegate.shared.onClose = { [weak self] in
            self?.settingsWindow = nil
        }
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        settingsWindow = win
    }
}

// MARK: - Window delegates

final class FloatingWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = FloatingWindowDelegate()
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}

final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowDelegate()
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}

/// Lightweight env object used by the popover to ask AppDelegate to open Settings.
final class SettingsOpener: ObservableObject {
    let open: () -> Void
    init(open: @escaping () -> Void) { self.open = open }
}
