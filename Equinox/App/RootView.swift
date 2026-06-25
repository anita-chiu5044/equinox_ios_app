import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    /// Onboarding step: 0 = rhythm, 1 = connect calendar
    @State private var onboardingStep = 0
    @State private var hasClosedCompletionRewardDemo = false

    var body: some View {
        rootContent
            .task(id: shouldShowCompletionRewardDemo) {
                if !shouldShowCompletionRewardDemo {
                    await appState.restoreSession()
                }
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
        if shouldShowCompletionRewardDemo {
            completionRewardDemo
        } else {
            authenticatedRoot
        }
        #else
        authenticatedRoot
        #endif
    }

    @ViewBuilder
    private var authenticatedRoot: some View {
        if appState.authStatus == .checkingSession {
            ProgressView("Restoring session...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.paper)
        } else if appState.isSignedIn {
            if !onboardingComplete {
                onboardingFlow
            } else {
                MainTabView()
            }
        } else {
            OnboardingWelcomeView()
        }
    }

    private var isCompletionRewardDemo: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--demo-completion-reward")
            || ProcessInfo.processInfo.environment["EQUINOX_DEMO_COMPLETION_REWARD"] == "1"
        #else
        false
        #endif
    }

    private var shouldShowCompletionRewardDemo: Bool {
        isCompletionRewardDemo && !hasClosedCompletionRewardDemo
    }

    private var completionRewardDemo: some View {
        SessionCompletionRewardContent(
            session: SessionDTO(
                id: "demo-completion-session",
                goalId: "demo-goal",
                phaseId: nil,
                emoji: "🪐",
                title: "Understand the electron transport chain and ATP synthesis",
                priority: "medium",
                difficulty: 3,
                minutes: 45,
                scheduledStart: nil,
                scheduledEnd: nil,
                status: "done",
                actualMinutes: 45,
                familiarity: nil,
                assessedAt: nil,
                measuredUnderstanding: nil
            ),
            userName: "Anita",
            actualMinutes: 45,
            completedAt: .now,
            completionOutcome: SessionCompletionOutcome(
                growthReward: GrowthReward(
                    points: 1,
                    didHatch: false,
                    cycle: GrowthCycleDTO(
                        id: "demo-growth-cycle",
                        goalId: "demo-goal",
                        goalTitle: "Biochemistry midterm review",
                        seed: "demo-orbit-seed",
                        visualVariant: "orb-cream",
                        state: "incubating",
                        progress: 3,
                        targetProgress: 5,
                        startedAt: .now,
                        hatchedAt: nil,
                        recentContributions: [],
                        nextSession: nil
                    )
                ),
                planCompletion: PlanCompletionReward(
                    goalId: "demo-goal",
                    goalTitle: "Biochemistry midterm review",
                    completedSessionCount: 5,
                    completedMinutes: 225
                )
            ),
            onDone: {
                hasClosedCompletionRewardDemo = true
            }
        )
    }

    @ViewBuilder
    private var onboardingFlow: some View {
        switch onboardingStep {
        case 0:
            OnboardingRhythmView {
                onboardingStep = 1
            }
        default:
            OnboardingConnectView {
                onboardingComplete = true
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
}
