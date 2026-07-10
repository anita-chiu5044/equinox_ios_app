import Foundation

struct SettingsDTO: Codable, Equatable {
    let suggestionsEnabled: Bool
    let dailyCheckinEnabled: Bool
    let suggestionMode: String
    let showCalendarEventTitles: Bool

    enum CodingKeys: String, CodingKey {
        case suggestionsEnabled = "suggestions_enabled"
        case dailyCheckinEnabled = "daily_checkin_enabled"
        case suggestionMode = "suggestion_mode"
        case showCalendarEventTitles = "show_calendar_event_titles"
    }
}

struct SettingsUpdateRequest: Encodable {
    let suggestionsEnabled: Bool?
    let dailyCheckinEnabled: Bool?
    let suggestionMode: String?
    let showCalendarEventTitles: Bool?

    enum CodingKeys: String, CodingKey {
        case suggestionsEnabled = "suggestions_enabled"
        case dailyCheckinEnabled = "daily_checkin_enabled"
        case suggestionMode = "suggestion_mode"
        case showCalendarEventTitles = "show_calendar_event_titles"
    }
}

struct ConnectionsDTO: Codable, Equatable {
    let googleCalendar: ConnectionStateDTO
    let health: ConnectionStateDTO

    enum CodingKeys: String, CodingKey {
        case googleCalendar = "google_calendar"
        case health
    }
}

struct ConnectionStateDTO: Codable, Equatable {
    let connected: Bool
    let scopes: [String]
}

/// OAuth authorization code from the on-device Google consent flow; the
/// backend exchanges it and stores the Calendar refresh token server-side.
struct GoogleCalendarConnectRequest: Encodable {
    let code: String
    let codeVerifier: String
    let redirectURI: String

    enum CodingKeys: String, CodingKey {
        case code
        case codeVerifier = "code_verifier"
        case redirectURI = "redirect_uri"
    }
}
