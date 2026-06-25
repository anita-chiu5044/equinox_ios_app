import SwiftUI

struct EggStatusPill: View {
    let growth: GrowthCycleDTO
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                OrbitEggView(
                    progress: growth.progress,
                    targetProgress: growth.targetProgress,
                    isHatched: growth.isHatched
                )
                .frame(width: 34, height: 42)

                VStack(alignment: .leading, spacing: 1) {
                    Text(growth.isHatched ? "Orb hatched" : growth.progressText)
                        .font(Theme.mono(10.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(growth.goalTitle)
                        .font(Theme.sans(10.5))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.surface2.opacity(0.92))
            .clipShape(.capsule)
            .overlay(
                Capsule()
                    .strokeBorder(Theme.accentRing, lineWidth: 1)
            )
            .shadow(color: Theme.shadowInk.opacity(0.08), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Growth progress \(growth.progressText), goal \(growth.goalTitle)")
    }
}

struct GrowthCompanionCard: View {
    let growth: GrowthCycleDTO?
    let nextSession: SessionDTO?
    let isActiveSessionRunning: Bool
    let isLowEnergy: Bool
    let rewardPoints: Int
    let action: () -> Void

    @AppStorage("growthReduceMotion") private var reduceMotion = false
    @State private var glow = false
    @State private var glideWobble = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .center, spacing: 14) {
                    companionImage
                        .frame(width: 78, height: 78)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(title)
                                .font(Theme.sans(15, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)

                            if let growth {
                                Text(growth.progressText)
                                    .font(Theme.mono(10.5, weight: .semibold))
                                    .foregroundStyle(growth.isHatched ? Theme.prioLow : Theme.accent)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background((growth.isHatched ? Theme.prioLow : Theme.accent).opacity(0.12))
                                    .clipShape(.capsule)
                            }
                        }

                        Text(message)
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)

                        if rewardPoints > 0 {
                            Label("Glow +\(rewardPoints)", systemImage: "sparkles")
                                .font(Theme.mono(11, weight: .semibold))
                                .foregroundStyle(Theme.prioMed)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color(hex: "FFF5D6").opacity(0.82))
                                .clipShape(.capsule)
                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.faint)
                }

                if let nextStepText {
                    HStack(spacing: 8) {
                        Image(systemName: growth == nil ? "plus.circle.fill" : "arrow.forward.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text(nextStepText)
                            .font(Theme.sans(12.5, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Theme.surface2.opacity(0.78))
                    .clipShape(.rect(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(cardBackground)
            .clipShape(.rect(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(
                        rewardPoints > 0 ? Theme.prioMed.opacity(0.35) : Theme.accentRing,
                        lineWidth: rewardPoints > 0 ? 1.4 : 1
                    )
            }
            .shadow(
                color: rewardPoints > 0 ? Theme.prioMed.opacity(0.18) : Theme.shadowInk.opacity(0.08),
                radius: rewardPoints > 0 ? 22 : 16,
                y: rewardPoints > 0 ? 9 : 6
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
        .onChange(of: companionVisualState, initial: false) { _, state in
            guard !reduceMotion, state == .glide else { return }
            glideWobble.toggle()
        }
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.78), value: rewardPoints)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.76), value: companionVisualState)
    }

    @ViewBuilder
    private var companionImage: some View {
        ZStack {
            Circle()
                .fill(activeGlowColor)
                .frame(width: rewardPoints > 0 || isActiveSessionRunning ? 74 : 58, height: rewardPoints > 0 || isActiveSessionRunning ? 74 : 58)
                .blur(radius: rewardPoints > 0 ? 5 : 2)
                .opacity(reduceMotion ? 0.85 : glow ? 0.95 : 0.55)

            if companionVisualState == .glide && !reduceMotion {
                StardustTrail()
                    .frame(width: 82, height: 52)
                    .offset(x: glideWobble ? -5 : -11, y: 3)
                    .opacity(glideWobble ? 0.68 : 0.35)
                    .animation(.easeInOut(duration: 0.22).repeatCount(5, autoreverses: true), value: glideWobble)
            }

            companionVisual
                .id(companionVisualState)
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .scale(scale: 0.88))
                            .combined(with: .offset(x: companionVisualState == .glide ? -8 : 0, y: 4)),
                        removal: .opacity
                            .combined(with: .scale(scale: 1.08))
                    )
                )
                .offset(x: companionVisualState == .glide && !reduceMotion ? (glideWobble ? 3 : -3) : 0,
                        y: companionVisualState == .glide && !reduceMotion ? (glideWobble ? -1 : 1) : 0)
                .rotationEffect(.degrees(companionVisualState == .glide && !reduceMotion ? (glideWobble ? 2.6 : -2.2) : 0))
                .animation(
                    companionVisualState == .glide && !reduceMotion
                    ? .easeInOut(duration: 0.18).repeatCount(5, autoreverses: true)
                    : nil,
                    value: glideWobble
                )
        }
    }

    @ViewBuilder
    private var companionVisual: some View {
        switch companionVisualState {
        case .collectStar:
            Image("OrbCollectStar")
                .resizable()
                .scaledToFit()
                .frame(width: 76, height: 76)
        case .glide:
            Image("OrbGlide")
                .resizable()
                .scaledToFit()
                .frame(width: 78, height: 78)
        case .egg:
            if let growth {
                OrbitEggView(
                    progress: growth.progress,
                    targetProgress: growth.targetProgress,
                    isHatched: false
                )
                .frame(width: 48, height: 62)
            }
        case .idle:
            Image("OrbIdle")
                .resizable()
                .scaledToFit()
                .frame(width: growth?.isHatched == true ? 76 : 66, height: growth?.isHatched == true ? 76 : 66)
                .opacity(growth == nil ? 0.82 : 1)
        }
    }

    private var companionVisualState: OrbCompanionVisualState {
        if rewardPoints > 0 {
            return .collectStar
        }
        if isActiveSessionRunning {
            return .glide
        }
        if let growth, !growth.isHatched {
            return .egg
        }
        return .idle
    }

    private var title: String {
        guard let growth else {
            return "Orb is waiting for a goal"
        }
        return growth.isHatched ? "Orb hatched" : growth.goalTitle
    }

    private var message: String {
        if growth == nil {
            return "Create a learning goal, and Orb will appear here to keep you company."
        }
        if rewardPoints > 0 {
            return "That step just made it into orbit."
        }
        if growth?.isHatched == true {
            return "Your steady steps have hatched Orb."
        }
        if isActiveSessionRunning {
            return "Orb is moving through this orbit with you."
        }
        if isLowEnergy {
            return "Scaling down still counts. Rest and adjustment are not failure."
        }
        return "Light up one small step today."
    }

    private var nextStepText: String? {
        if growth == nil {
            return "Next step: create a goal in Plans"
        }
        if let nextSession {
            return "Next step: \(nextSession.title) · \(nextSession.minutes) min"
        }
        if let next = growth?.nextSession {
            return "Next step: \(next.title) · \(next.minutes) min"
        }
        if growth?.isHatched == true {
            return "Open the nest and keep this growth record"
        }
        return "Complete the next session and Orb will glow."
    }

    private var activeGlowColor: Color {
        if rewardPoints > 0 {
            return Color(hex: "FFF5D6")
        }
        if isActiveSessionRunning {
            return Color(hex: "B8A7D9").opacity(0.22)
        }
        return Theme.accentWash
    }

    private var cardBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Theme.surface2,
                Color(hex: "fff8eb"),
                Theme.surface,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var accessibilityText: String {
        if let growth {
            return "Growth companion card, \(growth.goalTitle), \(growth.progressText). \(message)"
        }
        return "Growth companion card. Create a learning goal to begin hatching."
    }
}

