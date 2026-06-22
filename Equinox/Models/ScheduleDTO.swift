import Foundation

struct SchedulePreviewDTO: Codable, Equatable {
    let weekStart: String
    let ghosts: [GhostEventDTO]
    let placed: [PlacedSessionDTO]

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case ghosts
        case placed
    }
}

struct GhostEventDTO: Codable, Identifiable, Equatable {
    var id: String {
        "\(day)-\(start)-\(end)-\(label)"
    }

    let day: Int
    let start: String
    let end: String
    let label: String
}

struct PlacedSessionDTO: Codable, Identifiable, Equatable {
    var id: String {
        sessionId
    }

    let sessionId: String
    let day: Int
    let start: String
    let end: String
    let emoji: String?
    let label: String
    let personalizationReason: String?
    let confidence: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case day
        case start
        case end
        case emoji
        case label
        case personalizationReason = "personalization_reason"
        case confidence
    }
}
