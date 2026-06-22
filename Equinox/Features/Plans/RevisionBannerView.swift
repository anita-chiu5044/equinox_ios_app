import SwiftUI

struct RevisionBannerView: View {
    let revision: PlanRevisionDTO
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.amberText)

                VStack(alignment: .leading, spacing: 2) {
                    Text(revision.status == "awaiting_generation" ? "Plan revision ready to generate" : "Plan revision needs review")
                        .font(Theme.sans(13, weight: .semibold))
                        .foregroundStyle(Theme.amberText)
                    Text(triggerLabel)
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.amberText.opacity(0.8))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.amberText.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.prioMed.opacity(0.12))
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.prioMed.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var triggerLabel: String {
        switch revision.trigger {
        case "energy_high_difficulty": return "Low energy + demanding sessions ahead"
        case "slow_sessions": return "Sessions taking longer than planned"
        case "overdue": return "Multiple sessions overdue"
        case "low_familiarity": return "Material needs a different approach"
        case "deadline_infeasible": return "Remaining work won't fit before deadline"
        case "manual": return "Manually requested"
        default: return revision.triggerDetail.isEmpty ? "Review suggested" : revision.triggerDetail
        }
    }
}
