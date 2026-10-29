import Foundation
import AppKit

class ActionHandler {
    private let ddevService = DdevService()
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func sshIntoProject(at projectPath: String) {
        ddevService.sshIntoProject(at: projectPath)
    }

    func launchProject(url: String) {
        ddevService.launchProject(url: url)
    }

    func openTablePlus(at projectPath: String) {
        DispatchQueue.global(qos: .userInitiated).async { [ddevService] in
            ddevService.openTablePlus(at: projectPath)
        }
    }

    func isTablePlusAvailable() -> Bool {
        ddevService.isTablePlusAvailable()
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
        if appState.monitoredProject == projectName {
            appState.stopMonitoring()
        }
        ddevService.stopProject(projectName) { [weak self] output, succeeded in
            self?.appState.projectActionFinished(projectName, action: "stop", output: output, succeeded: succeeded)
        }
        reopenMenu()
    }

    func startProject(_ projectName: String) {
        appState.startingProjects.insert(projectName)
        ddevService.startProject(projectName) { [weak self] output, succeeded in
            self?.appState.projectActionFinished(projectName, action: "start", output: output, succeeded: succeeded)
        }
        reopenMenu()
    }

    func restartProject(_ projectName: String) {
        appState.startingProjects.insert(projectName)
        ddevService.restartProject(projectName) { [weak self] output, succeeded in
            self?.appState.projectActionFinished(projectName, action: "restart", output: output, succeeded: succeeded)
        }
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
}
