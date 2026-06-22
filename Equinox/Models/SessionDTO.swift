import Foundation

struct SessionDTO: Codable, Identifiable, Equatable {
    let id: String
    let goalId: String
    let phaseId: String?
    let emoji: String?
    let title: String
    let priority: String
    let difficulty: Int
    let minutes: Int
    let scheduledStart: Date?
    let scheduledEnd: Date?
    let status: String
    let actualMinutes: Int?
    let familiarity: Int?
    let assessedAt: Date?
    let measuredUnderstanding: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case goalId = "goal_id"
        case phaseId = "phase_id"
        case emoji
        case title
        case priority
        case difficulty
        case minutes
        case scheduledStart = "scheduled_start"
        case scheduledEnd = "scheduled_end"
        case status
        case actualMinutes = "actual_minutes"
        case familiarity
        case assessedAt = "assessed_at"
        case measuredUnderstanding = "measured_understanding"
    }
}

struct SessionCreateRequest: Encodable {
    let title: String
    let emoji: String?
    let priority: String
    let difficulty: Int
    let minutes: Int
    let phaseId: String?

    enum CodingKeys: String, CodingKey {
        case title
        case emoji
        case priority
        case difficulty
        case minutes
        case phaseId = "phase_id"
    }
}

struct SessionUpdateRequest: Encodable {
    let title: String?
    let emoji: String?
    let priority: String?
    let difficulty: Int?
    let minutes: Int?
    let status: String?
    let actualMinutes: Int?
    let familiarity: Int?
    let scheduledStart: Date?
    let scheduledEnd: Date?

    enum CodingKeys: String, CodingKey {
        case title
        case emoji
        case priority
        case difficulty
        case minutes
        case status
        case actualMinutes = "actual_minutes"
        case familiarity
        case scheduledStart = "scheduled_start"
        case scheduledEnd = "scheduled_end"
    }
}

extension SessionUpdateRequest {
    static func done(actualMinutes: Int? = nil, familiarity: Int? = nil) -> SessionUpdateRequest {
        SessionUpdateRequest(
            title: nil,
            emoji: nil,
            priority: nil,
            difficulty: nil,
            minutes: nil,
            status: "done",
            actualMinutes: actualMinutes,
            familiarity: familiarity,
            scheduledStart: nil,
            scheduledEnd: nil
        )
    }

    static func familiarity(_ value: Int) -> SessionUpdateRequest {
        SessionUpdateRequest(
            title: nil,
            emoji: nil,
            priority: nil,
            difficulty: nil,
            minutes: nil,
            status: nil,
            actualMinutes: nil,
            familiarity: value,
            scheduledStart: nil,
            scheduledEnd: nil
        )
    }
}
