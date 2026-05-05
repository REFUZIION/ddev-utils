import AppKit
import Combine
import Foundation

class AppState: ObservableObject {
    @Published var projects: [DdevProject] = []
    @Published var monitoredProject: String?
    @Published var currentStatus: StatusIcon = .initializing
    @Published var startingProjects: Set<String> = []
    @Published var stoppingProjects: Set<String> = []

    private var statusTimer: Timer?
    private var refreshTimer: Timer?
    private var startingProjectTimer: Timer?
    private var diskSpaceTimer: Timer?
    
    /// Avoid repeating the disk alert until usage falls below the threshold again.
    private var diskSpaceAlertLatchActive = false
    
    private static let diskSpaceCheckInterval: TimeInterval = 60
    
    private var xdebugStatusCache: [String: Bool] = [:]
    private var databaseAvailableCache: [String: Bool] = [:]
    
    private let ddevService = DdevService()
    private let settings = SettingsManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        observeSettingsChanges()
        setupTimers()
        setupDiskSpaceMonitoring()
        refreshProjects()
    }
    
    private func setupDiskSpaceMonitoring() {
        diskSpaceTimer?.invalidate()
        diskSpaceTimer = nil
        
        guard settings.diskSpaceWarningEnabled else {
            diskSpaceAlertLatchActive = false
            return
        }
        
        diskSpaceTimer = Timer(
            timeInterval: Self.diskSpaceCheckInterval,
            target: self,
            selector: #selector(checkDiskSpaceThresholdTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(diskSpaceTimer!, forMode: .common)
        
        checkDiskSpaceThreshold()
    }
    
    @objc private func checkDiskSpaceThresholdTick() {
        checkDiskSpaceThreshold()
    }
    
    private func checkDiskSpaceThreshold() {
        guard settings.diskSpaceWarningEnabled else { return }
        guard let fraction = DiskSpaceReader.bootVolumeUsedFraction() else { return }
        
        let usedPercent = fraction * 100.0
        let threshold = settings.diskSpaceWarningThresholdPercent
        
        if usedPercent >= threshold {
            guard !diskSpaceAlertLatchActive else { return }
            diskSpaceAlertLatchActive = true
            presentDiskSpaceWarningAlert(usedPercent: usedPercent, threshold: threshold)
        } else {
            diskSpaceAlertLatchActive = false
        }
    }
    
    private func presentDiskSpaceWarningAlert(usedPercent: Double, threshold: Double) {
        let shownPercent = Int(usedPercent.rounded())
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Disk space warning"
        alert.informativeText = """
            Your startup disk is about \(shownPercent)% full (warning threshold: \(Int(threshold))%). \
            Free up space to avoid macOS stability issues and problems with Docker or Mutagen sync.
            """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func observeSettingsChanges() {
        settings.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.setupTimers()
                self?.setupDiskSpaceMonitoring()
            }
            .store(in: &cancellables)
    }

    func setupTimers() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        
        if settings.projectRefreshInterval > 0 {
            refreshTimer = Timer.scheduledTimer(
                timeInterval: settings.projectRefreshInterval,
                target: self,
                selector: #selector(refreshProjects),
                userInfo: nil,
                repeats: true
            )
        }
    }

    @objc func refreshProjects() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let projects = self.ddevService.listProjects()
            
            for project in projects where project.status == "running" {
                guard let projectPath = project.approot,
                      self.databaseAvailableCache[projectPath] == nil else { continue }
                
                let hasDatabase = self.ddevService.hasDatabase(at: projectPath)
                DispatchQueue.main.async {
                    self.databaseAvailableCache[projectPath] = hasDatabase
                }
            }
            
            DispatchQueue.main.async {
                self.projects = projects
                
                if self.currentStatus == .initializing {
                    self.currentStatus = .idle
                }
                
                if let monitored = self.monitoredProject {
                    let isStillRunning = projects.contains { $0.name == monitored && $0.status == "running" }
                    if !isStillRunning {
                        self.stopMonitoring()
                    }
                }
                
                guard self.settings.autoMonitorFirstProject,
                      self.monitoredProject == nil,
                      let firstRunning = projects.first(where: { $0.status == "running" }) else { return }
                
                self.startMonitoring(project: firstRunning.name)
            }
        }
    }

    func startMonitoring(project: String) {
        stopMonitoring()
        monitoredProject = project
        
        statusTimer?.invalidate()
        
        statusTimer = Timer.scheduledTimer(
            timeInterval: settings.mutagenPollInterval,
            target: self,
            selector: #selector(checkMutagenStatus),
            userInfo: nil,
            repeats: true
        )
        
        checkMutagenStatus()
    }

    func stopMonitoring() {
        monitoredProject = nil
        statusTimer?.invalidate()
        statusTimer = nil
        currentStatus = .idle
    }
    
    @objc private func checkMutagenStatus() {
        guard let project = monitoredProject else {
            currentStatus = .idle
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let status = self.ddevService.getMutagenStatus(for: project)
            
            DispatchQueue.main.async {
                switch status.status {
                case .synced, .watching:
                    self.currentStatus = .synced
                case .scanning:
                    self.currentStatus = .scanning
                case .syncing, .staging:
                    self.currentStatus = .syncing
                case .problems, .disconnected, .unknown:
                    self.currentStatus = .error
                case .paused:
                    self.currentStatus = .idle
                }
                
                guard let index = self.projects.firstIndex(where: { $0.name == project }) else { return }
                
                let projectItem = self.projects[index]
                let statusString = status.rawOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? status.status.rawValue
                let updatedProject = DdevProject(
                    name: projectItem.name,
                    status: projectItem.status,
                    statusDesc: projectItem.statusDesc,
                    type: projectItem.type,
                    approot: projectItem.approot,
                    shortroot: projectItem.shortroot,
                    httpurl: projectItem.httpurl,
                    httpsurl: projectItem.httpsurl,
                    primaryUrl: projectItem.primaryUrl,
                    mutagenEnabled: projectItem.mutagenEnabled,
                    mutagenStatus: statusString
                )
                self.projects[index] = updatedProject
            }
        }
    }

    func getCachedXdebugStatus(at projectPath: String) -> Bool? {
        if let cachedStatus = xdebugStatusCache[projectPath] {
            return cachedStatus
        }
        
        guard let status = ddevService.getXdebugStatus(at: projectPath) else {
            xdebugStatusCache[projectPath] = nil
            return nil
        }
        
        xdebugStatusCache[projectPath] = status
        return status
    }

    func invalidateXdebugCache(for projectPath: String) {
        xdebugStatusCache.removeValue(forKey: projectPath)
    }
    
    func setXdebugStatus(_ status: Bool, for projectPath: String) {
        xdebugStatusCache[projectPath] = status
    }
    
    func getCachedDatabaseAvailability(at projectPath: String) -> Bool? {
        databaseAvailableCache[projectPath]
    }

    func trackProjectStatus(_ projectName: String, targetStatus: String) {
        startingProjectTimer?.invalidate()
        
        startingProjectTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            self?.checkProjectStatus(projectName, targetStatus: targetStatus, timer: timer)
        }
        
        checkProjectStatus(projectName, targetStatus: targetStatus, timer: nil)
    }

    private func checkProjectStatus(_ projectName: String, targetStatus: String, timer: Timer?) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let projects = self.ddevService.listProjects()
            
            DispatchQueue.main.async {
                self.projects = projects
                
                guard let project = projects.first(where: { $0.name == projectName }),
                      project.status == targetStatus || project.status.contains(targetStatus) else { return }
                
                timer?.invalidate()
                self.startingProjectTimer?.invalidate()
                self.startingProjectTimer = nil
                
                self.startingProjects.remove(projectName)
                self.stoppingProjects.remove(projectName)
                
                if targetStatus == "running" {
                    if let projectPath = project.approot, self.databaseAvailableCache[projectPath] == nil {
                        DispatchQueue.global(qos: .utility).async { [weak self] in
                            guard let self = self else { return }
                            let hasDatabase = self.ddevService.hasDatabase(at: projectPath)
                            DispatchQueue.main.async {
                                self.databaseAvailableCache[projectPath] = hasDatabase
                            }
                        }
                    }
                    
                    if self.settings.autoMonitorFirstProject {
                        self.startMonitoring(project: projectName)
                    }
                }
            }
        }
    }
    
    func cleanup() {
        statusTimer?.invalidate()
        refreshTimer?.invalidate()
        startingProjectTimer?.invalidate()
        diskSpaceTimer?.invalidate()
        diskSpaceTimer = nil
    }
}