private enum OrbCompanionVisualState: Equatable {
    case idle
    case egg
    case glide
    case collectStar
}

private struct StardustTrail: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "B8A7D9").opacity(0.00),
                            Color(hex: "B8A7D9").opacity(0.34),
                            Color(hex: "FFE1C2").opacity(0.00),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 58, height: 9)
                .rotationEffect(.degrees(-12))
                .blur(radius: 2)

            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(index.isMultiple(of: 2) ? Color(hex: "FFF5D6") : Color(hex: "B8A7D9"))
                    .frame(width: index.isMultiple(of: 2) ? 5 : 3, height: index.isMultiple(of: 2) ? 5 : 3)
                    .offset(
                        x: CGFloat(index * 11 - 28),
                        y: CGFloat(index.isMultiple(of: 2) ? -5 : 4)
                    )
                    .opacity(0.78)
            }
        }
        .accessibilityHidden(true)
    }
}

struct NestSheet: View {
    let growth: GrowthCycleDTO

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Theme.accentWash)
                                .frame(width: 148, height: 148)
                                .blur(radius: 4)

                            if growth.isHatched {
                                Image("OrbCollectStar")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 150, height: 150)
                                    .shadow(color: Theme.shadowInk.opacity(0.16), radius: 16, y: 8)
                            } else {
                                OrbitEggView(
                                    progress: growth.progress,
                                    targetProgress: growth.targetProgress,
                                    isHatched: false
                                )
                                .frame(width: 110, height: 136)
                            }
                        }

                        VStack(spacing: 5) {
                            Text("Orbit Nest")
                                .font(Theme.serif(28, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(growth.goalTitle)
                                .font(Theme.sans(14, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 18)

                    progressCard
                    recentActionsCard
                    nextStepCard
                    philosophyNote
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var progressCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(growth.isHatched ? "Hatched" : "Glow progress", systemImage: growth.isHatched ? "sparkles" : "sun.max.fill")
                        .font(Theme.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text(growth.progressText)
                        .font(Theme.mono(12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }

                ProgressView(value: Double(growth.progress), total: Double(growth.targetProgress))
                    .tint(Theme.accent)

                Text(growth.isHatched
                     ? "Your steady steps have hatched Orb."
                     : "Each completed learning session adds 1 glow. Delays and rest never subtract progress; they only pause hatching.")
                    .font(Theme.sans(12.5))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var recentActionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent glow-giving actions")
                    .font(Theme.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                if growth.recentContributions.isEmpty {
                    Text("No glow yet. Complete the next session and Orb will light up.")
                        .font(Theme.sans(12.5))
                        .foregroundStyle(Theme.muted)
                } else {
                    ForEach(growth.recentContributions) { contribution in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: contribution.sourceKind == "adapted_session_complete" ? "leaf.fill" : "star.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(contribution.sourceKind == "adapted_session_complete" ? Theme.prioLow : Theme.prioMed)
                                .frame(width: 18, height: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(contribution.displayTitle)
                                    .font(Theme.sans(12.5, weight: .semibold))
                                    .foregroundStyle(Theme.inkSoft)
                                    .lineLimit(2)
                                Text("\(contribution.displayKind) · +\(contribution.points) glow")
                                    .font(Theme.mono(10.5))
                                    .foregroundStyle(Theme.muted)
                            }

                            Spacer()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var nextStepCard: some View {
        if let next = growth.nextSession, !growth.isHatched {
            Card {
                HStack(spacing: 12) {
                    Image("OrbGlide")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next doable step")
                            .font(Theme.sans(13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(next.title)
                            .font(Theme.sans(12.5))
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(2)
                        Text("\(next.minutes) min")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                }
            }
        }
    }

    private var philosophyNote: some View {
        Text("This is not a streak, and Orb is not a pet to feed. It is a quiet reminder that a big goal is becoming a doable path.")
            .font(Theme.serif(14).italic())
            .foregroundStyle(Theme.inkSoft)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.bottom, 20)
    }
}

struct GrowthRewardBanner: View {
    let reward: GrowthReward

    var body: some View {
        HStack(spacing: 12) {
            Image("OrbCollectStar")
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text(reward.didHatch ? "Orb hatched" : "Glow +\(reward.points)")
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(reward.didHatch
                     ? "You turned this goal into 5 doable actions."
                     : "One doable step completed. Orb gained another star.")
                    .font(Theme.sans(12.5))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(Theme.surface2)
        .clipShape(.rect(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Theme.accentRing, lineWidth: 1)
        )
        .shadowE1()
    }
}

struct HatchCelebrationOverlay: View {
    @Binding var isPresented: Bool
    @AppStorage("growthReduceMotion") private var reduceMotion = false

    var body: some View {
        ZStack {
            Theme.paper.opacity(0.94)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Theme.accentWash)
                        .frame(width: 230, height: 230)
                        .blur(radius: 16)

                    Image("OrbCollectStar")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 190, height: 190)
                        .scaleEffect(reduceMotion ? 1 : 1.04)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: reduceMotion)
                }

                VStack(spacing: 6) {
                    Text("Orb hatched")
                        .font(Theme.serif(31, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Not because you were perfect, but because you kept returning to the next doable step.")
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }

                Button("Keep this growth record") {
                    withAnimation(.easeOut(duration: 0.22)) {
                        isPresented = false
                    }
                }
                .font(Theme.sans(15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Theme.accent)
                .clipShape(.capsule)
                .shadowE3()
            }
            .padding(28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

struct OrbitEggView: View {
    let progress: Int
    let targetProgress: Int
    let isHatched: Bool

    private var progressRatio: CGFloat {
        guard targetProgress > 0 else { return 0 }
        return min(1, CGFloat(progress) / CGFloat(targetProgress))
    }

    var body: some View {
        ZStack {
            if isHatched {
                Image("OrbIdle")
                    .resizable()
                    .scaledToFit()
            } else {
                eggBody
                orbit
                glowFill
                cracksAndStars
            }
        }
    }

    private var eggBody: some View {
        EggShape()
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "fff8eb"),
                        Color(hex: "f2dfca"),
                        Color(hex: "d9c0a6"),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                EggShape()
                    .strokeBorder(Theme.accent.opacity(0.18), lineWidth: 1.2)
            )
            .shadow(color: Theme.shadowInk.opacity(0.12), radius: 7, y: 4)
    }

    private var glowFill: some View {
        EggShape()
            .fill(
                LinearGradient(
                    colors: [
                        Theme.accent.opacity(0.28),
                        Color(hex: "fff5d6").opacity(0.76),
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .mask(
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle()
                        .frame(height: max(3, 92 * progressRatio))
                }
            )
            .opacity(0.92)
    }

    private var orbit: some View {
        Ellipse()
            .stroke(
                LinearGradient(
                    colors: [
                        Theme.accent.opacity(0.65),
                        Color(hex: "B8A7D9").opacity(0.78),
                        Color(hex: "FFE1C2").opacity(0.7),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 2
            )
            .frame(width: 64, height: 18)
            .rotationEffect(.degrees(-17))
            .offset(y: 7)
            .shadow(color: Color(hex: "B8A7D9").opacity(0.3), radius: 4)
    }

    private var cracksAndStars: some View {
        ZStack {
            ForEach(0..<min(progress, 5), id: \.self) { index in
                GrowthSparkleShape()
                    .fill(index.isMultiple(of: 2) ? Color(hex: "FFF5D6") : Color(hex: "B8A7D9"))
                    .frame(width: 5 + CGFloat(index % 2) * 2, height: 5 + CGFloat(index % 2) * 2)
                    .offset(starOffset(index))
            }

            if progress >= 3 {
                Path { path in
                    path.move(to: CGPoint(x: 25, y: 22))
                    path.addLine(to: CGPoint(x: 31, y: 31))
                    path.addLine(to: CGPoint(x: 27, y: 38))
                    path.addLine(to: CGPoint(x: 34, y: 47))
                }
                .stroke(Theme.accent.opacity(0.35), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func starOffset(_ index: Int) -> CGSize {
        let positions: [CGSize] = [
            CGSize(width: -9, height: 7),
            CGSize(width: 10, height: -5),
            CGSize(width: 4, height: 15),
            CGSize(width: -3, height: -16),
            CGSize(width: 15, height: 10),
        ]
        return positions[index % positions.count]
    }
}

private struct EggShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let w = rect.width
        let h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }

        var path = Path()
        path.move(to: p(0.50, 0.03))
        path.addCurve(to: p(0.88, 0.36), control1: p(0.70, 0.06), control2: p(0.84, 0.18))
        path.addCurve(to: p(0.78, 0.88), control1: p(0.96, 0.63), control2: p(0.92, 0.82))
        path.addCurve(to: p(0.50, 0.98), control1: p(0.68, 0.97), control2: p(0.58, 1.00))
        path.addCurve(to: p(0.22, 0.88), control1: p(0.42, 1.00), control2: p(0.32, 0.97))
        path.addCurve(to: p(0.12, 0.36), control1: p(0.08, 0.82), control2: p(0.04, 0.63))
        path.addCurve(to: p(0.50, 0.03), control1: p(0.16, 0.18), control2: p(0.30, 0.06))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct GrowthSparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: center.y), control: CGPoint(x: center.x + rect.width * 0.10, y: center.y - rect.height * 0.10))
        path.addQuadCurve(to: CGPoint(x: center.x, y: rect.maxY), control: CGPoint(x: center.x + rect.width * 0.10, y: center.y + rect.height * 0.10))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: center.y), control: CGPoint(x: center.x - rect.width * 0.10, y: center.y + rect.height * 0.10))
        path.addQuadCurve(to: CGPoint(x: center.x, y: rect.minY), control: CGPoint(x: center.x - rect.width * 0.10, y: center.y - rect.height * 0.10))
        return path
    }
}
