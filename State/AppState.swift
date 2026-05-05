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
    
    /// Active mutagen timer interval; `-1` means not yet aligned to adaptive pacing.
    private var mutagenPollTimerInterval: TimeInterval = -1
    
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
        
        let diskTimer = Timer(
            timeInterval: Self.diskSpaceCheckInterval,
            target: self,
            selector: #selector(checkDiskSpaceThresholdTick),
            userInfo: nil,
            repeats: true
        )
        diskTimer.tolerance = min(Self.diskSpaceCheckInterval * 0.15, 30)
        diskSpaceTimer = diskTimer
        RunLoop.main.add(diskTimer, forMode: .common)
        
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
            let interval = settings.projectRefreshInterval
            let timer = Timer(
                timeInterval: interval,
                target: self,
                selector: #selector(refreshProjects),
                userInfo: nil,
                repeats: true
            )
            timer.tolerance = max(interval * 0.15, 2)
            refreshTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    @objc func refreshProjects() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
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
        mutagenPollTimerInterval = -1
        statusTimer?.invalidate()
        statusTimer = nil
        checkMutagenStatus()
    }

    func stopMonitoring() {
        monitoredProject = nil
        statusTimer?.invalidate()
        statusTimer = nil
        mutagenPollTimerInterval = -1
        currentStatus = .idle
    }
    
    /// Poll quickly while Mutagen is busy; ease off when synced (still responsive when sync starts).
    private func adaptiveMutagenPollInterval(for syncStatus: MutagenSyncStatus) -> TimeInterval {
        let configured = settings.mutagenPollInterval
        switch syncStatus {
        case .synced, .watching:
            return max(configured * 2, 1)
        case .paused:
            return max(configured * 2, 1)
        case .scanning, .syncing, .staging:
            return configured
        case .problems, .disconnected, .unknown:
            return max(configured * 2, 1)
        }
    }
    
    /// After idle→active sync transitions, sample a few times at the fast interval so menu/icon updates feel immediate.
    private func scheduleMutagenBurstAfterBecomingBusy(previous: MutagenSyncStatus, next: MutagenSyncStatus) {
        guard next.isSyncing, !previous.isSyncing else { return }
        let interval = settings.mutagenPollInterval
        for step in 1...3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(step)) { [weak self] in
                guard let self, self.monitoredProject != nil else { return }
                self.checkMutagenStatus()
            }
        }
    }
    
    private func scheduleMutagenTimerIfNeeded(for syncStatus: MutagenSyncStatus) {
        guard monitoredProject != nil else { return }
        
        let interval = adaptiveMutagenPollInterval(for: syncStatus)
        if abs(interval - mutagenPollTimerInterval) < 0.05, statusTimer != nil {
            return
        }
        
        mutagenPollTimerInterval = interval
        statusTimer?.invalidate()
        
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(checkMutagenStatus),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = min(max(interval * 0.25, 0.05), interval * 0.5)
        statusTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    
    private static func statusIcon(for syncStatus: MutagenSyncStatus) -> StatusIcon {
        switch syncStatus {
        case .synced, .watching:
            return .synced
        case .scanning:
            return .scanning
        case .syncing, .staging:
            return .syncing
        case .problems, .disconnected, .unknown:
            return .error
        case .paused:
            return .idle
        }
    }
    
    @objc private func checkMutagenStatus() {
        guard let project = monitoredProject else {
            currentStatus = .idle
            return
        }
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let status = self.ddevService.getMutagenStatus(for: project)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard self.monitoredProject == project else { return }
                
                let newMenuIcon = Self.statusIcon(for: status.status)
                let statusString = status.rawOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? status.status.rawValue
                
                guard let index = self.projects.firstIndex(where: { $0.name == project }) else {
                    self.scheduleMutagenTimerIfNeeded(for: status.status)
                    return
                }
                
                let projectItem = self.projects[index]
                let prevMutagen = projectItem.mutagenStatus?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let previousSync = MutagenSyncStatus(fromString: prevMutagen)
                
                if prevMutagen == statusString, self.currentStatus == newMenuIcon {
                    self.scheduleMutagenTimerIfNeeded(for: status.status)
                    return
                }
                
                self.scheduleMutagenBurstAfterBecomingBusy(previous: previousSync, next: status.status)
                
                self.currentStatus = newMenuIcon
                
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
                
                self.scheduleMutagenTimerIfNeeded(for: status.status)
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
        
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] t in
            self?.checkProjectStatus(projectName, targetStatus: targetStatus, timer: t)
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        startingProjectTimer = timer
        
        checkProjectStatus(projectName, targetStatus: targetStatus, timer: nil)
    }

    private func checkProjectStatus(_ projectName: String, targetStatus: String, timer: Timer?) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
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
