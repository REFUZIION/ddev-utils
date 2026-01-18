import Foundation

struct DdevListResponse: Codable {
    let level: String?
    let msg: String?
    let raw: [DdevProject]
    let time: String?
}
