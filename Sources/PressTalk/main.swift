import Cocoa

// Global reference to prevent ARC deallocation since app.delegate is a weak reference
let delegate = AppDelegate()

autoreleasepool {
    let app = NSApplication.shared
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // Run as a background accessory app without Dock icon
    app.run()
}
