import Foundation
import AppKit

class DdevService {
    private let settings = SettingsManager.shared
    
    private var ddevPath: String {
        if !settings.ddevPath.isEmpty {
            return settings.ddevPath
        }
        
        if let detected = detectDdevPath() {
            DispatchQueue.main.async {
                self.settings.ddevPath = detected
            }
            return detected
        }
        
        return "ddev"
    }
    
    init() {
        if settings.ddevPath.isEmpty {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let detected = detectDdevPath() else { return }
                DispatchQueue.main.async {
                    self?.settings.ddevPath = detected
                    print("Auto-detected ddev at \(detected)")
                }
            }
        } else {
            print("Using saved ddev path: \(settings.ddevPath)")
        }
    }
    
    func listProjects() -> [DdevProject] {
        let path = ddevPath
        #if DEBUG
        print("Running '\(path) list --json-output'")
        #endif
        
        guard let output = runShell("\(path) list --json-output"),
              !output.isEmpty else {
            #if DEBUG
            print("Failed to run ddev list - no output")
            #endif
            return []
        }
        
        if output.contains("Could not connect to a Docker provider") {
            #if DEBUG
            print("Docker is not running")
            #endif
            return []
        }
        
        return parseProjectList(output)
    }
    
    func listRunningProjects() -> [DdevProject] {
        listProjects().filter { $0.status == "running" }
    }
    
    private func parseProjectList(_ jsonString: String) -> [DdevProject] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = trimmed.data(using: .utf8) else {
            print("Failed to convert JSON string to data")
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(DdevListResponse.self, from: data)
            #if DEBUG
            print("Successfully parsed \(response.raw.count) projects")
            #endif
            return response.raw
        } catch {
            print("Failed to parse ddev list JSON: \(error)")
            let preview = String(trimmed.prefix(500))
            print("JSON preview: \(preview)")
            return []
        }
    }
    func getMutagenStatus(for projectName: String) -> MutagenStatus {
        guard let output = runShell("\(ddevPath) mutagen status \(projectName) 2>&1") else {
            return MutagenStatus(projectName: projectName, status: .unknown)
        }
        
        let status = MutagenSyncStatus(fromString: output)
        return MutagenStatus(projectName: projectName, status: status, rawOutput: output)
    }
    
    func sshIntoProject(at projectPath: String) {
        let terminalApp = settings.terminalApp
        
        if terminalApp == .iterm {
            let escapedPath = projectPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let escapedDdevPath = ddevPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "iTerm"
                activate
                set new_term to (create window with default profile)
                tell new_term
                    tell the current session
                        write text "cd \\"\(escapedPath)\\""
                        write text "\(escapedDdevPath) ssh"
                    end tell
                end tell
            end tell
            """
            
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    PermissionManager.shared.handleAppleScriptError(error, appName: "iTerm")
                }
            }
        } else {
            let appName = terminalApp.appName
            let escapedPath = projectPath.replacingOccurrences(of: "\"", with: "\\\"")
            let command = """
            osascript -e 'tell app "\(appName)" to activate' -e 'tell app "\(appName)" to do script "cd \\"\(escapedPath)\\" && \(ddevPath) ssh"'
            """
            _ = runShell(command)
        }
    }
    
    func launchProject(url: String) {
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            guard let urlObj = URL(string: url) else {
                print("Invalid URL: \(url)")
                return
            }
            NSWorkspace.shared.open(urlObj)
            return
        }
        
        _ = runShell("\(ddevPath) launch \(url)")
    }
    
    func openTablePlus(at projectPath: String) {
        let escapedPath = projectPath.replacingOccurrences(of: "\"", with: "\\\"")
        let describeCommand = "cd \"\(escapedPath)\" && \(ddevPath) describe --json-output"
        
        guard let describeOutput = runShell(describeCommand) else {
            print("Failed to get DDEV project info - command returned no output")
            return
        }
        
        if describeOutput.contains("is not currently running") || describeOutput.contains("not found") {
            print("Project appears to not be running or not found")
            guard let projectName = extractProjectNameFromPath(projectPath) else { return }
            
            print("Attempting to start project \(projectName)...")
            startProject(projectName)
            
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.openTablePlus(at: projectPath)
            }
            return
        }
        
        guard let projectInfo = parseDdevDescribe(describeOutput) else {
            print("Failed to parse DDEV describe output")
            print("Output was: \(String(describeOutput.prefix(1000)))")
            return
        }
        
        let projects = listProjects()
        let project = projects.first { $0.name == projectInfo.name }
        
        guard project?.status == "running" else {
            print("Project \(projectInfo.name) is not running, starting it...")
            startProject(projectInfo.name)
            
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let updatedOutput = runShell(describeCommand),
                      let updatedInfo = self?.parseDdevDescribe(updatedOutput) else {
                    print("Could not get updated project info, using original")
                    self?.openTablePlusWithInfo(projectInfo: projectInfo)
                    return
                }
                self?.openTablePlusWithInfo(projectInfo: updatedInfo)
            }
            return
        }
        
        openTablePlusWithInfo(projectInfo: projectInfo)
    }
    
    private func extractProjectNameFromPath(_ projectPath: String) -> String? {
        let configPath = (projectPath as NSString).appendingPathComponent(".ddev/config.yaml")
        guard let configContent = try? String(contentsOfFile: configPath) else {
            return nil
        }
        
        for line in configContent.components(separatedBy: .newlines) {
            guard line.trimmingCharacters(in: .whitespaces).hasPrefix("name:") else { continue }
            let parts = line.components(separatedBy: ":")
            guard parts.count > 1 else { continue }
            return parts[1].trimmingCharacters(in: .whitespaces)
        }
        
        return nil
    }
    
    private func openTablePlusWithInfo(projectInfo: ProjectInfo) {
        let connectionURL = buildTablePlusURL(
            driver: projectInfo.dbInfo.driver,
            port: projectInfo.dbInfo.port,
            projectName: projectInfo.name
        )
        openTablePlusApp(with: connectionURL)
    }
    
    private struct DatabaseInfo {
        let driver: String
        let port: String
    }
    
    private struct ProjectInfo {
        let name: String
        let dbInfo: DatabaseInfo
    }
    
    private func parseDdevDescribe(_ jsonString: String) -> ProjectInfo? {
        guard let data = jsonString.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["raw"] as? [String: Any],
              let name = raw["name"] as? String,
              let dbinfo = raw["dbinfo"] as? [String: Any] else {
            return nil
        }
        
        let dbType = (raw["database_type"] as? String ?? dbinfo["database_type"] as? String ?? "").lowercased()
        let driver = dbType.contains("postgres") ? "postgres" : "mysql"
        
        let port: Int
        if let portInt = dbinfo["published_port"] as? Int {
            port = portInt
        } else if let portStr = dbinfo["published_port"] as? String, let portInt = Int(portStr) {
            port = portInt
        } else {
            return nil
        }
        
        return ProjectInfo(name: name, dbInfo: DatabaseInfo(driver: driver, port: String(port)))
    }
    
    private func buildTablePlusURL(driver: String, port: String, projectName: String) -> String {
        "\(driver)://db:db@127.0.0.1:\(port)/db?Enviroment=local&Name=ddev-\(projectName)"
    }
    
    func isTablePlusAvailable() -> Bool {
        let tablePlusPaths = [
            "/Applications/Setapp/TablePlus.app/Contents/MacOS/TablePlus",
            "/Applications/TablePlus.app/Contents/MacOS/TablePlus"
        ]
        
        return tablePlusPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }
    
    func hasDatabase(at projectPath: String) -> Bool {
        let escapedPath = projectPath.replacingOccurrences(of: "\"", with: "\\\"")
        let describeCommand = "cd \"\(escapedPath)\" && \(ddevPath) describe --json-output"
        
        guard let output = runShell(describeCommand),
              let data = output.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["raw"] as? [String: Any],
              let dbinfo = raw["dbinfo"] as? [String: Any] else {
            return false
        }
        
        return dbinfo["published_port"] is Int || dbinfo["published_port"] is String
    }
    
    private func openTablePlusApp(with connectionURL: String) {
        guard let appPath = getTablePlusPath() else {
            print("TablePlus not found in standard locations")
            return
        }
        
        let command = "open \"\(connectionURL)\" -a \"\(appPath)\""
        _ = runShell(command)
        print("Opened TablePlus with connection: \(connectionURL)")
    }
    
    private func getTablePlusPath() -> String? {
        let tablePlusPaths = [
            "/Applications/Setapp/TablePlus.app/Contents/MacOS/TablePlus",
            "/Applications/TablePlus.app/Contents/MacOS/TablePlus"
        ]
        
        return tablePlusPaths.first { FileManager.default.fileExists(atPath: $0) }
    }
    
    func stopProject(_ projectName: String) {
        runShellAsync("\(ddevPath) stop \(projectName)") { _ in
            print("Project \(projectName) stopped")
        }
    }
    
    func startProject(_ projectName: String) {
        runShellAsync("\(ddevPath) start \(projectName)") { _ in
            print("Project \(projectName) started")
        }
    }
    
    func restartProject(_ projectName: String) {
        runShellAsync("\(ddevPath) restart \(projectName)") { _ in
            print("Project \(projectName) restarted")
        }
    }
    
    func runCommand(_ command: String, for projectName: String) {
        runShellAsync("\(ddevPath) \(command) \(projectName)") { output in
            print("Ran '\(command)' for \(projectName)")
            if let output = output, !output.isEmpty {
                print("Output: \(output)")
            }
        }
    }
    
    func getLogs(for projectName: String) -> String? {
        runShell("\(ddevPath) logs \(projectName)")
    }
    
    func getXdebugStatus(at projectPath: String) -> Bool? {
        let escapedPath = projectPath.replacingOccurrences(of: "\"", with: "\\\"")
        let command = "cd \"\(escapedPath)\" && \(ddevPath) xdebug status"
        guard let output = runShell(command) else {
            print("Failed to get xdebug status at \(projectPath)")
            return nil
        }
        let lowercased = output.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        print("xdebug status output at \(projectPath): '\(lowercased)'")
        
        if lowercased.contains("unknown command") || lowercased.contains("error:") {
            print("xdebug command not available for project at \(projectPath)")
            return nil
        }
        
        if lowercased.contains("xdebug enabled") {
            return true
        }
        
        if lowercased.contains("xdebug disabled") {
            return false
        }
        
        if lowercased.contains("enabled") && !lowercased.contains("disabled") {
            return true
        }
        
        return nil
    }
    
    func toggleXdebug(at projectPath: String, completion: ((String?) -> Void)? = nil) {
        let escapedPath = projectPath.replacingOccurrences(of: "\"", with: "\\\"")
        let command = "cd \"\(escapedPath)\" && \(ddevPath) xdebug toggle"
        runShellAsync(command) { output in
            if let output = output, !output.isEmpty {
                print("Toggled xdebug at \(projectPath)")
                print("Output: \(output)")
            }
            completion?(output)
        }
    }
}
