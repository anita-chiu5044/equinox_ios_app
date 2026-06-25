import Foundation

struct GrowthCycleDTO: Codable, Identifiable, Equatable {
    let id: String
    let goalId: String
    let goalTitle: String
    let seed: String
    let visualVariant: String
    let state: String
    let progress: Int
    let targetProgress: Int
    let startedAt: Date
    let hatchedAt: Date?
    let recentContributions: [GrowthContributionDTO]
    let nextSession: GrowthSessionDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case goalId = "goal_id"
        case goalTitle = "goal_title"
        case seed
        case visualVariant = "visual_variant"
        case state
        case progress
        case targetProgress = "target_progress"
        case startedAt = "started_at"
        case hatchedAt = "hatched_at"
        case recentContributions = "recent_contributions"
        case nextSession = "next_session"
    }

    var progressText: String {
        "\(progress) / \(targetProgress) glow"
    }

    var isHatched: Bool {
        state == "hatched"
    }
}

struct GrowthContributionDTO: Codable, Identifiable, Equatable {
    let id: String
    let sourceKind: String
    let sourceId: String
    let sourceTitle: String?
    let points: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sourceKind = "source_kind"
        case sourceId = "source_id"
        case sourceTitle = "source_title"
        case points
        case createdAt = "created_at"
    }

    var displayTitle: String {
        sourceTitle ?? "Completed one doable step"
    }

    var displayKind: String {
        sourceKind == "adapted_session_complete" ? "Kept moving on a low-energy day" : "Session completed"
    }
}

struct GrowthSessionDTO: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let minutes: Int
    let scheduledStart: Date?
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case minutes
        case scheduledStart = "scheduled_start"
        case status
    }
}

struct GrowthReward: Equatable {
    let points: Int
    let didHatch: Bool
    let cycle: GrowthCycleDTO?
}

struct PlanCompletionReward: Equatable {
    let goalId: String
    let goalTitle: String
    let completedSessionCount: Int
    let completedMinutes: Int
}

struct SessionCompletionOutcome: Equatable {
    let growthReward: GrowthReward?
    let planCompletion: PlanCompletionReward?
}
