import Foundation

struct AuthRequest: Encodable {
    let identityToken: String?
    let idToken: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case idToken = "id_token"
        case name
    }
}

struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let user: UserDTO

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case user
    }
}
