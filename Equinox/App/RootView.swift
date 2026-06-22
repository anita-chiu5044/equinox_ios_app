import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    /// Onboarding step: 0 = rhythm, 1 = connect calendar
    @State private var onboardingStep = 0

    var body: some View {
        Group {
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
        .task {
            await appState.restoreSession()
        }
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
