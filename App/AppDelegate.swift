import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var actionHandler: ActionHandler!
    private var windowManager: WindowManager!
    private var statusBarController: StatusBarController!
    private var menuManager: MenuManager!

    func applicationWillFinishLaunching(_ notification: Notification) {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "fuziion-dev.DDevUtilsRefactor"
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        
        if runningApps.count > 1 {
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        appState = AppState()
        actionHandler = ActionHandler(appState: appState)
        windowManager = WindowManager()
        
        menuManager = MenuManager(appState: appState, actionHandler: actionHandler, windowManager: windowManager)
        
        statusBarController = StatusBarController(appState: appState)
        statusBarController.setMenu(menuManager.getMenu())
        
        actionHandler.setStatusBarController(statusBarController)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        appState?.cleanup()
    }
}
