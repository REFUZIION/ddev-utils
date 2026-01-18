import Foundation
import AppKit

class ActionHandler {
    private let ddevService = DdevService()
    private let appState: AppState
    private let settings = SettingsManager.shared

    init(appState: AppState) {
        self.appState = appState
    }

    func toggleFavorite(_ projectName: String) {
        settings.toggleFavorite(projectName)
    }

    func sshIntoProject(at projectPath: String) {
        ddevService.sshIntoProject(at: projectPath)
    }

    func launchProject(url: String) {
        ddevService.launchProject(url: url)
    }
    
    func openTablePlus(at projectPath: String) {
        ddevService.openTablePlus(at: projectPath)
    }
    
    func isTablePlusAvailable() -> Bool {
        ddevService.isTablePlusAvailable()
    }
    
    func hasDatabase(at projectPath: String) -> Bool {
        if let cached = appState.getCachedDatabaseAvailability(at: projectPath) {
            return cached
        }
        
        return ddevService.hasDatabase(at: projectPath)
    }

    func toggleXdebug(at projectPath: String) {
        appState.invalidateXdebugCache(for: projectPath)
        
        ddevService.toggleXdebug(at: projectPath) { [weak self] output in
            guard let self = self, let output = output else { return }
            
            DispatchQueue.main.async {
                let lowercased = output.lowercased()
                if lowercased.contains("enabled") {
                    self.appState.setXdebugStatus(true, for: projectPath)
                } else if lowercased.contains("disabled") {
                    self.appState.setXdebugStatus(false, for: projectPath)
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.reopenMenu()
                }
            }
        }
    }

    func stopProject(_ projectName: String) {
        appState.stoppingProjects.insert(projectName)
        ddevService.stopProject(projectName)
        
        if appState.monitoredProject == projectName {
            appState.stopMonitoring()
        }
        
        appState.trackProjectStatus(projectName, targetStatus: "stopped")
        reopenMenu()
    }

    func startProject(_ projectName: String) {
        appState.startingProjects.insert(projectName)
        ddevService.startProject(projectName)
        appState.trackProjectStatus(projectName, targetStatus: "running")
        reopenMenu()
    }

    func restartProject(_ projectName: String) {
        appState.startingProjects.insert(projectName)
        ddevService.restartProject(projectName)
        appState.trackProjectStatus(projectName, targetStatus: "running")
        reopenMenu()
    }
    
    func reopenMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.statusBarController?.reopenMenu()
        }
    }
    
    private weak var statusBarController: StatusBarController?
    
    func setStatusBarController(_ controller: StatusBarController) {
        self.statusBarController = controller
    }
    
    func monitorProject(_ projectName: String) {
        appState.startMonitoring(project: projectName)
    }
    
    func refreshProjects() {
        appState.refreshProjects()
    }
    
    func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
