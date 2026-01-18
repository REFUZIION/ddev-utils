import AppKit
import Combine

class StatusBarController {
    private var statusItem: NSStatusItem?
    private let appState: AppState
    private let settings = SettingsManager.shared
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.toolTip = "DDEV Utils"
        }
        
        setupBindings()
        updateStatusIcon()
    }
    
    func setMenu(_ menu: NSMenu) {
        statusItem?.menu = menu
    }

    private func setupBindings() {
        appState.$currentStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusIcon() }
            .store(in: &cancellables)
        
        appState.$projects
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusIcon() }
            .store(in: &cancellables)
        
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusIcon() }
            .store(in: &cancellables)
        
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(updateIconForAppearanceChange),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }
    
    @objc private func updateIconForAppearanceChange() {
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let statusItem = statusItem, let button = statusItem.button else { return }
        
        let status = appState.currentStatus
        let displayMode = settings.statusDisplayMode
        let showCount = settings.showProjectCount
        let runningCount = appState.projects.filter { $0.status == "running" }.count
        
        var title = ""
        if displayMode == .textOnly || displayMode == .iconAndText {
            title = status.statusText
            if showCount && runningCount > 0 {
                title += " (\(runningCount))"
            }
        } else if showCount && runningCount > 0 {
            title = "(\(runningCount))"
        }
        
        button.title = title
        
        guard displayMode == .iconOnly || displayMode == .iconAndText else {
            button.image = nil
            button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
            return
        }
        
        if status == .idle {
            if let ddevLogo = loadDdevLogo(for: button) {
                button.image = ddevLogo
                button.contentTintColor = nil
            } else if let image = NSImage(systemSymbolName: status.symbolName, accessibilityDescription: "DDEV Status") {
                let sizeConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
                if let configuredImage = image.withSymbolConfiguration(sizeConfig) {
                    configuredImage.isTemplate = true
                    button.image = configuredImage
                }
                button.contentTintColor = nil
            }
        } else if let image = NSImage(systemSymbolName: status.symbolName, accessibilityDescription: "DDEV Status") {
            let sizeConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let colorConfig = NSImage.SymbolConfiguration(hierarchicalColor: status.tintColor)
            let combinedConfig = colorConfig.applying(sizeConfig)
            
            if let configuredImage = image.withSymbolConfiguration(combinedConfig) {
                configuredImage.isTemplate = false
                button.image = configuredImage
            }
            button.contentTintColor = nil
        }
        
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
    }

    private func loadDdevLogo(for button: NSButton) -> NSImage? {
        let appearance = button.effectiveAppearance
        let isDark = appearance.name == .darkAqua || appearance.name == .vibrantDark
        
        let filename = isDark ? "ddev-logo-white" : "ddev-logo-dark"
        
        guard let path = Bundle.main.path(forResource: filename, ofType: "svg"),
              let svgImage = NSImage(contentsOfFile: path) else {
            return nil
        }
        
        svgImage.size = NSSize(width: 16, height: 16)
        return svgImage
    }
    
    func reopenMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.statusItem?.button?.performClick(nil)
        }
    }
}
