import Foundation

struct SuggestionDTO: Codable, Identifiable, Equatable {
    let id: String
    let goalId: String?
    let kind: String
    let reason: String
    let payload: JSONValue
    let proposedPatch: JSONValue
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, kind, reason, payload, status
        case goalId = "goal_id"
        case proposedPatch = "proposed_patch"
    }

    var options: [SuggestionOptionDTO] {
        guard case .object(let object) = payload,
              case .array(let values)? = object["options"] else {
            return []
        }

        return values.compactMap { value in
            guard case .object(let object) = value else {
                return nil
            }
            return SuggestionOptionDTO(
                key: object["key"]?.stringValue ?? "",
                label: object["label"]?.stringValue ?? "",
                detail: object["detail"]?.stringValue
            )
        }
    }

    /// The sessions this suggestion is about (contract `context_sessions`).
    var contextSessions: [SuggestionContextSessionDTO] {
        guard case .object(let object) = payload,
              case .array(let values)? = object["context_sessions"] else {
            return []
        }

        return values.enumerated().compactMap { index, value in
            guard case .object(let object) = value else {
                return nil
            }
            return SuggestionContextSessionDTO(
                id: "\(index)",
                time: object["time"]?.stringValue,
                title: object["title"]?.stringValue ?? "",
                tag: object["tag"]?.stringValue
            )
        }
    }
}

struct SuggestionContextSessionDTO: Identifiable, Equatable {
    let id: String
    let time: String?
    let title: String
    let tag: String?
}

struct SuggestionOptionDTO: Identifiable, Equatable {
    var id: String {
        key
    }

    let key: String
    let label: String
    let detail: String?
}

struct SuggestionResponseRequest: Encodable {
    let choice: String
    let rejectionReason: String?

    enum CodingKeys: String, CodingKey {
        case choice
        case rejectionReason = "rejection_reason"
    }
}

struct SuggestionPreviewDTO: Codable, Equatable {
    let suggestion: SuggestionDTO
    let schedule: SchedulePreviewDTO
    let changes: [String]
    let feasible: Bool
    let reason: String?
    let affectedSessions: [SuggestionImpactDTO]
    let totalMinutesBefore: Int
    let totalMinutesAfter: Int

    enum CodingKeys: String, CodingKey {
        case suggestion, schedule, changes, feasible, reason
        case affectedSessions = "affected_sessions"
        case totalMinutesBefore = "total_minutes_before"
        case totalMinutesAfter = "total_minutes_after"
    }
}

struct SuggestionImpactDTO: Codable, Identifiable, Equatable {
    let sessionId: String
    let title: String
    let before: SuggestionTimingDTO
    let after: SuggestionTimingDTO

    var id: String { sessionId }

    enum CodingKeys: String, CodingKey {
        case title, before, after
        case sessionId = "session_id"
    }
}

struct SuggestionTimingDTO: Codable, Equatable {
    let start: String?
    let end: String?
    let minutes: Int
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
