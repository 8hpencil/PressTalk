import Foundation
import Cocoa
import SwiftUI

public enum DictationState {
    case idle
    case recording
    /// Still recording, but approaching the duration cap (U4).
    case recordingWarning
    case transcribing

    var iconName: String {
        switch self {
        case .idle:
            return "mic"
        case .recording:
            return "mic.fill"
        case .recordingWarning:
            return "exclamationmark.triangle.fill"
        case .transcribing:
            return "ellipsis"
        }
    }

    var tooltip: String {
        switch self {
        case .idle:
            return L("state.idle.tooltip")
        case .recording:
            return L("state.recording.tooltip")
        case .recordingWarning:
            return L("state.recordingWarning.tooltip")
        case .transcribing:
            return L("state.transcribing.tooltip")
        }
    }

    var menuStatusText: String {
        switch self {
        case .idle:
            return L("state.idle.menu")
        case .recording:
            return L("state.recording.menu")
        case .recordingWarning:
            return L("state.recordingWarning.menu")
        case .transcribing:
            return L("state.transcribing.menu")
        }
    }
}

public final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private var settingsWindow: NSWindow?
    private var state: DictationState = .idle
    private var statusMenuItem: NSMenuItem?

    public init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        super.init()
        setupMenu()
        updateStatusItem()
    }

    public func updateState(_ newState: DictationState) {
        self.state = newState
        updateStatusItem()
        // Update the status line in place instead of rebuilding the menu (E3).
        statusMenuItem?.title = state.menuStatusText
    }

    /// Brief menu-bar hint when a hotkey press is ignored because the
    /// previous transcription is still in flight (U5 default policy).
    public func flashBusyHint() {
        guard let button = statusItem.button else { return }
        button.title = L("menu.busyHint")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.statusItem.button?.title = ""
        }
    }
    
    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        
        let config = NSImage.SymbolConfiguration(textStyle: .body, scale: .medium)
        if let image = NSImage(systemSymbolName: state.iconName, accessibilityDescription: state.tooltip) {
            let configuredImage = image.withSymbolConfiguration(config)
            if let finalImage = configuredImage {
                finalImage.isTemplate = true
                button.image = finalImage
            } else {
                image.isTemplate = true
                button.image = image
            }
        }
        
        button.toolTip = state.tooltip
        
        // Visual indicator details (e.g. highlight button when recording)
        if state == .recording || state == .recordingWarning {
            button.isHighlighted = true
        } else {
            button.isHighlighted = false
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // 1. Status Info (Disabled Item)
        let statusItem = NSMenuItem(title: state.menuStatusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        self.statusMenuItem = statusItem
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. Open Settings Window
        let settingsItem = NSMenuItem(title: L("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Quit
        let quitItem = NSMenuItem(title: L("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.statusItem.menu = menu
    }
    
    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = L("settings.windowTitle")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.backingType = .buffered
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.center()
        
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Observe window closing to clean up reference
        NotificationCenter.default.addObserver(self, selector: #selector(settingsWindowWillClose(_:)), name: NSWindow.willCloseNotification, object: window)
    }
    
    @objc private func settingsWindowWillClose(_ notification: Notification) {
        settingsWindow = nil
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
