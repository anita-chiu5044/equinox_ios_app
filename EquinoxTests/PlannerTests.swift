import Testing
import Foundation
@testable import Equinox

@MainActor
struct PlannerTests {
    @Test func templatePlannerAlwaysProducesAPlan() async throws {
        let plan = try await TemplatePlanner().makePlan(
            title: "Organic Chemistry midterm",
            deadline: Date(timeIntervalSinceNow: 14 * 86400),
            materialSummary: nil
        )
        #expect(!plan.phases.isEmpty)
        #expect(plan.phases.count <= 4)
        #expect(plan.phases.allSatisfy { !$0.sessions.isEmpty })
    }

    @Test func validationClampsOutOfRangeFields() throws {
        let plan = GeneratedPlan(phases: [
            GeneratedPhase(name: "", sessions: [
                GeneratedSession(emoji: "", title: "Read chapter", minutes: 999, priority: "urgent", difficulty: 9),
                GeneratedSession(emoji: "📖", title: "   ", minutes: 30, priority: "low", difficulty: 2),
            ]),
        ]).validated()

        #expect(plan.phases.count == 1)
        let session = try #require(plan.phases.first?.sessions.first)
        #expect(plan.phases[0].sessions.count == 1) // blank-title session dropped
        #expect(plan.phases[0].name == "Phase")     // empty name defaulted
        #expect(session.minutes == 180)             // clamped
        #expect(session.priority == "med")          // invalid priority defaulted
        #expect(session.difficulty == 5)            // clamped
        #expect(session.emoji == nil)               // empty emoji nilled
    }

    @Test func emptyPhasesAreDropped() {
        let plan = GeneratedPlan(phases: [
            GeneratedPhase(name: "Empty", sessions: []),
        ]).validated()
        #expect(plan.phases.isEmpty)
    }

    @Test func shortSleepProducesRecoveryHealthAnalysis() {
        let snapshot = HealthKitService.analyze(
            lastNightSleepHours: 5.4,
            sevenDaySleepAverage: 6.2,
            todaySteps: 1_200
        )

        #expect(snapshot.status == "Recovery needed")
        #expect(snapshot.recommendation.contains("recovery"))
    }

    @Test func dailyEnergyAdviceChangesWithStatus() {
        let strong = TodayViewModel.statusAdvice(for: "great")
        let drained = TodayViewModel.statusAdvice(for: "drained")

        #expect(strong.contains("demanding session"))
        #expect(drained.contains("Protect recovery"))
        #expect(strong != drained)
    }

    @Test func overlappingSleepSamplesAreNotDoubleCounted() {
        let start = Date(timeIntervalSince1970: 0)
        let duration = HealthKitService.mergedDuration(of: [
            (start, start.addingTimeInterval(4 * 3600)),
            (start.addingTimeInterval(2 * 3600), start.addingTimeInterval(6 * 3600)),
            (start.addingTimeInterval(7 * 3600), start.addingTimeInterval(8 * 3600)),
        ])

        #expect(duration == 7 * 3600)
    }

    @Test func appleIntelligenceRecheckPromptIncludesUserChangesAndCurrentWork() {
        let goal = GoalDTO(
            id: "goal-1",
            title: "Physics final",
            tag: nil,
            color: "#000000",
            deadline: Date(timeIntervalSince1970: 2_000_000_000),
            status: "active",
            progress: ProgressDTO(doneMinutes: 30, totalMinutes: 75, pct: 40, daysLeft: 5),
            phases: [
                PhaseDTO(id: "phase-1", name: "Practice", order: 0, sessions: [
                    SessionDTO(
                        id: "session-1",
                        goalId: "goal-1",
                        phaseId: "phase-1",
                        emoji: nil,
                        title: "Derive equations",
                        priority: "high",
                        difficulty: 5,
                        minutes: 45,
                        scheduledStart: nil,
                        scheduledEnd: nil,
                        status: "next",
                        actualMinutes: nil,
                        familiarity: nil,
                        assessedAt: nil,
                        measuredUnderstanding: nil
                    ),
                ]),
            ],
            materials: []
        )

        let prompt = OnDevicePlanner.recheckPrompt(
            goal: goal,
            instructions: "Use shorter sessions and emphasize derivations.",
            targetSessionMinutes: 25,
            preserveCompleted: true
        )

        #expect(prompt.contains("Use shorter sessions"))
        #expect(prompt.contains("Target session length: 25 minutes"))
        #expect(prompt.contains("Derive equations"))
        #expect(prompt.contains("Do not repeat sessions marked done"))
    }

    @Test func recheckedPlanUsesTheExplicitTargetLength() {
        let plan = GeneratedPlan(phases: [
            GeneratedPhase(name: "Practice", sessions: [
                GeneratedSession(
                    emoji: nil,
                    title: "Short review",
                    minutes: 90,
                    priority: "high",
                    difficulty: 3
                ),
                GeneratedSession(
                    emoji: nil,
                    title: "Final check",
                    minutes: 45,
                    priority: "med",
                    difficulty: 2
                ),
            ]),
        ])

        let adjusted = plan.usingSessionMinutes(30)

        #expect(adjusted.phases.flatMap(\.sessions).allSatisfy { $0.minutes == 30 })
    }
}
