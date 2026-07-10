import Foundation
import SwiftData

/// SwiftData-backed local cache. Views read from here first and render
/// immediately; the network refresh then overwrites (last-write-wins).
@MainActor
final class LocalStore {
    static let shared = LocalStore()

    private let container: ModelContainer?
    private var context: ModelContext? {
        container?.mainContext
    }

    private init() {
        container = try? ModelContainer(
            for: CachedGoal.self,
            CachedPhase.self,
            CachedSession.self,
            CachedCheckin.self,
            PendingMutation.self
        )
    }

    private func save() {
        try? context?.save()
    }

    // MARK: Goals

    func cacheGoals(_ goals: [GoalDTO]) {
        guard let context else {
            return
        }
        let incoming = Set(goals.map(\.id))
        let existing = (try? context.fetch(FetchDescriptor<CachedGoal>())) ?? []
        for stale in existing where !incoming.contains(stale.id) {
            context.delete(stale)
        }
        for goal in goals {
            cacheGoal(goal)
        }
        save()
    }

    func cacheGoal(_ goal: GoalDTO) {
        guard let context else {
            return
        }
        let goalID = goal.id

        if let cached = fetchGoal(goalID) {
            cached.apply(goal)
        } else {
            context.insert(CachedGoal(dto: goal))
        }

        // Replace phases + sessions for this goal wholesale.
        let phaseDescriptor = FetchDescriptor<CachedPhase>(
            predicate: #Predicate { $0.goalId == goalID }
        )
        for phase in (try? context.fetch(phaseDescriptor)) ?? [] {
            context.delete(phase)
        }
        let sessionDescriptor = FetchDescriptor<CachedSession>(
            predicate: #Predicate { $0.goalId == goalID }
        )
        for session in (try? context.fetch(sessionDescriptor)) ?? [] {
            context.delete(session)
        }

        for phase in goal.phases {
            context.insert(CachedPhase(dto: phase, goalId: goal.id))
            for session in phase.sessions {
                context.insert(CachedSession(dto: session))
            }
        }
        save()
    }

    func cachedGoals() -> [GoalDTO] {
        guard let context else {
            return []
        }
        let goals = (try? context.fetch(FetchDescriptor<CachedGoal>())) ?? []
        return goals
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { $0.toDTO(phases: cachedPhases(goalID: $0.id)) }
    }

    func cachedGoal(id: String) -> GoalDTO? {
        fetchGoal(id)?.toDTO(phases: cachedPhases(goalID: id))
    }

    func removeGoal(id: String) {
        guard let context else {
            return
        }

        if let goal = fetchGoal(id) {
            context.delete(goal)
        }

        let phaseDescriptor = FetchDescriptor<CachedPhase>(
            predicate: #Predicate { $0.goalId == id }
        )
        for phase in (try? context.fetch(phaseDescriptor)) ?? [] {
            context.delete(phase)
        }

        let sessionDescriptor = FetchDescriptor<CachedSession>(
            predicate: #Predicate { $0.goalId == id }
        )
        for session in (try? context.fetch(sessionDescriptor)) ?? [] {
            context.delete(session)
        }

        save()
    }

    private func fetchGoal(_ id: String) -> CachedGoal? {
        guard let context else {
            return nil
        }
        let descriptor = FetchDescriptor<CachedGoal>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func cachedPhases(goalID: String) -> [PhaseDTO] {
        guard let context else {
            return []
        }
        let phaseDescriptor = FetchDescriptor<CachedPhase>(
            predicate: #Predicate { $0.goalId == goalID }
        )
        let sessionDescriptor = FetchDescriptor<CachedSession>(
            predicate: #Predicate { $0.goalId == goalID }
        )
        let phases = (try? context.fetch(phaseDescriptor)) ?? []
        let sessions = (try? context.fetch(sessionDescriptor)) ?? []
        let byPhase = Dictionary(grouping: sessions, by: { $0.phaseId ?? "" })

        return phases
            .sorted { $0.order < $1.order }
            .map { phase in
                PhaseDTO(
                    id: phase.id,
                    name: phase.name,
                    order: phase.order,
                    sessions: (byPhase[phase.id] ?? []).map(\.toDTO)
                )
            }
    }

    // MARK: Sessions (Today)

    func cacheSessions(_ sessions: [SessionDTO]) {
        guard let context else {
            return
        }
        for dto in sessions {
            let sessionID = dto.id
            let descriptor = FetchDescriptor<CachedSession>(
                predicate: #Predicate { $0.id == sessionID }
            )
            if let cached = try? context.fetch(descriptor).first {
                cached.apply(dto)
            } else {
                context.insert(CachedSession(dto: dto))
            }
        }
        save()
    }

    func cachedTodaySessions() -> [SessionDTO] {
        guard let context else {
            return []
        }
        let start = Calendar.current.startOfDay(for: .now)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else {
            return []
        }
        let descriptor = FetchDescriptor<CachedSession>(
            predicate: #Predicate { session in
                if let scheduledStart = session.scheduledStart {
                    return scheduledStart >= start && scheduledStart < end
                } else {
                    return false
                }
            },
            sortBy: [SortDescriptor(\.scheduledStart)]
        )
        return ((try? context.fetch(descriptor)) ?? []).map(\.toDTO)
    }

    func markSessionDone(id: String, actualMinutes: Int?) {
        guard let context else {
            return
        }
        let descriptor = FetchDescriptor<CachedSession>(predicate: #Predicate { $0.id == id })
        if let cached = try? context.fetch(descriptor).first {
            cached.status = "done"
            cached.actualMinutes = actualMinutes
            save()
        }
    }

    func setFamiliarity(id: String, value: Int) {
        guard let context else {
            return
        }
        let descriptor = FetchDescriptor<CachedSession>(predicate: #Predicate { $0.id == id })
        if let cached = try? context.fetch(descriptor).first {
            cached.familiarity = value
            cached.assessedAt = .now
            save()
        }
    }

    // MARK: Check-ins

    func cacheCheckin(_ checkin: CheckinDTO) {
        guard let context else {
            return
        }
        let date = checkin.date
        let descriptor = FetchDescriptor<CachedCheckin>(predicate: #Predicate { $0.date == date })
        if let cached = try? context.fetch(descriptor).first {
            cached.energy = checkin.energy
        } else {
            context.insert(CachedCheckin(dto: checkin))
        }
        save()
    }

    func cachedTodayCheckin() -> CheckinDTO? {
        guard let context else {
            return nil
        }
        let today = ISO8601DateFormatter.dateOnly.string(from: .now)
        let descriptor = FetchDescriptor<CachedCheckin>(predicate: #Predicate { $0.date == today })
        return (try? context.fetch(descriptor).first)?.toDTO
    }

    // MARK: Pending mutation queue

    func enqueue(_ mutation: PendingMutation) {
        context?.insert(mutation)
        save()
    }

    func pendingMutations() -> [PendingMutation] {
        guard let context else {
            return []
        }
        let descriptor = FetchDescriptor<PendingMutation>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func remove(_ mutation: PendingMutation) {
        context?.delete(mutation)
        save()
    }
}

extension ISO8601DateFormatter {
    /// `YYYY-MM-DD` only, matching the backend's check-in date format.
    static let dateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
