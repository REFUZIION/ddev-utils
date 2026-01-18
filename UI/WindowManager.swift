import AppKit
import SwiftUI
import ObjectiveC

private var logsDelegateKey: UInt8 = 0

class LogsWindowDelegate: NSObject, NSWindowDelegate {
    let projectName: String
    let onClose: (String) -> Void
    
    init(projectName: String, onClose: @escaping (String) -> Void) {
        self.projectName = projectName
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose(projectName)
    }
}

class WindowManager {
    private var settingsWindow: NSWindow?
    private var logsWindows: [String: NSWindow] = [:]

    func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "DDEV Utils Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 420))
        window.center()
        window.isReleasedWhenClosed = false
        
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
