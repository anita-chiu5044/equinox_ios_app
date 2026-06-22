import Foundation

struct UserDTO: Codable, Identifiable, Equatable {
    let id: String
    let email: String?
    let name: String?
    let timezone: String
}
