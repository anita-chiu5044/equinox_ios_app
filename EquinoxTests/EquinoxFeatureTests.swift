import Testing
import Foundation
@testable import Equinox

// MARK: - TodayViewModel edge-state logic

@MainActor
struct TodayViewModelTests {

    @Test func statusAdviceCoversAllKnownEnergyKeys() {
        let keys = ["great", "ok", "tired", "drained"]
        for key in keys {
            let advice = TodayViewModel.statusAdvice(for: key)
            #expect(!advice.isEmpty, "Expected non-empty advice for energy key '\(key)'")
        }
    }

    @Test func statusAdviceFallbackForUnknownKey() {
        let advice = TodayViewModel.statusAdvice(for: "unknown_key")
        #expect(advice.contains("guide"), "Fallback advice should mention using energy as a guide")
    }

    @Test func heroSessionPrefersNowStatus() {
        // Arrange — first session is "next", second is "now"
        let sessions: [SessionDTO] = [
            makeSession(id: "s1", status: "next"),
            makeSession(id: "s2", status: "now"),
        ]
        let hero = sessions.first { $0.status == "now" }
                ?? sessions.first { $0.status != "done" }
        #expect(hero?.id == "s2")
    }

    @Test func heroSessionFallsBackToFirstNonDone() {
        let sessions: [SessionDTO] = [
            makeSession(id: "s1", status: "done"),
            makeSession(id: "s2", status: "next"),
            makeSession(id: "s3", status: "next"),
        ]
        let hero = sessions.first { $0.status == "now" }
                ?? sessions.first { $0.status != "done" }
        #expect(hero?.id == "s2")
    }

    @Test func heroSessionIsNilWhenAllDone() {
        let sessions: [SessionDTO] = [
            makeSession(id: "s1", status: "done"),
            makeSession(id: "s2", status: "done"),
        ]
        let hero = sessions.first { $0.status == "now" }
                ?? sessions.first { $0.status != "done" }
        #expect(hero == nil)
    }

    // Helper
    private func makeSession(id: String, status: String) -> SessionDTO {
        SessionDTO(
            id: id,
            goalId: "g1",
            phaseId: nil,
            emoji: nil,
            title: "Test session",
            priority: "med",
            difficulty: 3,
            minutes: 45,
            scheduledStart: nil,
            scheduledEnd: nil,
            status: status,
            actualMinutes: nil,
            familiarity: nil,
            assessedAt: nil,
            measuredUnderstanding: nil
        )
    }
}

// MARK: - OnboardingRhythmView hour formatting

struct OnboardingRhythmFormatTests {

    private func formatHour(_ hour: Double) -> String {
        let h = Int(hour)
        let m = hour.truncatingRemainder(dividingBy: 1) == 0.5 ? 30 : 0
        let ampm = h < 12 ? "AM" : "PM"
        let displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        if m == 0 {
            return "\(displayH) \(ampm)"
        } else {
            return "\(displayH):30 \(ampm)"
        }
    }

    @Test func midnight() {
        #expect(formatHour(0.0) == "12 AM")
    }

    @Test func noon() {
        #expect(formatHour(12.0) == "12 PM")
    }

    @Test func morningWholeHour() {
        #expect(formatHour(9.0) == "9 AM")
    }

    @Test func afternoonWholeHour() {
        #expect(formatHour(17.0) == "5 PM")
    }

    @Test func halfPastMorning() {
        #expect(formatHour(9.5) == "9:30 AM")
    }

    @Test func halfPastEvening() {
        #expect(formatHour(21.5) == "9:30 PM")
    }

    @Test func oneAM() {
        #expect(formatHour(1.0) == "1 AM")
    }
}

// MARK: - RangeSlider value clamping logic

struct RangeSliderTests {

    private func clampStart(raw: Double, range: ClosedRange<Double>, step: Double, endValue: Double) -> Double {
        let snapped = (raw / step).rounded() * step
        return min(max(snapped, range.lowerBound), endValue - step)
    }

    private func clampEnd(raw: Double, range: ClosedRange<Double>, step: Double, startValue: Double) -> Double {
        let snapped = (raw / step).rounded() * step
        return min(max(snapped, startValue + step), range.upperBound)
    }

    @Test func startCannotPassEnd() {
        let end = 17.0
        let result = clampStart(raw: 20.0, range: 5...23, step: 0.5, endValue: end)
        #expect(result < end)
    }

