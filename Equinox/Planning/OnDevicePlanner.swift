import Foundation

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Generable schema for the on-device model

@available(iOS 26.0, *)
@Generable
struct AIGeneratedPlan {
    @Guide(description: "2 to 4 ordered study phases that build on each other")
    var phases: [AIGeneratedPhase]
}

@available(iOS 26.0, *)
@Generable
struct AIGeneratedPhase {
    @Guide(description: "Short phase name, e.g. Foundations, Practice, Consolidation")
    var name: String

    @Guide(description: "2 to 6 concrete study sessions for this phase")
    var sessions: [AIGeneratedSession]
}

@available(iOS 26.0, *)
@Generable
struct AIGeneratedSession {
    @Guide(description: "One emoji that fits the session")
    var emoji: String

    @Guide(description: "Concrete, actionable session title a student can start immediately")
    var title: String

    @Guide(description: "Estimated focused minutes, between 20 and 120")
    var minutes: Int

    @Guide(description: "Priority: exactly one of low, med, high")
    var priority: String

    @Guide(description: "Cognitive difficulty from 1 (light review) to 5 (deep focus)")
    var difficulty: Int
}
#endif

// MARK: - Planner

/// Apple Intelligence planner: decomposes a study goal entirely on-device
/// using the FoundationModels system language model. No data leaves the phone.
struct OnDevicePlanner: Planner {
    let origin = PlanOrigin.appleIntelligence

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    static func recheckPrompt(
        goal: GoalDTO,
        instructions: String,
        targetSessionMinutes: Int,
        preserveCompleted: Bool,
        personalLearningContext: String? = nil
    ) -> String {
        let sessions = goal.phases
            .sorted { $0.order < $1.order }
            .flatMap { phase in
                phase.sessions.map { session in
                    "- [\(session.status)] \(phase.name): \(session.title) " +
                    "(\(session.minutes) min, \(session.priority), difficulty \(session.difficulty))"
                }
            }
            .joined(separator: "\n")

        var prompt = """
            Goal: \(goal.title)
            User-requested changes: \(instructions.isEmpty ? "Improve the schedule while keeping it realistic." : instructions)
            Target session length: \(targetSessionMinutes) minutes
            Preserve completed sessions: \(preserveCompleted ? "yes" : "no")

            Current plan:
            \(sessions)
            """
        if let deadline = goal.deadline {
            prompt += "\nDeadline: \(deadline.formatted(date: .abbreviated, time: .omitted))"
        }
        if !goal.materials.isEmpty {
            prompt += "\nMaterials: " + goal.materials.map(\.name).joined(separator: ", ")
        }
        if preserveCompleted {
            prompt += "\nReturn only the remaining work. Do not repeat sessions marked done."
        } else {
            prompt += "\nRedesign the complete plan, including work that was previously marked done."
        }
        if let personalLearningContext, !personalLearningContext.isEmpty {
            prompt += "\n\n\(personalLearningContext)"
        }
        return prompt
    }

    func makePlan(
        title: String,
        deadline: Date?,
        materialSummary: String?,
        personalLearningContext: String? = nil
    ) async throws -> GeneratedPlan {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else {
                throw PlannerError.unavailable
            }

            let session = LanguageModelSession(instructions: """
                You are a study planner. Decompose a learning goal into 2-4 \
                ordered phases, each with 2-6 concrete study sessions. \
                Sessions must be specific and actionable (not "study more"). \
                Estimate realistic minutes (20-120), a priority (low/med/high), \
                and a difficulty (1-5, where 5 is deep focus work like solving \
                hard problems and 1 is light review).
                """)

            var prompt = "Goal: \(title)"
            if let deadline {
                let days = Calendar.current.dateComponents(
                    [.day],
                    from: .now,
                    to: deadline
                ).day ?? 0
                prompt += "\nDeadline: \(deadline.formatted(date: .abbreviated, time: .omitted)) (\(max(days, 0)) days from now)"
            }
            if let materialSummary, !materialSummary.isEmpty {
                prompt += "\nMaterial excerpt:\n\(String(materialSummary.prefix(2000)))"
            }
            if let personalLearningContext, !personalLearningContext.isEmpty {
                prompt += "\n\n\(personalLearningContext)"
            }

            let response = try await session.respond(to: prompt, generating: AIGeneratedPlan.self)
            let plan = GeneratedPlan(
                phases: response.content.phases.map { phase in
                    GeneratedPhase(
                        name: phase.name,
                        sessions: phase.sessions.map { item in
                            GeneratedSession(
                                emoji: item.emoji,
                                title: item.title,
                                minutes: item.minutes,
                                priority: item.priority,
                                difficulty: item.difficulty
                            )
                        }
                    )
                }
            ).validated()

            guard !plan.phases.isEmpty else {
                throw PlannerError.emptyPlan
            }
            return plan
        }
        #endif
        throw PlannerError.unavailable
    }

    func makeRecheckedPlan(
        goal: GoalDTO,
        instructions: String,
        targetSessionMinutes: Int,
        preserveCompleted: Bool,
        personalLearningContext: String? = nil
    ) async throws -> GeneratedPlan {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else {
                throw PlannerError.unavailable
            }

            let session = LanguageModelSession(instructions: """
                You are Equinox's on-device schedule recheck engine. Revise a user's \
                existing learning plan according to their requested changes. Produce \
                2-4 ordered phases with concrete, actionable sessions. Aim for the \
                requested session length exactly, use priority low/med/high, and difficulty 1-5. \
                Respect completed-work instructions exactly and never duplicate a \
                completed session when the user asks to preserve it.
                """)

            let prompt = Self.recheckPrompt(
                goal: goal,
                instructions: instructions,
                targetSessionMinutes: targetSessionMinutes,
                preserveCompleted: preserveCompleted,
                personalLearningContext: personalLearningContext
            )
            let response = try await session.respond(
                to: prompt,
                generating: AIGeneratedPlan.self
            )
            let plan = GeneratedPlan(
                phases: response.content.phases.map { phase in
                    GeneratedPhase(
                        name: phase.name,
                        sessions: phase.sessions.map { item in
                            GeneratedSession(
                                emoji: item.emoji,
                                title: item.title,
                                minutes: item.minutes,
                                priority: item.priority,
                                difficulty: item.difficulty
                            )
                        }
                    )
                }
            )
                .validated()
                .usingSessionMinutes(targetSessionMinutes)

            guard !plan.phases.isEmpty else {
                throw PlannerError.emptyPlan
            }
            return plan
        }
        #endif
        throw PlannerError.unavailable
    }
}
