import Foundation

struct HealthDailyRequest: Codable {
    let date: String?
    let sleepHours: Double?
    let steps: Int?
    let workoutMinutes: Int?
    let cyclePhase: String?
    let cycleImpact: String?
    let source: String

    enum CodingKeys: String, CodingKey {
        case date, source
        case sleepHours = "sleep_hours"
        case steps
        case workoutMinutes = "workout_minutes"
        case cyclePhase = "cycle_phase"
        case cycleImpact = "cycle_impact"
    }
}

struct CapacityDTO: Codable, Equatable {
    let date: String
    let dcs: Int
    let sleepScore: Int?
    let activityScore: Int?
    let fatigueScore: Int?
    let completionScore: Int?
    let cycleScore: Int?

    enum CodingKeys: String, CodingKey {
        case date, dcs
        case sleepScore = "sleep_score"
        case activityScore = "activity_score"
        case fatigueScore = "fatigue_score"
        case completionScore = "completion_score"
        case cycleScore = "cycle_score"
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
