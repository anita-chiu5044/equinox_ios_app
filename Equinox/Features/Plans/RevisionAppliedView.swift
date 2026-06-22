import SwiftUI

struct RevisionAppliedView: View {
    let revision: PlanRevisionDTO
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Theme.accentWash)
                    .frame(width: 72, height: 72)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.accent)
            }

            VStack(spacing: 8) {
                Text("Plan updated")
                    .font(Theme.serif(28))
                    .foregroundStyle(Theme.ink)
                Text("Your schedule has been revised and rescheduled based on the new plan.")
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            if let diff = revision.diff {
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text("\(diff.totalAfter)")
                            .font(Theme.serif(28, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text("sessions")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.muted)
                    }
                    VStack(spacing: 4) {
                        Text("\(diff.minutesAfter / 60)h \(diff.minutesAfter % 60)m")
                            .font(Theme.serif(28, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text("total")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(20)
                .background(Theme.surface)
                .clipShape(.rect(cornerRadius: 16))
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Text("Back to Plans")
                    .font(Theme.sans(16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Theme.accent)
            .clipShape(.rect(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.bottom, 44)
        }
        .background(Theme.paper)
    }
}
