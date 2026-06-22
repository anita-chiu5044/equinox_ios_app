import Foundation
import SwiftData

// MARK: - Cached mirrors of the contract entities
// Flat tables with string foreign keys, mirroring the backend schema.
// Views render from these immediately; SyncService reconciles with the
// server using last-write-wins.

@Model
final class CachedGoal {
    @Attribute(.unique) var id: String
    var title: String
    var tag: String?
    var color: String
    var deadline: Date?
    var status: String
    var doneMinutes: Int
    var totalMinutes: Int
    var pct: Int
    var daysLeft: Int?
    var updatedAt: Date

    init(dto: GoalDTO) {
        id = dto.id
        title = dto.title
        tag = dto.tag
        color = dto.color
        deadline = dto.deadline
        status = dto.status
        doneMinutes = dto.progress.doneMinutes
        totalMinutes = dto.progress.totalMinutes
        pct = dto.progress.pct
        daysLeft = dto.progress.daysLeft
        updatedAt = .now
    }

    func apply(_ dto: GoalDTO) {
        title = dto.title
        tag = dto.tag
        color = dto.color
        deadline = dto.deadline
        status = dto.status
        doneMinutes = dto.progress.doneMinutes
        totalMinutes = dto.progress.totalMinutes
        pct = dto.progress.pct
        daysLeft = dto.progress.daysLeft
        updatedAt = .now
    }

    func toDTO(phases: [PhaseDTO]) -> GoalDTO {
        GoalDTO(
            id: id,
            title: title,
            tag: tag,
            color: color,
            deadline: deadline,
            status: status,
            progress: ProgressDTO(
                doneMinutes: doneMinutes,
                totalMinutes: totalMinutes,
                pct: pct,
                daysLeft: daysLeft
            ),
            phases: phases,
            materials: []
        )
    }
}

@Model
final class CachedPhase {
    @Attribute(.unique) var id: String
    var goalId: String
    var name: String
    var order: Int

    init(dto: PhaseDTO, goalId: String) {
        id = dto.id
        self.goalId = goalId
        name = dto.name
        order = dto.order
    }
}

@Model
final class CachedSession {
    @Attribute(.unique) var id: String
    var goalId: String
    var phaseId: String?
    var emoji: String?
    var title: String
    var priority: String
    var difficulty: Int
    var minutes: Int
    var scheduledStart: Date?
    var scheduledEnd: Date?
    var status: String
    var actualMinutes: Int?
    var familiarity: Int?
    var assessedAt: Date?

    init(dto: SessionDTO) {
        id = dto.id
        goalId = dto.goalId
        phaseId = dto.phaseId
        emoji = dto.emoji
        title = dto.title
        priority = dto.priority
        difficulty = dto.difficulty
        minutes = dto.minutes
        scheduledStart = dto.scheduledStart
        scheduledEnd = dto.scheduledEnd
        status = dto.status
        actualMinutes = dto.actualMinutes
        familiarity = dto.familiarity
        assessedAt = dto.assessedAt
    }

    func apply(_ dto: SessionDTO) {
        goalId = dto.goalId
        phaseId = dto.phaseId
        emoji = dto.emoji
        title = dto.title
        priority = dto.priority
        difficulty = dto.difficulty
        minutes = dto.minutes
        scheduledStart = dto.scheduledStart
        scheduledEnd = dto.scheduledEnd
        status = dto.status
        actualMinutes = dto.actualMinutes
        familiarity = dto.familiarity
        assessedAt = dto.assessedAt
    }

    var toDTO: SessionDTO {
        SessionDTO(
            id: id,
            goalId: goalId,
            phaseId: phaseId,
            emoji: emoji,
            title: title,
            priority: priority,
            difficulty: difficulty,
            minutes: minutes,
            scheduledStart: scheduledStart,
            scheduledEnd: scheduledEnd,
            status: status,
            actualMinutes: actualMinutes,
            familiarity: familiarity,
            assessedAt: assessedAt,
            measuredUnderstanding: nil
        )
    }
}

@Model
final class CachedCheckin {
    @Attribute(.unique) var date: String
    var energy: String

    init(dto: CheckinDTO) {
        date = dto.date
        energy = dto.energy
    }

    var toDTO: CheckinDTO {
        CheckinDTO(id: "cached-\(date)", date: date, energy: energy)
    }
}

// MARK: - Offline mutation queue

/// A local mutation waiting to be replayed against the backend
/// once connectivity returns.
@Model
final class PendingMutation {
    @Attribute(.unique) var id: String
    /// "complete_session" | "set_familiarity" | "checkin"
    var kind: String
    var targetId: String?
    var intValue: Int?
    var secondIntValue: Int?
    var stringValue: String?
    var createdAt: Date

    init(kind: String, targetId: String? = nil, intValue: Int? = nil, secondIntValue: Int? = nil, stringValue: String? = nil) {
        id = UUID().uuidString
        self.kind = kind
        self.targetId = targetId
        self.intValue = intValue
        self.secondIntValue = secondIntValue
        self.stringValue = stringValue
        createdAt = .now
    }
}
