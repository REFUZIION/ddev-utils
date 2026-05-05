import Foundation
import SwiftUI
import Combine

enum StatusDisplayMode: String, CaseIterable, Identifiable {
    case iconOnly = "icon"
    case textOnly = "text"
    case iconAndText = "both"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .iconOnly: return "Icon Only"
        case .textOnly: return "Text Only"
        case .iconAndText: return "Icon & Text"
        }
    }
}

enum ProjectFilterMode: String, CaseIterable, Identifiable {
    case all = "all"
    case runningOnly = "running"
    case favorites = "favorites"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .all: return "All Projects"
        case .runningOnly: return "Running Only"
        case .favorites: return "Favorites Only"
        }
    }
}

enum ShellType: String, CaseIterable, Identifiable {
    case zsh = "/bin/zsh"
    case bash = "/bin/bash"
    case fish = "/opt/homebrew/bin/fish"
    case custom = "custom"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .zsh: return "Zsh"
        case .bash: return "Bash"
        case .fish: return "Fish"
        case .custom: return "Custom"
        }
    }
    
    var path: String {
        return rawValue
    }
}

enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal = "Terminal"
    case iterm = "iTerm"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm: return "iTerm"
        }
    }
    
    var appName: String {
        switch self {
        case .terminal: return "Terminal"
        case .iterm: return "iTerm"
        }
    }
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let statusDisplayMode = "statusDisplayMode"
        static let showProjectCount = "showProjectCount"
        static let projectFilterMode = "projectFilterMode"
        static let hideStoppedProjects = "hideStoppedProjects"
        static let favoriteProjects = "favoriteProjects"
        static let mutagenPollInterval = "mutagenPollInterval"
        static let projectRefreshInterval = "projectRefreshInterval"
        static let autoMonitorFirstProject = "autoMonitorFirstProject"
        static let notifyOnSyncComplete = "notifyOnSyncComplete"
        static let shellType = "shellType"
        static let customShellPath = "customShellPath"
        static let ddevPath = "ddevPath"
        static let terminalApp = "terminalApp"
        static let diskSpaceWarningEnabled = "diskSpaceWarningEnabled"
        static let diskSpaceWarningThresholdPercent = "diskSpaceWarningThresholdPercent"
    }
    
    @Published var statusDisplayMode: StatusDisplayMode {
        didSet {
            defaults.set(statusDisplayMode.rawValue, forKey: Keys.statusDisplayMode)
        }
    }
    
    @Published var showProjectCount: Bool {
        didSet {
            defaults.set(showProjectCount, forKey: Keys.showProjectCount)
        }
    }
    
    @Published var projectFilterMode: ProjectFilterMode {
        didSet {
            defaults.set(projectFilterMode.rawValue, forKey: Keys.projectFilterMode)
        }
    }
    
    @Published var hideStoppedProjects: Bool {
        didSet {
            defaults.set(hideStoppedProjects, forKey: Keys.hideStoppedProjects)
        }
    }
    
    @Published var favoriteProjects: [String] {
        didSet {
            defaults.set(favoriteProjects, forKey: Keys.favoriteProjects)
        }
    }
    
    @Published var mutagenPollInterval: Double {
        didSet {
            defaults.set(mutagenPollInterval, forKey: Keys.mutagenPollInterval)
        }
    }
    
    @Published var projectRefreshInterval: Double {
        didSet {
            defaults.set(projectRefreshInterval, forKey: Keys.projectRefreshInterval)
        }
    }
    
    @Published var autoMonitorFirstProject: Bool {
        didSet {
            defaults.set(autoMonitorFirstProject, forKey: Keys.autoMonitorFirstProject)
        }
    }
    
    @Published var notifyOnSyncComplete: Bool {
        didSet {
            defaults.set(notifyOnSyncComplete, forKey: Keys.notifyOnSyncComplete)
        }
    }
    
    @Published var shellType: ShellType {
        didSet {
            defaults.set(shellType.rawValue, forKey: Keys.shellType)
        }
    }
    
    @Published var customShellPath: String {
        didSet {
            defaults.set(customShellPath, forKey: Keys.customShellPath)
        }
    }
    
    @Published var ddevPath: String {
        didSet {
            defaults.set(ddevPath, forKey: Keys.ddevPath)
        }
    }
    
    @Published var terminalApp: TerminalApp {
        didSet {
            defaults.set(terminalApp.rawValue, forKey: Keys.terminalApp)
        }
    }
    
    /// Off by default. When enabled, warns if boot volume used % reaches the threshold.
    @Published var diskSpaceWarningEnabled: Bool {
        didSet {
            defaults.set(diskSpaceWarningEnabled, forKey: Keys.diskSpaceWarningEnabled)
        }
    }
    
    /// Whole percent (50–99), used only when `diskSpaceWarningEnabled` is true.
    @Published var diskSpaceWarningThresholdPercent: Double {
        didSet {
            defaults.set(diskSpaceWarningThresholdPercent, forKey: Keys.diskSpaceWarningThresholdPercent)
        }
    }
    
    var effectiveShellPath: String {
        if shellType == .custom {
            return customShellPath.isEmpty ? "/bin/zsh" : customShellPath
        }
        return shellType.path
    }
    
    private init() {
        let savedDisplayMode = defaults.string(forKey: Keys.statusDisplayMode) ?? StatusDisplayMode.iconOnly.rawValue
        self.statusDisplayMode = StatusDisplayMode(rawValue: savedDisplayMode) ?? .iconAndText
        
        self.showProjectCount = defaults.bool(forKey: Keys.showProjectCount)
        
        let savedFilterMode = defaults.string(forKey: Keys.projectFilterMode) ?? ProjectFilterMode.all.rawValue
        self.projectFilterMode = ProjectFilterMode(rawValue: savedFilterMode) ?? .all
        
        self.hideStoppedProjects = defaults.bool(forKey: Keys.hideStoppedProjects)
        self.favoriteProjects = defaults.stringArray(forKey: Keys.favoriteProjects) ?? []
        
        let savedPollInterval = defaults.double(forKey: Keys.mutagenPollInterval)
        self.mutagenPollInterval = savedPollInterval > 0 ? savedPollInterval : 0.5
        
        let savedRefreshInterval = defaults.double(forKey: Keys.projectRefreshInterval)
        self.projectRefreshInterval = savedRefreshInterval > 0 ? savedRefreshInterval : 30.0
        
        if defaults.object(forKey: Keys.autoMonitorFirstProject) == nil {
            self.autoMonitorFirstProject = true
            defaults.set(true, forKey: Keys.autoMonitorFirstProject)
        } else {
            self.autoMonitorFirstProject = defaults.bool(forKey: Keys.autoMonitorFirstProject)
        }
        
        self.notifyOnSyncComplete = defaults.bool(forKey: Keys.notifyOnSyncComplete)
        
        let savedShellType = defaults.string(forKey: Keys.shellType) ?? ShellType.zsh.rawValue
        self.shellType = ShellType(rawValue: savedShellType) ?? .zsh
        self.customShellPath = defaults.string(forKey: Keys.customShellPath) ?? ""
        self.ddevPath = defaults.string(forKey: Keys.ddevPath) ?? ""
        
        let savedTerminalApp = defaults.string(forKey: Keys.terminalApp) ?? TerminalApp.terminal.rawValue
        self.terminalApp = TerminalApp(rawValue: savedTerminalApp) ?? .terminal
        
        self.diskSpaceWarningEnabled = defaults.bool(forKey: Keys.diskSpaceWarningEnabled)
        
        let savedDiskThreshold = defaults.double(forKey: Keys.diskSpaceWarningThresholdPercent)
        self.diskSpaceWarningThresholdPercent = (savedDiskThreshold >= 50 && savedDiskThreshold <= 99)
            ? savedDiskThreshold
            : 90
    }
    
    func toggleFavorite(_ projectName: String) {
        if favoriteProjects.contains(projectName) {
            favoriteProjects.removeAll { $0 == projectName }
        } else {
            favoriteProjects.append(projectName)
        }
    }
    
    func isFavorite(_ projectName: String) -> Bool {
        favoriteProjects.contains(projectName)
    }
    
    func resetToDefaults() {
        statusDisplayMode = .iconAndText
        showProjectCount = false
        projectFilterMode = .all
        hideStoppedProjects = false
        favoriteProjects = []
        mutagenPollInterval = 0.5
        projectRefreshInterval = 30.0
        autoMonitorFirstProject = true
        notifyOnSyncComplete = false
        shellType = .zsh
        customShellPath = ""
        ddevPath = ""
        terminalApp = .terminal
        diskSpaceWarningEnabled = false
        diskSpaceWarningThresholdPercent = 90
    }
}
