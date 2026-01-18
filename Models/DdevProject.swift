import Foundation

/// Represents a DDEV project from the `ddev list --json-output` command.
struct DdevProject: Codable, Identifiable {
    var id: String { name }
    let name: String
    let status: String
    let statusDesc: String?
    let type: String?
    let approot: String?
    let shortroot: String?
    let httpurl: String?
    let httpsurl: String?
    let primaryUrl: String?
    let mutagenEnabled: Bool?
    let mutagenStatus: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case status
        case statusDesc = "status_desc"
        case type
        case approot
        case shortroot
        case httpurl
        case httpsurl
        case primaryUrl = "primary_url"
        case mutagenEnabled = "mutagen_enabled"
        case mutagenStatus = "mutagen_status"
    }
}
