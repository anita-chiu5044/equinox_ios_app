import Foundation

struct HealthDailyRequest: Codable {
    let date: String?
    let sleepHours: Double?
    let steps: Int?
    let workoutMinutes: Int?
    let source: String

    enum CodingKeys: String, CodingKey {
        case date, source
        case sleepHours = "sleep_hours"
        case steps
        case workoutMinutes = "workout_minutes"
    }
}

struct CapacityDTO: Codable, Equatable {
    let date: String
    let dcs: Int
    let sleepScore: Int?
    let activityScore: Int?
    let fatigueScore: Int?
    let completionScore: Int?

    enum CodingKeys: String, CodingKey {
        case date, dcs
        case sleepScore = "sleep_score"
        case activityScore = "activity_score"
        case fatigueScore = "fatigue_score"
        case completionScore = "completion_score"
    }
}

struct LearningProfileDTO: Codable, Equatable {
    let profile: JSONValue
    let sampleCount: Int
    let version: String
    let confidence: String
    let promptContext: String

    enum CodingKeys: String, CodingKey {
        case profile, version, confidence
        case promptContext = "prompt_context"
        case sampleCount = "sample_count"
    }
}
