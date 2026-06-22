import Foundation

struct GoalDTO: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let tag: String?
    let color: String
    let deadline: Date?
    let status: String
    let progress: ProgressDTO
    let phases: [PhaseDTO]
    let materials: [MaterialDTO]
}

struct GoalCreateRequest: Encodable {
    let title: String
    let deadline: Date?
    let tag: String?
    let color: String
    let materialIds: [String]
    let sourceText: String?
    let generatedPhases: [ReplanPhaseRequest]?

    enum CodingKeys: String, CodingKey {
        case title
        case deadline
        case tag
        case color
        case materialIds = "material_ids"
        case sourceText = "source_text"
        case generatedPhases = "generated_phases"
    }
}

struct GoalUpdateRequest: Encodable {
    let title: String?
    let deadline: Date?
    let tag: String?
    let color: String?
    let status: String?
}

struct ReplanGoalRequest: Encodable {
    let instructions: String
    let targetSessionMinutes: Int
    let preserveCompleted: Bool
    let generatedPhases: [ReplanPhaseRequest]?
    let source: String

    enum CodingKeys: String, CodingKey {
        case instructions
        case targetSessionMinutes = "target_session_minutes"
        case preserveCompleted = "preserve_completed"
        case generatedPhases = "generated_phases"
        case source
    }
}

struct ReplanPhaseRequest: Encodable {
    let name: String
    let sessions: [ReplanSessionRequest]
}

struct ReplanSessionRequest: Encodable {
    let emoji: String?
    let title: String
    let priority: String
    let difficulty: Int
    let minutes: Int
}

extension GeneratedPlan {
    var goalCreatePhases: [ReplanPhaseRequest] {
        replanRequestPhases
    }

    var replanRequestPhases: [ReplanPhaseRequest] {
        phases.map { phase in
            ReplanPhaseRequest(
                name: phase.name,
                sessions: phase.sessions.map { session in
                    ReplanSessionRequest(
                        emoji: session.emoji,
                        title: session.title,
                        priority: session.priority,
                        difficulty: session.difficulty,
                        minutes: session.minutes
                    )
                }
            )
        }
    }
}

struct RecheckChangeSummary: Equatable {
    let source: String
    let targetMinutes: Int
    let previousRemainingCount: Int
    let updatedRemainingCount: Int
    let previousRemainingMinutes: Int
    let updatedRemainingMinutes: Int
    let preservedCompletedCount: Int
    let changedTitles: [String]

    static func make(
        before: GoalDTO,
        after: GoalDTO,
        source: String,
        targetMinutes: Int,
        preserveCompleted: Bool
    ) -> RecheckChangeSummary {
        let beforeSessions = before.phases.flatMap(\.sessions)
        let afterSessions = after.phases.flatMap(\.sessions)
        let beforeRemaining = beforeSessions.filter { $0.status != "done" }
        let afterRemaining = afterSessions.filter { $0.status != "done" }
        let previousTitles = Set(beforeRemaining.map { $0.title.lowercased() })
        let changedTitles = afterRemaining
            .map(\.title)
            .filter { !previousTitles.contains($0.lowercased()) }

        return RecheckChangeSummary(
            source: source,
            targetMinutes: targetMinutes,
            previousRemainingCount: beforeRemaining.count,
            updatedRemainingCount: afterRemaining.count,
            previousRemainingMinutes: beforeRemaining.reduce(0) { $0 + $1.minutes },
            updatedRemainingMinutes: afterRemaining.reduce(0) { $0 + $1.minutes },
            preservedCompletedCount: preserveCompleted
                ? afterSessions.filter { $0.status == "done" }.count
                : 0,
            changedTitles: Array(changedTitles.prefix(3))
        )
    }
}

struct ProgressDTO: Codable, Equatable {
    let doneMinutes: Int
    let totalMinutes: Int
    let pct: Int
    let daysLeft: Int?

    enum CodingKeys: String, CodingKey {
        case doneMinutes = "done_minutes"
        case totalMinutes = "total_minutes"
        case pct
        case daysLeft = "days_left"
    }
}

struct PhaseDTO: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let order: Int
    let sessions: [SessionDTO]
}

struct MaterialDTO: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let type: String
    let sizeBytes: Int
    let storagePath: String?
    let extractionStatus: String
    let extractionError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case sizeBytes = "size_bytes"
        case storagePath = "storage_path"
        case extractionStatus = "extraction_status"
        case extractionError = "extraction_error"
    }
}
