import Foundation
import Cocoa
import HotKey

public final class HotkeyManager {
    private var hotKey: HotKey?
    
    public var onKeyDown: (() -> Void)?
    public var onKeyUp: (() -> Void)?
    
    public init() {
        registerHotkey()
    }
    
    public func registerHotkey() {
        // Clear existing hotkey if any
        hotKey = nil
        
        let keyCodeVal = UInt16(Configuration.shared.hotkeyKeyCode)
        let modifierVal = UInt(Configuration.shared.hotkeyModifiers)
        
        // Find matching Key case using Carbon Key Code
        guard let key = Key(carbonKeyCode: UInt32(keyCodeVal)) else {
            Log.hotkey.error("Invalid keycode \(keyCodeVal); defaulting to 'D' (key code 2)")
            // Fallback to D (keycode 2) and Option (524288)
            setupHotkey(key: .d, modifiers: .option)
            return
        }
        
        let modifiers = NSEvent.ModifierFlags(rawValue: modifierVal)
        setupHotkey(key: key, modifiers: modifiers)
    }
    
    private func setupHotkey(key: Key, modifiers: NSEvent.ModifierFlags) {
        Log.hotkey.info("Registering global hotkey (keycode \(key.carbonKeyCode), modifiers \(modifiers.rawValue))")

        let newHotKey = HotKey(key: key, modifiers: modifiers)

        newHotKey.keyDownHandler = { [weak self] in
            self?.onKeyDown?()
        }

        newHotKey.keyUpHandler = { [weak self] in
            self?.onKeyUp?()
        }
        
        self.hotKey = newHotKey
    }
}
