import SwiftUI

/// Step 2 — progress animation while the goal is decomposed into sessions.
struct ThinkingStepView: View {
    @ObservedObject var viewModel: CreateGoalFlowViewModel
    @State private var phase = 0.0

    var body: some View {
        VStack(spacing: 26) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(Theme.faint.opacity(0.4), lineWidth: 3)
                    .frame(width: 110, height: 110)

                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(phase))

                Image(systemName: "sparkles")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Drafting your plan")
                    .font(Theme.serif(26, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                Text(viewModel.thinkingDetail)
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .animation(.default, value: viewModel.thinkingDetail)
            }

            if OnDevicePlanner.isAvailable {
                Label("Planned on-device with Apple Intelligence", systemImage: "lock.shield")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.muted)
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 360
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drafting your plan. \(viewModel.thinkingDetail)")
    }
}
