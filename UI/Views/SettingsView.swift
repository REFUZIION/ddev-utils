import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            DisplaySettingsView()
                .tabItem {
                    Label("Display", systemImage: "eye")
                }
            
            ProjectsSettingsView()
                .tabItem {
                    Label("Projects", systemImage: "folder")
                }
            
            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: 500, height: 400)
        .padding(8)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        Form {
            Section {
                Toggle("Auto-monitor first running project", isOn: $settings.autoMonitorFirstProject)
                    .help("Automatically start monitoring the first running project when the app launches")
                
                Toggle("Notify when sync completes", isOn: $settings.notifyOnSyncComplete)
                    .help("Show a notification when Mutagen sync finishes")
            } header: {
                Text("Behavior")
            }
            
            Section {
                Toggle("Disk space warning", isOn: $settings.diskSpaceWarningEnabled)
                    .help("Alert when startup disk usage reaches the threshold")
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Warn when disk usage reaches:")
                        Spacer()
                        Text("\(Int(settings.diskSpaceWarningThresholdPercent))%")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: $settings.diskSpaceWarningThresholdPercent,
                        in: 50...99,
                        step: 1
                    ) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("50%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } maximumValueLabel: {
                        Text("99%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .disabled(!settings.diskSpaceWarningEnabled)
                }
            } header: {
                Text("Disk Space")
            } footer: {
                Text("Checks every minute while enabled. Shows one alert until usage drops below your threshold.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                HStack {
                    Text("Mutagen polling interval:")
                    Spacer()
                    Picker("", selection: $settings.mutagenPollInterval) {
                        Text("0.5 seconds").tag(0.5)
                        Text("1 second").tag(1.0)
                        Text("2 seconds").tag(2.0)
                        Text("5 seconds").tag(5.0)
                    }
                    .frame(width: 150)
                }
                
                HStack {
                    Text("Project list refresh:")
                    Spacer()
                    Picker("", selection: $settings.projectRefreshInterval) {
                        Text("Manual").tag(0.0)
                        Text("15 seconds").tag(15.0)
                        Text("30 seconds").tag(30.0)
                        Text("1 minute").tag(60.0)
                        Text("5 minutes").tag(300.0)
                    }
                    .frame(width: 150)
                }
            } header: {
                Text("Refresh Intervals")
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct DisplaySettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        Form {
            Section {
                Picker("Status display:", selection: $settings.statusDisplayMode) {
                    ForEach(StatusDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                
                Toggle("Show running project count", isOn: $settings.showProjectCount)
                    .help("Display the number of running projects next to the icon")
            } header: {
                Text("Menu Bar")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        StatusPreview(mode: settings.statusDisplayMode, showCount: settings.showProjectCount)
                    }
                    .padding()
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(8)
                }
            } header: {
                Text("Preview")
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct StatusPreview: View {
    let mode: StatusDisplayMode
    let showCount: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            if mode != .textOnly {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
            
            if mode != .iconOnly {
                Text("Synced")
                    .font(.system(size: 12, weight: .medium))
            }
            
            if showCount {
                Text("(2)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct ProjectsSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var newFavorite: String = ""
    
    var body: some View {
        Form {
            Section {
                Picker("Show in menu:", selection: $settings.projectFilterMode) {
                    ForEach(ProjectFilterMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                
                Toggle("Hide stopped projects submenu", isOn: $settings.hideStoppedProjects)
                    .help("Completely hide the stopped projects from the menu")
            } header: {
                Text("Project Visibility")
            }
            
            Section {
                if settings.favoriteProjects.isEmpty {
                    Text("No favorites yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(settings.favoriteProjects, id: \.self) { project in
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text(project)
                            Spacer()
                            Button(action: {
                                settings.toggleFavorite(project)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                HStack {
                    TextField("Project name", text: $newFavorite)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Add") {
                        if !newFavorite.isEmpty {
                            settings.toggleFavorite(newFavorite)
                            newFavorite = ""
                        }
                    }
                    .disabled(newFavorite.isEmpty)
                }
            } header: {
                Text("Favorite Projects")
            } footer: {
                Text("Favorite projects appear at the top of the menu")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct AdvancedSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var isDetectingDdev: Bool = false
    
    var body: some View {
        Form {
            Section {
                Picker("Shell type:", selection: $settings.shellType) {
                    ForEach(ShellType.allCases) { shell in
                        Text(shell.displayName).tag(shell)
                    }
                }
                .pickerStyle(.menu)
                
                if settings.shellType == .custom {
                    HStack {
                        Text("Custom shell path:")
                        TextField("/bin/your-shell", text: $settings.customShellPath)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                Text("Current: \(settings.effectiveShellPath)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Shell")
            } footer: {
                Text("Select the shell to use for running ddev commands")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                Picker("Terminal app:", selection: $settings.terminalApp) {
                    ForEach(TerminalApp.allCases) { app in
                        Text(app.displayName).tag(app)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("SSH Terminal")
            } footer: {
                Text("Select which terminal application to use when opening SSH sessions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                HStack {
                    TextField("Path to ddev executable", text: $settings.ddevPath)
                        .textFieldStyle(.roundedBorder)
                    
                    Button(action: {
                        isDetectingDdev = true
                        DispatchQueue.global(qos: .userInitiated).async {
                            let detected = detectDdevPath()
                            DispatchQueue.main.async {
                                if let path = detected {
                                    settings.ddevPath = path
                                }
                                isDetectingDdev = false
                            }
                        }
                    }) {
                        if isDetectingDdev {
                            ProgressView()
                                .scaleEffect(0.5)
                        } else {
                            Text("Detect")
                        }
                    }
                    .disabled(isDetectingDdev)
                }
                
                if !settings.ddevPath.isEmpty {
                    Text("Using: \(settings.ddevPath)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("DDEV Path")
            } footer: {
                Text("Auto-detected via 'which ddev'. Only change if detection fails.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reset all settings to their default values.")
                        .foregroundColor(.secondary)
                    
                    Button("Reset All Settings") {
                        settings.resetToDefaults()
                    }
                    .foregroundColor(.red)
                }
            } header: {
                Text("Reset")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "d.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DDEV Utils")
                                .font(.headline)
                            Text("Version 1.2.1")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text("A menu bar utility for managing DDEV projects and monitoring Mutagen sync status.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Created by")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("fuziion_dev")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            NSWorkspace.shared.open(URL(string: "https://buymeacoffee.com/fuziion_dev")!)
                        }) {
                            HStack {
                                Image(systemName: "cup.and.saucer.fill")
                                Text("Buy me a coffee")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 4)
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    SettingsView()
}