    @Test func endCannotPassStart() {
        let start = 9.0
        let result = clampEnd(raw: 5.0, range: 5...23, step: 0.5, startValue: start)
        #expect(result > start)
    }

    @Test func valuesSnapToStep() {
        let result = clampStart(raw: 9.3, range: 5...23, step: 0.5, endValue: 17.0)
        #expect(result == 9.5)
    }

    @Test func startCannotGoBelowRangeLower() {
        let result = clampStart(raw: -5.0, range: 5...23, step: 0.5, endValue: 17.0)
        #expect(result >= 5.0)
    }

    @Test func endCannotExceedRangeUpper() {
        let result = clampEnd(raw: 30.0, range: 5...23, step: 0.5, startValue: 9.0)
        #expect(result <= 23.0)
    }
}

// MARK: - GoalDetailView familiarity labels

struct FamiliarityLabelTests {

    @Test func allFourLabelsExist() {
        #expect(GoalDetailView.familiarityLabels.count == 4)
    }

    @Test func labelsAreNonEmpty() {
        for label in GoalDetailView.familiarityLabels {
            #expect(!label.isEmpty)
        }
    }

    @Test func labelsIncreaseCognitiveDemand() {
        // The fourth label should indicate mastery
        let last = GoalDetailView.familiarityLabels.last ?? ""
        #expect(last.lowercased().contains("teach"))
    }
}

// MARK: - AppState deleteAccount

@MainActor
struct AppStateTests {

    @Test func signOutClearsUser() {
        let appState = AppState()
        appState.signInForPreview()
        #expect(appState.user != nil)
        appState.signOut()
        #expect(appState.user == nil)
        #expect(appState.authStatus == .signedOut)
    }

    @Test func isSignedInReflectsUserPresence() {
        let appState = AppState()
        #expect(!appState.isSignedIn)
        appState.signInForPreview()
        #expect(appState.isSignedIn)
    }
}

// MARK: - SchedulePreviewDTO day filtering (logic mirror)

struct SchedulePreviewTests {

    private func slot(sessionId: String, day: Int, label: String) -> PlacedSessionDTO {
        PlacedSessionDTO(
            sessionId: sessionId,
            day: day,
            start: "09:00",
            end: "10:00",
            emoji: nil,
            label: label,
            personalizationReason: nil,
            confidence: nil
        )
    }

    @Test func dayFilterReturnsOnlyMatchingSlots() {
        let placed = [
            slot(sessionId: "s1", day: 0, label: "Monday session"),
            slot(sessionId: "s2", day: 2, label: "Wednesday session"),
            slot(sessionId: "s3", day: 0, label: "Another Monday"),
        ]

        let monday    = placed.filter { $0.day == 0 }
        let wednesday = placed.filter { $0.day == 2 }
        let thursday  = placed.filter { $0.day == 3 }

        #expect(monday.count == 2)
        #expect(wednesday.count == 1)
        #expect(thursday.isEmpty)
    }

    @Test func totalSessionCountIsCorrect() {
        let placed = [
            slot(sessionId: "s1", day: 0, label: "A"),
            slot(sessionId: "s2", day: 1, label: "B"),
        ]
        let activeDays = (0..<7).filter { day in !placed.filter { $0.day == day }.isEmpty }.count
        #expect(placed.count == 2)
        #expect(activeDays == 2)
    }
}

// MARK: - GeneratedPlan validation (extended)

struct GeneratedPlanValidationTests {

    @Test func sessionWithZeroMinutesIsClamped() {
        // validated() clamps minutes to min(max(x, 10), 180) — zero becomes 10, not dropped.
        let plan = GeneratedPlan(phases: [
            GeneratedPhase(name: "Phase", sessions: [
                GeneratedSession(emoji: nil, title: "Zero minutes", minutes: 0, priority: "med", difficulty: 3),
            ]),
        ]).validated()

        let session = plan.phases.flatMap(\.sessions).first
        #expect(session?.minutes == 10, "0-minute session should be clamped to minimum 10")
    }

    @Test func highPriorityKeywordIsPreserved() {
        let plan = GeneratedPlan(phases: [
            GeneratedPhase(name: "Phase", sessions: [
                GeneratedSession(emoji: nil, title: "Exam prep", minutes: 45, priority: "high", difficulty: 4),
            ]),
        ]).validated()

        #expect(plan.phases.first?.sessions.first?.priority == "high")
    }
}
