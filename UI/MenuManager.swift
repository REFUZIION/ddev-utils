import AppKit
import Combine

class MenuManager: NSObject, NSMenuDelegate {
    private let menu = NSMenu()
    private let appState: AppState
    private let actionHandler: ActionHandler
    private let windowManager: WindowManager
    private let settings = SettingsManager.shared
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState, actionHandler: ActionHandler, windowManager: WindowManager) {
        self.appState = appState
        self.actionHandler = actionHandler
        self.windowManager = windowManager
        super.init()
        
        menu.delegate = self
        setupBindings()
        rebuildMenuItems()
    }

    func getMenu() -> NSMenu {
        return menu
    }

    private func setupBindings() {
        appState.$projects
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenuItems() }
            .store(in: &cancellables)
        
        appState.$monitoredProject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenuItems() }
            .store(in: &cancellables)
        
        appState.$startingProjects
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenuItems() }
            .store(in: &cancellables)
            
        appState.$stoppingProjects
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenuItems() }
            .store(in: &cancellables)
        
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenuItems() }
            .store(in: &cancellables)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenuItems()
    }

    private func rebuildMenuItems() {
        menu.removeAllItems()
        
        let runningCount = appState.projects.filter { $0.status == "running" }.count
        let headerItem = NSMenuItem(title: "DDEV Projects (\(runningCount) running)", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())
        
        let favorites = settings.favoriteProjects
        let runningProjects = appState.projects.filter { $0.status == "running" }.sorted(by: { $0.name < $1.name })
        let favoriteRunning = runningProjects.filter { favorites.contains($0.name) }
        let nonFavoriteRunning = runningProjects.filter { !favorites.contains($0.name) }
        
        for project in favoriteRunning {
            let projectItem = createProjectMenuItem(project, isFavorite: true)
            menu.addItem(projectItem)
        }
        
        if runningProjects.isEmpty && appState.startingProjects.isEmpty {
            let noProjectsItem = NSMenuItem(title: "No running projects", action: nil, keyEquivalent: "")
            noProjectsItem.isEnabled = false
            menu.addItem(noProjectsItem)
        } else {
            for project in nonFavoriteRunning {
                let projectItem = createProjectMenuItem(project, isFavorite: false)
                menu.addItem(projectItem)
            }
        }
        
        let startingNotYetRunning = appState.startingProjects.filter { name in
            !runningProjects.contains(where: { $0.name == name })
        }
        for projectName in startingNotYetRunning.sorted() {
            let item = NSMenuItem(title: "\(projectName) — Starting...", action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "arrow.trianglehead.clockwise", accessibilityDescription: "Starting")
            item.isEnabled = false
            menu.addItem(item)
        }
        
        if !settings.hideStoppedProjects {
            let stoppedProjects = appState.projects.filter { $0.status != "running" }
            if !stoppedProjects.isEmpty {
                menu.addItem(NSMenuItem.separator())
                
                let stoppedMenuItem = NSMenuItem(
                    title: "Stopped Projects (\(stoppedProjects.count))",
                    action: nil,
                    keyEquivalent: ""
                )
                stoppedMenuItem.image = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: "Stopped")
                
                let stoppedSubmenu = NSMenu()
                
                let favoriteStoppedProjects = stoppedProjects.filter { favorites.contains($0.name) }.sorted(by: { $0.name < $1.name })
                let nonFavoriteStoppedProjects = stoppedProjects.filter { !favorites.contains($0.name) }.sorted(by: { $0.name < $1.name })
                
                for project in favoriteStoppedProjects {
                    let projectItem = createStoppedProjectMenuItem(project, isFavorite: true)
                    stoppedSubmenu.addItem(projectItem)
                }
                
                if !favoriteStoppedProjects.isEmpty && !nonFavoriteStoppedProjects.isEmpty {
                    stoppedSubmenu.addItem(NSMenuItem.separator())
                }
                
                for project in nonFavoriteStoppedProjects {
                    let projectItem = createStoppedProjectMenuItem(project, isFavorite: false)
                    stoppedSubmenu.addItem(projectItem)
                }
                
                stoppedMenuItem.submenu = stoppedSubmenu
                menu.addItem(stoppedMenuItem)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let refreshItem = NSMenuItem(title: "Refresh Projects", action: #selector(refreshProjectsAction), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit DDEV Utils", action: #selector(quitAppAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func createProjectMenuItem(_ project: DdevProject, isFavorite: Bool) -> NSMenuItem {
        let isStopping = appState.stoppingProjects.contains(project.name)
        let isRestarting = appState.startingProjects.contains(project.name) && project.status == "running"
        let baseTitle = isFavorite ? "⭐ \(project.name)" : project.name
        
        let title: String
        if isStopping {
            title = "\(baseTitle) — Stopping..."
        } else if isRestarting {
            title = "\(baseTitle) — Restarting..."
        } else {
            title = baseTitle
        }
        
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        
        let monitorItem = NSMenuItem(title: appState.monitoredProject == project.name ? "✓ Monitoring" : "Monitor Status", action: #selector(monitorProjectAction(_:)), keyEquivalent: "")
        monitorItem.target = self
        monitorItem.representedObject = project.name
        submenu.addItem(monitorItem)
        
        let favoriteItem = NSMenuItem(title: isFavorite ? "Remove from Favorites" : "Add to Favorites", action: #selector(toggleFavoriteAction(_:)), keyEquivalent: "")
        favoriteItem.target = self
        favoriteItem.representedObject = project.name
        submenu.addItem(favoriteItem)
        
        submenu.addItem(NSMenuItem.separator())
        
        let sshItem = NSMenuItem(title: "SSH into Container", action: #selector(sshIntoProjectAction(_:)), keyEquivalent: "")
        sshItem.target = self
        sshItem.representedObject = project.approot
        submenu.addItem(sshItem)
        
        let launchItem = NSMenuItem(title: "Open in Browser", action: #selector(launchProjectAction(_:)), keyEquivalent: "")
        launchItem.target = self
        let url = project.httpsurl ?? project.httpurl ?? project.primaryUrl ?? ""
        launchItem.representedObject = url.isEmpty ? project.name : url
        submenu.addItem(launchItem)
        
        if let projectPath = project.approot,
           actionHandler.isTablePlusAvailable(),
           let hasDatabase = appState.getCachedDatabaseAvailability(at: projectPath),
           hasDatabase {
            let tablePlusItem = NSMenuItem(title: "Open in TablePlus", action: #selector(openTablePlusAction(_:)), keyEquivalent: "")
            tablePlusItem.target = self
            tablePlusItem.representedObject = projectPath
            submenu.addItem(tablePlusItem)
        }
        
        submenu.addItem(NSMenuItem.separator())
        
        let commandsItem = NSMenuItem(title: "Commands", action: nil, keyEquivalent: "")
        let commandsSubmenu = NSMenu()
        
        let projectPath = project.approot ?? project.name
        if let xdebugStatus = appState.getCachedXdebugStatus(at: projectPath) {
            let xdebugTitle = xdebugStatus ? "Disable xDebug" : "Enable xDebug"
            let xdebugItem = NSMenuItem(title: xdebugTitle, action: #selector(toggleXdebugAction(_:)), keyEquivalent: "")
            xdebugItem.target = self
            xdebugItem.representedObject = projectPath
            commandsSubmenu.addItem(xdebugItem)
        }
        
        if !commandsSubmenu.items.isEmpty {
            commandsItem.submenu = commandsSubmenu
            submenu.addItem(commandsItem)
        }
        
        submenu.addItem(NSMenuItem.separator())
        
        let restartItem = NSMenuItem(title: "Restart", action: #selector(restartProjectAction(_:)), keyEquivalent: "")
        restartItem.target = self
        restartItem.representedObject = project.name
        submenu.addItem(restartItem)
        
        let stopItem = NSMenuItem(title: "Stop", action: #selector(stopProjectAction(_:)), keyEquivalent: "")
        stopItem.target = self
        stopItem.representedObject = project.name
        submenu.addItem(stopItem)
        
        item.submenu = submenu
        
        guard let mutagenStatusString = project.mutagenStatus else {
            return item
        }
        
        let mutagenStatus = MutagenSyncStatus(fromString: mutagenStatusString)
        
        switch mutagenStatus {
        case .synced, .watching:
            item.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Synced")
        case .syncing, .staging, .scanning:
            item.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Syncing")
        case .problems:
            item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Problems")
        case .paused:
            item.image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "Paused")
        case .disconnected, .unknown:
            item.image = NSImage(systemSymbolName: "questionmark.circle.fill", accessibilityDescription: "Unknown")
        }
        
        return item
    }

    private func createStoppedProjectMenuItem(_ project: DdevProject, isFavorite: Bool) -> NSMenuItem {
        let isStarting = appState.startingProjects.contains(project.name)
        let baseTitle = isFavorite ? "⭐ \(project.name)" : project.name
        let title = isStarting ? "\(baseTitle) — Starting..." : baseTitle
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        
        if isStarting {
            item.image = NSImage(systemSymbolName: "arrow.trianglehead.clockwise", accessibilityDescription: "Starting")
        } else {
            item.image = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: "Stopped")
        }
        
        let submenu = NSMenu()
        
        let favoriteItem = NSMenuItem(title: isFavorite ? "Remove from Favorites" : "Add to Favorites", action: #selector(toggleFavoriteAction(_:)), keyEquivalent: "")
        favoriteItem.target = self
        favoriteItem.representedObject = project.name
        submenu.addItem(favoriteItem)
        
        submenu.addItem(NSMenuItem.separator())
        
        let startItem = NSMenuItem(title: "Start", action: #selector(startProjectAction(_:)), keyEquivalent: "")
        startItem.target = self
        startItem.representedObject = project.name
        submenu.addItem(startItem)
        
        item.submenu = submenu
        
        return item
    }

    @objc private func refreshProjectsAction() {
        actionHandler.refreshProjects()
    }
    
    @objc private func openSettingsAction() {
        windowManager.openSettings()
    }
    
    @objc private func quitAppAction() {
        actionHandler.quitApp()
    }
    
    @objc private func monitorProjectAction(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        actionHandler.monitorProject(name)
    }
    
    @objc private func toggleFavoriteAction(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        actionHandler.toggleFavorite(name)
    }
    
    @objc private func sshIntoProjectAction(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        actionHandler.sshIntoProject(at: path)
    }
    
    @objc private func launchProjectAction(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        actionHandler.launchProject(url: url)
    }
    
    @objc private func openTablePlusAction(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        actionHandler.openTablePlus(at: path)
    }
    
    @objc private func toggleXdebugAction(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        actionHandler.toggleXdebug(at: path)
    }
    
    @objc private func restartProjectAction(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        actionHandler.restartProject(name)
    }
    
    @objc private func stopProjectAction(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        actionHandler.stopProject(name)
    }
    
    @objc private func startProjectAction(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        actionHandler.startProject(name)
    }
}
