import SwiftUI

/// Captures the two feedback signals needed for continual learning before a
/// completed session is sent to the backend.
struct CompletionFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: SessionDTO
    let userName: String?
    let measuredActualMinutes: Int?
    let onSubmit: (Int, Int) async -> SessionCompletionOutcome

    @State private var actualMinutes: Int
    @State private var familiarity = 3
    @State private var isSubmitting = false
    @State private var completedAt: Date?
    @State private var completionOutcome: SessionCompletionOutcome?

    init(
        session: SessionDTO,
        userName: String?,
        measuredActualMinutes: Int? = nil,
        onSubmit: @escaping (Int, Int) async -> SessionCompletionOutcome
    ) {
        self.session = session
        self.userName = userName
        self.measuredActualMinutes = measuredActualMinutes
        self.onSubmit = onSubmit
        _actualMinutes = State(initialValue: measuredActualMinutes ?? session.actualMinutes ?? session.minutes)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let completedAt {
                    SessionCompletionRewardContent(
                        session: session,
                        userName: userName,
                        actualMinutes: actualMinutes,
                        completedAt: completedAt,
                        completionOutcome: completionOutcome,
                        onDone: { dismiss() }
                    )
                } else {
                    feedbackForm
                }
            }
            .navigationTitle(completedAt == nil ? "Session feedback" : "Growth record")
            .toolbar {
                if completedAt == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.disabled(isSubmitting)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            isSubmitting = true
                            Task {
                                let finishedAt = Date()
                                completionOutcome = await onSubmit(actualMinutes, familiarity)
                                completedAt = finishedAt
                                isSubmitting = false
                            }
                        }
                        .disabled(isSubmitting)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
        .presentationDetents([.large])
    }

    private var feedbackForm: some View {
        Form {
            Section {
                OrbSessionFeedbackHero(
                    sessionTitle: session.title,
                    actualMinutes: actualMinutes,
                    isMeasuredAutomatically: measuredActualMinutes != nil
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section("Actual time") {
                if measuredActualMinutes != nil {
                    HStack {
                        Label("Measured automatically", systemImage: "timer")
                            .font(Theme.sans(14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(actualMinutes) min")
                            .font(Theme.mono(14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text("Recorded from Start session to End session.")
                        .font(Theme.sans(12.5))
                        .foregroundStyle(Theme.muted)
                } else {
                    Stepper("\(actualMinutes) minutes", value: $actualMinutes, in: 5...360, step: 5)
                }
            }
            Section("How familiar do you feel?") {
                Picker("Familiarity", selection: $familiarity) {
                    Text("1 · No real grasp").tag(1)
                    Text("2 · Recognize it").tag(2)
                    Text("3 · Can work through it").tag(3)
                    Text("4 · I could teach it").tag(4)
                }
                .pickerStyle(.inline)
            }
            Section("Why we ask") {
                Text("Equinox uses your real pace and familiarity to make future plans more realistic. Your reward card will not include this private feedback.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

private struct OrbSessionFeedbackHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let sessionTitle: String
    let actualMinutes: Int
    let isMeasuredAutomatically: Bool

    @State private var isFloating = false
    @State private var orbitTurns = false
    @State private var sparkleTwinkle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                orbVisual

                VStack(alignment: .leading, spacing: 7) {
                    Text("Orb is here for the wrap-up")
                        .font(Theme.serif(20, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("A quick check-in helps Equinox make your next step feel realistic.")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
            }

            VStack(alignment: .leading, spacing: 8) {
                OrbFeedbackMetaRow(
                    icon: isMeasuredAutomatically ? "timer" : "clock",
                    text: isMeasuredAutomatically ? "Actual time recorded · \(actualMinutes) min" : "Actual time · \(actualMinutes) min"
                )

                OrbFeedbackMetaRow(
                    icon: "sparkles",
                    text: "Session: \(sessionTitle)"
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Theme.surface,
                            Color(hex: "F4F7FB"),
                            Color(hex: "FFF5D6").opacity(0.48)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.accentRing.opacity(0.9), lineWidth: 1)
        }
        .shadow(color: Theme.ink.opacity(0.08), radius: 18, x: 0, y: 10)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                isFloating = true
            }
            withAnimation(.linear(duration: 5.5).repeatForever(autoreverses: false)) {
                orbitTurns = true
            }
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                sparkleTwinkle = true
            }
        }
    }

    private var orbVisual: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "FFF5D6").opacity(0.94),
                            Theme.accentSoft.opacity(0.18),
                            Theme.surface.opacity(0.1)
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 62
                    )
                )
                .frame(width: 104, height: 104)
                .blur(radius: 1)

            OrbFeedbackOrbit()
                .stroke(
                    LinearGradient(
                        colors: [
                            Theme.accent.opacity(0.48),
                            Color(hex: "B8A7D9").opacity(0.52),
                            Theme.accent.opacity(0.2)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
                .frame(width: 96, height: 54)
                .rotationEffect(.degrees((orbitTurns && !reduceMotion ? 360 : 0) - 11))
                .offset(y: 9)
                .opacity(sparkleTwinkle ? 0.82 : 0.52)

            Image("OrbIdle")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .scaleEffect(isFloating ? 1.025 : 0.99)
                .offset(x: isFloating ? 2 : -2, y: isFloating ? -7 : 3)
                .rotationEffect(.degrees(isFloating ? 3.2 : -3.0))
                .shadow(color: Theme.ink.opacity(0.16), radius: 12, x: 0, y: 8)
                .shadow(color: Color(hex: "B8A7D9").opacity(0.28), radius: 10, x: 0, y: 0)

            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "FFF5D6"))
                .offset(x: 37, y: -32)
                .scaleEffect(sparkleTwinkle ? 1.22 : 0.72)
                .opacity(sparkleTwinkle ? 1 : 0.45)
                .shadow(color: Theme.accent.opacity(0.32), radius: 4)

            Image(systemName: "star.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.accentSoft)
                .offset(x: sparkleTwinkle ? -33 : -39, y: sparkleTwinkle ? 22 : 27)
                .scaleEffect(sparkleTwinkle ? 1.08 : 0.82)
                .opacity(sparkleTwinkle ? 0.95 : 0.56)
        }
        .frame(width: 104, height: 104)
        .accessibilityHidden(true)
    }
}

private struct OrbFeedbackOrbit: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: rect)
        return path
    }
}

private struct OrbFeedbackMetaRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 14, height: 14)
                .padding(.top, 1)

            Text(text)
                .font(Theme.mono(10.5, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .kerning(0.45)
                .textCase(.uppercase)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.surface.opacity(0.72))
        .clipShape(.rect(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(Theme.line.opacity(0.85), lineWidth: 1)
        }
    }
}
