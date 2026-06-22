import SwiftUI

struct OnboardingConnectView: View {
    var onDone: () -> Void

    @StateObject private var settingsVM = SettingsViewModel()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 64)

                    // Orbital ambient (smaller)
                    OrbitAmbient()
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .scaleEffect(0.7)
                        .accessibilityHidden(true)

                    // Headline + badge row
                    HStack(alignment: .center, spacing: 12) {
                        Text("Connect your\ncalendar")
                            .font(Theme.serif(38))
                            .foregroundStyle(Theme.ink)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()

                        Text("Optional")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.bgWarm)
                            .overlay(
                                Capsule()
                                    .strokeBorder(Theme.faint.opacity(0.7), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                    .padding(.top, 24)

                    // Feature rows
                    VStack(spacing: 16) {
                        FeatureRow(
                            icon: "calendar.badge.checkmark",
                            title: "Schedule around real life",
                            description: "Equinox sees your existing events and plans around them — no more double-booking."
                        )
                        FeatureRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Two-way sync",
                            description: "Tasks become calendar events. Changes flow both ways automatically."
                        )
                    }
                    .padding(.top, 28)

                    // Connect Google Calendar button
                    Button {
                        Task {
                            do {
                                await settingsVM.setGoogleCalendarConnected(true)
                            }
                            onDone()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            GoogleGlyph(size: 22)
                            Text("Connect Google Calendar")
                                .font(Theme.sans(16, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                    }
                    .buttonStyle(.plain)
                    .background(Theme.surface)
                    .clipShape(.rect(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Theme.faint.opacity(0.6), lineWidth: 1)
                    )
                    .shadow(color: Theme.ink.opacity(0.07), radius: 8, x: 0, y: 3)
                    .padding(.top, 32)

                    // Maybe later
                    Button {
                        onDone()
                    } label: {
                        Text("Maybe later")
                            .font(Theme.sans(15))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)

                    // Fine print
                    Text("Equinox only reads event times and titles. We never store or share your calendar data.")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.faint)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                        .padding(.bottom, 44)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon tile
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.accentWash)
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(description)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    OnboardingConnectView(onDone: {})
        .environmentObject(AppState())
}
