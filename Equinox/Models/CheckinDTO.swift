import Foundation

struct CheckinDTO: Codable, Identifiable, Equatable {
    let id: String
    let date: String
    let energy: String
}

struct CheckinCreateRequest: Encodable {
    let date: String?
    let energy: String
}
