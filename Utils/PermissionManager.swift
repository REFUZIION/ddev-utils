import Foundation
import AppKit

class PermissionManager {
    static let shared = PermissionManager()
    
    private init() {}
    
    func handleAppleScriptError(_ error: NSDictionary, appName: String) {
        guard let errorNumber = error[NSAppleScript.errorNumber] as? Int else {
            print("AppleScript error: \(error)")
            return
        }
        
        if errorNumber == -1743 {
            showPermissionAlert(appName: appName)
        } else {
            print("AppleScript error for \(appName): \(error)")
        }
    }
    
    private func showPermissionAlert(appName: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Automation Permission Required"
            alert.informativeText = "DDEV Utils needs permission to control \(appName). Please grant Automation permission in System Settings."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.openAutomationSettings()
            }
        }
    }
    
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
