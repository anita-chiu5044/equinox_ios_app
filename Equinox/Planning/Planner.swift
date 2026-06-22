import Foundation

// MARK: - Generated plan domain model

struct GeneratedPlan: Equatable {
    var phases: [GeneratedPhase]

    /// Clamp every field into contract-legal ranges and drop empty phases.
    func validated() -> GeneratedPlan {
        let cleaned = phases.compactMap { phase -> GeneratedPhase? in
            let sessions = phase.sessions
                .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { $0.validated() }
            guard !sessions.isEmpty else {
                return nil
            }
            return GeneratedPhase(
                name: phase.name.isEmpty ? "Phase" : phase.name,
                sessions: sessions
            )
        }
        return GeneratedPlan(phases: Array(cleaned.prefix(4)))
    }

    func usingSessionMinutes(_ minutes: Int) -> GeneratedPlan {
        let target = min(max(minutes, 20), 120)
        return GeneratedPlan(phases: phases.map { phase in
            GeneratedPhase(
                name: phase.name,
                sessions: phase.sessions.map { session in
                    GeneratedSession(
                        emoji: session.emoji,
                        title: session.title,
                        minutes: target,
                        priority: session.priority,
                        difficulty: session.difficulty
                    )
                }
            )
        })
    }
}

struct GeneratedPhase: Equatable {
    var name: String
    var sessions: [GeneratedSession]
}

struct GeneratedSession: Equatable {
    var emoji: String?
    var title: String
    var minutes: Int
    var priority: String
    var difficulty: Int

    func validated() -> GeneratedSession {
        GeneratedSession(
            emoji: emoji?.isEmpty == true ? nil : emoji,
            title: title,
            minutes: min(max(minutes, 10), 180),
            priority: ["low", "med", "high"].contains(priority) ? priority : "med",
            difficulty: min(max(difficulty, 1), 5)
        )
    }
}

// MARK: - Planner protocol

enum PlanOrigin: String {
    case appleIntelligence = "Apple Intelligence"
    case backend = "Equinox Cloud"
    case template = "Starter template"
}

enum PlannerError: LocalizedError {
    case unavailable
    case emptyPlan

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "On-device planning is not available on this device."
        case .emptyPlan:
            "The planner returned an empty plan."
        }
    }
}

protocol Planner: Sendable {
    var origin: PlanOrigin { get }
    func makePlan(
        title: String,
        deadline: Date?,
        materialSummary: String?,
        personalLearningContext: String?
    ) async throws -> GeneratedPlan
}

// MARK: - Deterministic fallback

/// Last-resort planner: a sensible three-phase template that always works,
/// fully offline, with no model dependency.
struct TemplatePlanner: Planner {
    let origin = PlanOrigin.template

    func makePlan(
        title: String,
        deadline: Date?,
        materialSummary: String?,
        personalLearningContext: String? = nil
    ) async throws -> GeneratedPlan {
        GeneratedPlan(phases: [
            GeneratedPhase(name: "Foundations", sessions: [
                GeneratedSession(emoji: "📖", title: "Survey the scope of \(title)", minutes: 40, priority: "high", difficulty: 2),
                GeneratedSession(emoji: "🗂️", title: "Collect notes and materials", minutes: 30, priority: "med", difficulty: 1),
                GeneratedSession(emoji: "📖", title: "Read core chapters", minutes: 60, priority: "high", difficulty: 3),
            ]),
            GeneratedPhase(name: "Practice", sessions: [
                GeneratedSession(emoji: "✏️", title: "Work through practice problems", minutes: 60, priority: "high", difficulty: 4),
                GeneratedSession(emoji: "🧠", title: "Summarize tricky concepts", minutes: 40, priority: "med", difficulty: 3),
            ]),
            GeneratedPhase(name: "Consolidation", sessions: [
                GeneratedSession(emoji: "🔁", title: "Review mistakes and weak spots", minutes: 40, priority: "med", difficulty: 3),
                GeneratedSession(emoji: "✅", title: "Final timed self-test", minutes: 45, priority: "high", difficulty: 4),
            ]),
        ]).validated()
    }
}

// MARK: - Coordinator

/// Picks the best available planner, preferring Apple Intelligence on-device
/// planning, with the deterministic template as the always-works fallback.
struct PlannerCoordinator {
    func makePlan(
        title: String,
        deadline: Date?,
        materialSummary: String?,
        personalLearningContext: String? = nil
    ) async -> (plan: GeneratedPlan, origin: PlanOrigin)? {
        if OnDevicePlanner.isAvailable {
            let planner = OnDevicePlanner()
            if let plan = try? await planner.makePlan(
                title: title,
                deadline: deadline,
                materialSummary: materialSummary,
                personalLearningContext: personalLearningContext
            ), !plan.phases.isEmpty {
                return (plan, planner.origin)
            }
        }

        let template = TemplatePlanner()
        if let plan = try? await template.makePlan(
            title: title,
            deadline: deadline,
            materialSummary: materialSummary,
            personalLearningContext: personalLearningContext
        ) {
            return (plan, template.origin)
        }

        return nil
    }
}
