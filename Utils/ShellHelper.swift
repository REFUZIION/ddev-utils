import Foundation

func runShell(_ command: String, shellPath: String? = nil) -> String? {
    let task = Process()
    let pipe = Pipe()
    
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-l", "-c", command]
    
    let shell = shellPath ?? SettingsManager.shared.effectiveShellPath
    task.launchPath = shell
    
    var environment = ProcessInfo.processInfo.environment
    let additionalPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin"
    if let existingPath = environment["PATH"] {
        environment["PATH"] = "\(additionalPaths):\(existingPath)"
    } else {
        environment["PATH"] = additionalPaths
    }
    
    if environment["HOME"] == nil {
        environment["HOME"] = NSHomeDirectory()
    }
    task.environment = environment
    
    do {
        try task.run()
    } catch {
        print("Error launching shell command '\(command)' with shell '\(shell)': \(error)")
        return nil
    }
    
    let fileHandle = pipe.fileHandleForReading
    var outputData = Data()
    
    while true {
        let availableData = fileHandle.availableData
        guard !availableData.isEmpty else { break }
        outputData.append(availableData)
    }
    
    task.waitUntilExit()
    
    let output = String(data: outputData, encoding: .utf8)
    
    if task.terminationStatus != 0 {
        print("Command '\(command)' exited with status \(task.terminationStatus)")
    }
    
    return output
}

func runShellAsync(_ command: String, completion: @escaping (String?) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let result = runShell(command)
        DispatchQueue.main.async {
            completion(result)
        }
    }
}

func detectDdevPath() -> String? {
    // Last line only: a login shell may print profile noise first.
    guard let output = runShell("command -v ddev", shellPath: "/bin/bash"),
          let path = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).last,
          !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
    return path
}

/// Quotes a value for safe use as one shell argument.
func shq(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
