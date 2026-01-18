import Foundation

/// Represents detailed Mutagen status from `ddev mutagen status`
struct MutagenStatus {
    let projectName: String
    let status: MutagenSyncStatus
    let rawOutput: String?
    
    init(projectName: String, status: MutagenSyncStatus, rawOutput: String? = nil) {
        self.projectName = projectName
        self.status = status
        self.rawOutput = rawOutput
    }
}
