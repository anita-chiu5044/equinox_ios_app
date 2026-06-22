import SwiftUI

struct PriorityPill: View {
    let priority: String

    var body: some View {
        Text(priority.uppercased())
            .font(Theme.mono(11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.priorityColor(priority))
            .clipShape(.capsule)
    }
}
