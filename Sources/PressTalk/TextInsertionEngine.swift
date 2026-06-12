import Foundation
import Cocoa
import ApplicationServices

public final class TextInsertionEngine {

    /// Apps known to report AX write success without actually rendering the
    /// text (custom editors and terminal emulators draw their own text and
    /// ignore kAXSelectedText writes). These always take the clipboard path.
    private static let axUnreliableBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.google.Chrome",
        "com.mitchellh.ghostty",
        "com.googlecode.iterm2",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "com.apple.Terminal"
    ]

    public init() {}

    /// Inserts text at the current cursor position. Tries the Accessibility
    /// API first for plain text fields, then falls back to clipboard-paste
    /// emulation. Calls `completion(false)` when both paths fail — typically
    /// missing accessibility permission — so the caller can notify the user (E2).
    public func insert(text: String, completion: @escaping (Bool) -> Void) {
        if insertViaAccessibility(text: text) {
            Log.insertion.debug("Inserted via Accessibility API")
            completion(true)
            return
        }
        insertViaPasteboardFallback(text: text, completion: completion)
    }

    /// Attempt direct insertion into the focused element using the macOS
    /// Accessibility API. Only trusted for standard text roles in apps that
    /// are not on the unreliable list; everything else goes through the
    /// clipboard path, which is reliable system-wide.
    private func insertViaAccessibility(text: String) -> Bool {
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           Self.axUnreliableBundleIDs.contains(bundleID) {
            return false
        }

        let systemWideElement = AXUIElementCreateSystemWide()

        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success, let element = focusedElement else {
            return false
        }

        let axElement = element as! AXUIElement

        // Only standard text roles render kAXSelectedText writes dependably.
        var roleValue: AnyObject?
        guard AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String,
              role == kAXTextFieldRole || role == kAXTextAreaRole else {
            return false
        }

        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(axElement, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else {
            return false
        }

        return AXUIElementSetAttributeValue(axElement, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    /// Emulate copy/paste by backing up the clipboard, pasting, and restoring.
    private func insertViaPasteboardFallback(text: String, completion: @escaping (Bool) -> Void) {
        let pasteboard = NSPasteboard.general

        // 1. Back up ALL original pasteboard items with ALL their types —
        // do not degrade this to a string-only backup (verified complete
        // 2026-06-12; rich text and images must survive the round-trip).
        var originalItems: [NSPasteboardItem]? = nil
        if let items = pasteboard.pasteboardItems {
            originalItems = items.map { item in
                let newItem = NSPasteboardItem()
                for type in item.types {
                    if let data = item.data(forType: type) {
                        newItem.setData(data, forType: type)
                    }
                }
                return newItem
            }
        }

        // 2. Set transcribed text as pasteboard content
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        // 3. Simulate Cmd+V keystroke; CGEvent creation fails without
        // accessibility permission, which is exactly the E2 failure mode.
        guard simulatePasteKeystroke() else {
            pasteboard.clearContents()
            if let items = originalItems, !items.isEmpty {
                pasteboard.writeObjects(items)
            }
            completion(false)
            return
        }

        // 4. Restore the original clipboard after a grace period. Paste
        // consumption is not observable (NSPasteboard.changeCount only tracks
        // writes), so we use a generous 800 ms delay instead of the old racy
        // 100 ms (B6), and skip the restore entirely if someone else wrote to
        // the clipboard in the meantime (their content wins).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard pasteboard.changeCount == ourChangeCount else {
                Log.insertion.debug("Clipboard changed during grace period; skipping restore")
                return
            }
            pasteboard.clearContents()
            if let items = originalItems, !items.isEmpty {
                pasteboard.writeObjects(items)
            }
            Log.insertion.debug("Pasteboard contents restored")
        }
        completion(true)
    }

    /// Simulates Cmd+V keystroke using CGEvent. Returns false when the events
    /// cannot be created or posted (no accessibility permission).
    private func simulatePasteKeystroke() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            Log.insertion.error("Failed to create CGEventSource")
            return false
        }

        // Key code for 'V' is 9
        guard let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) else {
            Log.insertion.error("Failed to create Command+V keydown event")
            return false
        }
        cmdVDown.flags = .maskCommand

        guard let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            Log.insertion.error("Failed to create Command+V keyup event")
            return false
        }
        cmdVUp.flags = .maskCommand

        // Post events to the event stream
        cmdVDown.post(tap: .cghidEventTap)
        cmdVUp.post(tap: .cghidEventTap)
        return true
    }
}
