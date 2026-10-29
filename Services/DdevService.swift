import Foundation
import AppKit

class DdevService {
    private let settings = SettingsManager.shared

    private static let tablePlusPaths = [
        "/Applications/Setapp/TablePlus.app/Contents/MacOS/TablePlus",
        "/Applications/TablePlus.app/Contents/MacOS/TablePlus"
    ]

    /// Quoted for the shell. Falls back to PATH lookup until detection in `init` fills the setting.
    private var ddev: String {
        settings.ddevPath.isEmpty ? "ddev" : shq(settings.ddevPath)
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
        #if DEBUG
        print("Running '\(ddev) list --json-output'")
        #endif

        guard let output = runShell("\(ddev) list --json-output"),
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

    func getMutagenStatus(for projectName: String) -> (status: MutagenSyncStatus, output: String?) {
        guard let output = runShell("\(ddev) mutagen status \(shq(projectName)) 2>&1") else {
            return (.unknown, nil)
        }
        return (MutagenSyncStatus(fromString: output), output)
    }

    func sshIntoProject(at projectPath: String) {
        let terminalApp = settings.terminalApp
        let command = "cd \(shq(projectPath)) && \(ddev) ssh"
        let quoted = "\"" + command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""

        let script: String
        if terminalApp == .iterm {
            script = """
            tell application "iTerm"
                activate
                set new_term to (create window with default profile)
                tell new_term
                    tell the current session
                        write text \(quoted)
                    end tell
                end tell
            end tell
            """
        } else {
            script = """
            tell application "Terminal"
                activate
                do script \(quoted)
            end tell
            """
        }

        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error = error {
            PermissionManager.shared.handleAppleScriptError(error, appName: terminalApp.appName)
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

        _ = runShell("\(ddev) launch \(shq(url))")
    }

    /// Runs shell commands; call off the main thread.
    func openTablePlus(at projectPath: String) {
        guard let output = describe(at: projectPath) else {
            print("Failed to get DDEV project info - command returned no output")
            return
        }
        guard let projectInfo = parseDdevDescribe(output) else {
            print("Failed to parse DDEV describe output (is the project running?)")
            print("Output was: \(String(output.prefix(1000)))")
            return
        }
        guard let appPath = tablePlusPath else {
            print("TablePlus not found in standard locations")
            return
        }

        let connectionURL = "\(projectInfo.driver)://db:db@127.0.0.1:\(projectInfo.port)/db?Enviroment=local&Name=ddev-\(projectInfo.name)"
        _ = runShell("open \(shq(connectionURL)) -a \(shq(appPath))")
        print("Opened TablePlus with connection: \(connectionURL)")
    }

    private struct ProjectInfo {
        let name: String
        let driver: String
        let port: Int
    }

    private func describe(at projectPath: String) -> String? {
        runShell("cd \(shq(projectPath)) && \(ddev) describe --json-output")
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

        return ProjectInfo(name: name, driver: driver, port: port)
    }

    private var tablePlusPath: String? {
        Self.tablePlusPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    func isTablePlusAvailable() -> Bool {
        tablePlusPath != nil
    }

    func hasDatabase(at projectPath: String) -> Bool {
        describe(at: projectPath).flatMap(parseDdevDescribe) != nil
    }

    func stopProject(_ projectName: String) {
        runShellAsync("\(ddev) stop \(shq(projectName))") { _ in
            print("Project \(projectName) stopped")
        }
    }

    func startProject(_ projectName: String) {
        runShellAsync("\(ddev) start \(shq(projectName))") { _ in
            print("Project \(projectName) started")
        }
    }

    func restartProject(_ projectName: String) {
        runShellAsync("\(ddev) restart \(shq(projectName))") { _ in
            print("Project \(projectName) restarted")
        }
    }

    func getXdebugStatus(at projectPath: String) -> Bool? {
        guard let output = runShell("cd \(shq(projectPath)) && \(ddev) xdebug status") else {
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
        runShellAsync("cd \(shq(projectPath)) && \(ddev) xdebug toggle") { output in
            if let output = output, !output.isEmpty {
                print("Toggled xdebug at \(projectPath)")
                print("Output: \(output)")
            }
            completion?(output)
        }
    }
}
