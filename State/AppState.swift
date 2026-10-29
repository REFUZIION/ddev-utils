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
    private var diskSpaceTimer: Timer?
    
    /// Avoid repeating the disk alert until usage falls below the threshold again.
    private var diskSpaceAlertLatchActive = false
    
    private static let diskSpaceCheckInterval: TimeInterval = 60
    
    /// Active mutagen timer interval; `-1` means not yet aligned to adaptive pacing.
    private var mutagenPollTimerInterval: TimeInterval = -1
    
    /// A nil value means "looked up, unavailable"; a missing key means "not looked up yet".
    private var xdebugStatusCache: [String: Bool?] = [:]
    private var databaseAvailableCache: [String: Bool] = [:]
    
    /// Shell checks can outlast their timer interval; skip ticks instead of piling up processes.
    private var isCheckingMutagen = false
    
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
            
            DispatchQueue.main.async {
                self.projects = projects
                self.loadProjectDetails(for: projects)
                
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
    
    /// Looks up database and xdebug state in the background so building the menu never runs a shell.
    /// Call on the main thread: the caches are only touched there.
    private func loadProjectDetails(for projects: [DdevProject]) {
        let paths = projects.filter { $0.status == "running" }.compactMap(\.approot)
        let needDatabase = paths.filter { databaseAvailableCache[$0] == nil }
        let needXdebug = paths.filter { xdebugStatusCache[$0] == nil }
        guard !needDatabase.isEmpty || !needXdebug.isEmpty else { return }
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let databases = needDatabase.map { ($0, self.ddevService.hasDatabase(at: $0)) }
            let xdebugs = needXdebug.map { ($0, self.ddevService.getXdebugStatus(at: $0)) }
            
            DispatchQueue.main.async {
                for (path, hasDatabase) in databases {
                    self.databaseAvailableCache[path] = hasDatabase
                }
                for (path, status) in xdebugs where self.xdebugStatusCache[path] == nil {
                    self.xdebugStatusCache.updateValue(status, forKey: path)
                }
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
        case .scanning, .syncing, .staging:
            return configured
        default:
            return max(configured * 2, 1)
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
        case .synced:
            return .synced
        case .scanning:
            return .scanning
        case .syncing, .staging:
            return .syncing
        case .problems, .disconnected, .unknown:
            return .error
        case .paused, .disabled:
            return .idle
        }
    }
    
    @objc private func checkMutagenStatus() {
        guard let project = monitoredProject else {
            currentStatus = .idle
            return
        }
        guard !isCheckingMutagen else { return }
        isCheckingMutagen = true
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let result = self.ddevService.getMutagenStatus(for: project)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isCheckingMutagen = false
                guard self.monitoredProject == project else {
                    // Monitoring switched while this check ran; the new project's first check was skipped.
                    if self.monitoredProject != nil { self.checkMutagenStatus() }
                    return
                }
                
                let newMenuIcon = Self.statusIcon(for: result.status)
                let statusString = result.output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? result.status.rawValue
                
                // @Published fires on every assignment; only write real changes so the menu isn't rebuilt each poll.
                if let index = self.projects.firstIndex(where: { $0.name == project }),
                   self.projects[index].mutagenStatus != statusString {
                    self.projects[index].mutagenStatus = statusString
                }
                if self.currentStatus != newMenuIcon {
                    self.currentStatus = newMenuIcon
                }
                
                // Mutagen is off for this project: nothing will change, so stop polling.
                if result.status == .disabled {
                    self.statusTimer?.invalidate()
                    self.statusTimer = nil
                    return
                }
                self.scheduleMutagenTimerIfNeeded(for: result.status)
            }
        }
    }

    /// Cache only; `loadProjectDetails` fills it in the background.
    func getCachedXdebugStatus(at projectPath: String) -> Bool? {
        xdebugStatusCache[projectPath] ?? nil
    }

    func invalidateXdebugCache(for projectPath: String) {
        xdebugStatusCache.removeValue(forKey: projectPath)
    }
    
    func setXdebugStatus(_ status: Bool, for projectPath: String) {
        xdebugStatusCache.updateValue(status, forKey: projectPath)
    }
    
    func getCachedDatabaseAvailability(at projectPath: String) -> Bool? {
        databaseAvailableCache[projectPath]
    }

    /// Called on the main thread when a ddev start/stop/restart command has exited.
    func projectActionFinished(_ projectName: String, action: String, output: String?, succeeded: Bool) {
        startingProjects.remove(projectName)
        stoppingProjects.remove(projectName)
        refreshProjects()
        
        guard succeeded else {
            presentProjectActionFailedAlert(projectName, action: action, output: output)
            return
        }
        if action != "stop", settings.autoMonitorFirstProject {
            startMonitoring(project: projectName)
        }
    }
    
    private func presentProjectActionFailedAlert(_ projectName: String, action: String, output: String?) {
        let details = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Failed to \(action) \(projectName)"
        // ddev prints progress first; the error is at the end.
        alert.informativeText = details.isEmpty ? "ddev exited with an error." : String(details.suffix(1500))
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    
    func cleanup() {
        statusTimer?.invalidate()
        refreshTimer?.invalidate()
        diskSpaceTimer?.invalidate()
        diskSpaceTimer = nil
    }
}
