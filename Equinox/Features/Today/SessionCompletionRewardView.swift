import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct SessionCompletionRewardContent: View {
    let session: SessionDTO
    let userName: String?
    let actualMinutes: Int
    let completedAt: Date
    var completionOutcome: SessionCompletionOutcome? = nil
    let onDone: () -> Void

    @State private var shareURL: URL?
    @State private var isPreparingShareImage = false
    @State private var shareError: String?
    @State private var showHatchCelebration = false

    private var growthReward: GrowthReward? {
        completionOutcome?.growthReward
    }

    private var planCompletion: PlanCompletionReward? {
        completionOutcome?.planCompletion
    }

    private var displayName: String {
        let trimmed = (userName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "You" : trimmed
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text(planCompletion == nil ? "Star collected" : "Plan completed")
                        .font(Theme.serif(28, weight: .semibold))
                        .foregroundStyle(Theme.ink)

                    Text(planCompletion == nil
                         ? "Orb gathered stardust from this session."
                         : "Orb saved this completed plan into your orbit.")
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 18)

                if let growthReward {
                    GrowthRewardBanner(reward: growthReward)
                        .padding(.horizontal, 2)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let planCompletion {
                    SessionCompletionRecordCard(
                        sessionTitle: planCompletion.goalTitle,
                        userName: displayName,
                        actualMinutes: planCompletion.completedMinutes,
                        completedAt: completedAt,
                        completedLine: "\(displayName) completed the plan",
                        metricText: "\(planCompletion.completedSessionCount) SESSIONS · \(planCompletion.completedMinutes) MIN · \(completedAt.formatted(.dateTime.year().month(.abbreviated).day()).uppercased())",
                        reflectionText: "You turned a big plan into finished steps, one orbit at a time.",
                        certificateTitle: "PLAN CERTIFICATE"
                    )
                    .frame(width: SessionCompletionRecordCard.defaultSize.width,
                           height: SessionCompletionRecordCard.defaultSize.height)
                    .shadow(color: OrbPalette.midnight.opacity(0.16), radius: 22, x: 0, y: 14)
                    .padding(.vertical, 4)
                } else {
                    sessionStarCollectedCard
                        .padding(.vertical, 4)
                }

                VStack(spacing: 8) {
                    if planCompletion != nil {
                        shareAction
                    }

                    Button {
                        onDone()
                    } label: {
                        Text("Done")
                            .font(Theme.sans(15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.ink)
                    .background(Theme.surface2)
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Theme.line, lineWidth: 1)
                    )
                }

                VStack(spacing: 4) {
                    if planCompletion == nil {
                        Text("Session completions collect stardust for Orb.")
                        Text("A shareable card appears when the whole plan is complete.")
                    } else {
                        Text("The share card only includes name, plan title, date, sessions, and completed minutes.")
                        Text("Familiarity and energy status will not appear on the card.")
                    }
                }
                .font(Theme.sans(11.5))
                .foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 20)
        }
        .background(Theme.paper)
        .overlay {
            if showHatchCelebration {
                HatchCelebrationOverlay(isPresented: $showHatchCelebration)
            }
        }
        .onAppear {
            if growthReward?.didHatch == true {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    showHatchCelebration = true
                }
            }
        }
    }

    private var sessionStarCollectedCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: "FFF5D6"))
                    .frame(width: 150, height: 150)
                    .blur(radius: 12)

                Image("OrbCollectStar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 138, height: 138)
                    .shadow(color: OrbPalette.midnight.opacity(0.14), radius: 14, x: 0, y: 8)
            }

            VStack(spacing: 6) {
                Text(growthReward.map { "Glow +\($0.points)" } ?? "Session completed")
                    .font(Theme.sans(18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("\(session.title) added stardust to Orb. Keep going — the plan card unlocks when every session is complete.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(22)
        .background(Theme.surface2)
        .clipShape(.rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Theme.accentRing, lineWidth: 1)
        }
        .shadowE1()
    }

    @ViewBuilder
    private var shareAction: some View {
        if let shareURL {
            ShareLink(
                item: shareURL,
                preview: SharePreview("Equinox Growth Record")
            ) {
                Label("Share card", systemImage: "square.and.arrow.up")
                    .font(Theme.sans(15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Theme.accent)
            .clipShape(.rect(cornerRadius: 14))
            .shadowE3()
        } else {
            Button {
                Task {
                    await prepareShareImage()
                }
            } label: {
                HStack(spacing: 8) {
                    if isPreparingShareImage {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(isPreparingShareImage ? "Preparing card…" : "Prepare share card")
                }
                .font(Theme.sans(15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Theme.accent)
            .clipShape(.rect(cornerRadius: 14))
            .shadowE3()
            .disabled(isPreparingShareImage)

            if let shareError {
                Text(shareError)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.amberText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @MainActor
    private func prepareShareImage() async {
        guard shareURL == nil, !isPreparingShareImage else {
            return
        }

        isPreparingShareImage = true
        shareError = nil
        defer { isPreparingShareImage = false }

        do {
            shareURL = try renderShareImage()
        } catch {
            shareError = "You can screenshot the card for now; the share image could not be prepared."
        }
    }

    @MainActor
    private func renderShareImage() throws -> URL {
        let content = SessionCompletionRecordCard(
            sessionTitle: planCompletion?.goalTitle ?? session.title,
            userName: displayName,
            actualMinutes: planCompletion?.completedMinutes ?? actualMinutes,
            completedAt: completedAt,
            completedLine: planCompletion == nil ? "\(displayName) completed" : "\(displayName) completed the plan",
            metricText: planCompletion.map {
                "\($0.completedSessionCount) SESSIONS · \($0.completedMinutes) MIN · \(completedAt.formatted(.dateTime.year().month(.abbreviated).day()).uppercased())"
            },
            reflectionText: planCompletion == nil
                ? "Today was not about catching up. It was about putting the next step into orbit."
                : "You turned a big plan into finished steps, one orbit at a time.",
            certificateTitle: planCompletion == nil ? "SESSION CERTIFICATE" : "PLAN CERTIFICATE"
        )
        .frame(width: SessionCompletionRecordCard.defaultSize.width,
               height: SessionCompletionRecordCard.defaultSize.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3

        #if canImport(UIKit)
        guard let image = renderer.uiImage, let data = image.pngData() else {
            throw ShareRenderError.failed
        }
        #elseif canImport(AppKit)
        guard
            let image = renderer.nsImage,
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let data = bitmap.representation(using: .png, properties: [:])
        else {
            throw ShareRenderError.failed
        }
        #else
        throw ShareRenderError.failed
        #endif

        let fileName = "Equinox-\(safeFileStem(from: planCompletion?.goalTitle ?? session.title))-growth-record.png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func safeFileStem(from title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = title.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let stem = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return stem.isEmpty ? "session" : stem
    }
}

struct SessionCompletionRecordCard: View {
    static let defaultSize = CGSize(width: 326, height: 435)

    let sessionTitle: String
    let userName: String
    let actualMinutes: Int
    let completedAt: Date
    var completedLine: String? = nil
    var metricText: String? = nil
    var reflectionText: String = "Today was not about catching up. It was about putting the next step into orbit."
    var certificateTitle: String = "SESSION CERTIFICATE"

    private var dateText: String {
        completedAt.formatted(.dateTime.year().month(.abbreviated).day())
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            OrbPalette.mist,
                            Theme.surface2,
                            OrbPalette.cream,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            cardGlow
            decorativeSparkles

            VStack(alignment: .leading, spacing: 0) {
                cardHeader

                Spacer(minLength: 18)

                VStack(alignment: .leading, spacing: 10) {
                    Text(completedLine ?? "\(userName) completed")
                        .font(Theme.sans(15, weight: .semibold))
                        .foregroundStyle(OrbPalette.slate)

                    Text(sessionTitle)
                        .font(Theme.serif(31, weight: .semibold))
                        .foregroundStyle(OrbPalette.midnight)
                        .lineLimit(3)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(metricText ?? "\(actualMinutes) MIN · \(dateText.uppercased())")
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(OrbPalette.indigo)
                        .kerning(1.1)
                }
                .frame(maxWidth: 214, alignment: .leading)

                Spacer(minLength: 14)

                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(reflectionText)
                            .font(Theme.serif(16).italic())
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(certificateTitle)
                            .font(Theme.mono(10, weight: .semibold))
                            .foregroundStyle(Theme.faint)
                            .kerning(1.2)
                    }

                    Spacer(minLength: 4)

                    OrbIdleMascotImage(size: 142)
                        .offset(x: 8, y: 8)
                        .accessibilityHidden(true)
                }
            }
            .padding(24)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            OrbPalette.lavender.opacity(0.66),
                            OrbPalette.peach.opacity(0.66),
                            OrbPalette.indigo.opacity(0.22),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        }
        .clipShape(.rect(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(userName) completed \(sessionTitle), \(actualMinutes) minutes, \(dateText)")
    }

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("EQUINOX")
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(OrbPalette.midnight)
                    .kerning(1.4)

                Text("Growth Record")
                    .font(Theme.sans(12, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }

            Spacer()

            Text("ORB")
                .font(Theme.mono(10, weight: .semibold))
                .foregroundStyle(OrbPalette.indigo)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.62))
                .clipShape(.capsule)
                .overlay(
                    Capsule()
                        .strokeBorder(OrbPalette.lavender.opacity(0.5), lineWidth: 1)
                )
        }
    }

    private var cardGlow: some View {
        ZStack {
            Circle()
                .fill(OrbPalette.lavender.opacity(0.26))
                .blur(radius: 24)
                .frame(width: 188, height: 188)
                .offset(x: 116, y: -142)

            Circle()
                .fill(OrbPalette.peach.opacity(0.34))
                .blur(radius: 28)
                .frame(width: 166, height: 166)
                .offset(x: -130, y: 150)

            Ellipse()
                .stroke(OrbPalette.lavender.opacity(0.22), lineWidth: 1)
                .frame(width: 250, height: 72)
                .rotationEffect(.degrees(-18))
                .offset(x: 88, y: -96)
        }
    }

    private var decorativeSparkles: some View {
        ZStack {
            ForEach(0..<OrbDecoration.cardSparkles.count, id: \.self) { index in
                let sparkle = OrbDecoration.cardSparkles[index]
                SparkleShape()
                    .fill(sparkle.color.opacity(sparkle.opacity))
                    .frame(width: sparkle.size, height: sparkle.size)
                    .offset(x: sparkle.x, y: sparkle.y)
            }

            ForEach(0..<OrbDecoration.cardDots.count, id: \.self) { index in
                let dot = OrbDecoration.cardDots[index]
                Circle()
                    .fill(dot.color.opacity(dot.opacity))
                    .frame(width: dot.size, height: dot.size)
                    .offset(x: dot.x, y: dot.y)
            }
        }
    }
}

private struct OrbIdleMascotImage: View {
    let size: CGFloat

    var body: some View {
        Image("OrbIdle")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: OrbPalette.midnight.opacity(0.18), radius: 12, x: 0, y: 8)
            .shadow(color: OrbPalette.lavender.opacity(0.18), radius: 9, x: 0, y: 0)
    }
}

struct OrbMascotView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            ambientGlow
            orbitBack
            furHalo
            mascotBody
            curl
            face
            paws
            feet
            orbitFront
        }
        .frame(width: size * 1.48, height: size * 1.40)
    }

    private var ambientGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        OrbPalette.lavender.opacity(0.36),
                        OrbPalette.peach.opacity(0.14),
                        .clear,
                    ],
                    center: .center,
                    startRadius: size * 0.08,
                    endRadius: size * 0.86
                )
            )
            .frame(width: size * 1.55, height: size * 1.38)
            .blur(radius: size * 0.08)
            .offset(y: size * 0.04)
    }

    private var furHalo: some View {
        ZStack {
            ForEach(0..<OrbDecoration.furRim.count, id: \.self) { index in
                let fur = OrbDecoration.furRim[index]
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                fur.color.opacity(fur.opacity),
                                fur.color.opacity(fur.opacity * 0.30),
                                .clear,
                            ],
                            center: .center,
                            startRadius: size * fur.size * 0.14,
                            endRadius: size * fur.size * 0.56
                        )
                    )
                    .frame(width: size * fur.size, height: size * fur.size)
                    .offset(x: size * fur.x, y: size * fur.y)
            }
        }
        .offset(y: size * 0.06)
    }

    private var mascotBody: some View {
        ZStack {
            OrbMascotBodyShape()
                .fill(
                    RadialGradient(
                        colors: [
                            OrbPalette.silver.opacity(0.74),
                            OrbPalette.indigo.opacity(0.92),
                            OrbPalette.midnight,
                        ],
                        center: UnitPoint(x: 0.50, y: 0.92),
                        startRadius: size * 0.10,
                        endRadius: size * 0.74
                    )
                )
                .overlay(
                    OrbMascotBodyShape()
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1.1)
                )
                .shadow(color: OrbPalette.midnight.opacity(0.26), radius: 12, x: 0, y: 7)

            OrbMascotBodyShape()
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.30),
                            OrbPalette.silver.opacity(0.12),
                            .clear,
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .mask(
                    Ellipse()
                        .frame(width: size * 0.78, height: size * 0.60)
                        .offset(y: size * 0.28)
                )

            mascotSparkles
        }
        .frame(width: size * 1.04, height: size * 1.08)
        .offset(y: size * 0.05)
    }

    private var curl: some View {
        Path { path in
            path.move(to: CGPoint(x: size * 0.51, y: size * 0.24))
            path.addCurve(
                to: CGPoint(x: size * 0.64, y: size * 0.00),
                control1: CGPoint(x: size * 0.66, y: size * 0.16),
                control2: CGPoint(x: size * 0.76, y: size * 0.05)
            )
            path.addCurve(
                to: CGPoint(x: size * 0.47, y: size * 0.01),
                control1: CGPoint(x: size * 0.56, y: size * -0.06),
                control2: CGPoint(x: size * 0.43, y: size * -0.03)
            )
        }
        .stroke(
            LinearGradient(
                colors: [
                    OrbPalette.midnight,
                    OrbPalette.indigo,
                    OrbPalette.lavender,
                ],
                startPoint: .bottom,
                endPoint: .top
            ),
            style: StrokeStyle(lineWidth: size * 0.115, lineCap: .round, lineJoin: .round)
        )
        .overlay(
            Path { path in
                path.move(to: CGPoint(x: size * 0.51, y: size * 0.24))
                path.addCurve(
                    to: CGPoint(x: size * 0.64, y: size * 0.00),
                    control1: CGPoint(x: size * 0.66, y: size * 0.16),
                    control2: CGPoint(x: size * 0.76, y: size * 0.05)
                )
                path.addCurve(
                    to: CGPoint(x: size * 0.47, y: size * 0.01),
                    control1: CGPoint(x: size * 0.56, y: size * -0.06),
                    control2: CGPoint(x: size * 0.43, y: size * -0.03)
                )
            }
            .stroke(.white.opacity(0.16), style: StrokeStyle(lineWidth: size * 0.038, lineCap: .round, lineJoin: .round))
        )
        .shadow(color: OrbPalette.lavender.opacity(0.42), radius: 7, x: 0, y: 0)
        .frame(width: size, height: size)
        .offset(x: size * -0.03, y: size * -0.22)
    }

    private var face: some View {
        ZStack {
            OrbEye(size: size * 0.215)
                .offset(x: size * -0.19, y: size * -0.04)
            OrbEye(size: size * 0.215)
                .offset(x: size * 0.19, y: size * -0.04)

            Circle()
                .fill(OrbPalette.blush.opacity(0.82))
                .frame(width: size * 0.17, height: size * 0.08)
                .blur(radius: 2.4)
                .offset(x: size * -0.33, y: size * 0.12)

            Circle()
                .fill(OrbPalette.blush.opacity(0.82))
                .frame(width: size * 0.17, height: size * 0.08)
                .blur(radius: 2.4)
                .offset(x: size * 0.33, y: size * 0.12)

            Capsule()
                .fill(OrbPalette.midnight.opacity(0.82))
                .frame(width: size * 0.055, height: size * 0.035)
                .offset(y: size * 0.095)

            Path { path in
                path.move(to: CGPoint(x: size * 0.50, y: size * 0.50))
                path.addQuadCurve(
                    to: CGPoint(x: size * 0.585, y: size * 0.50),
                    control: CGPoint(x: size * 0.545, y: size * 0.575)
                )
                path.move(to: CGPoint(x: size * 0.50, y: size * 0.50))
                path.addQuadCurve(
                    to: CGPoint(x: size * 0.415, y: size * 0.50),
                    control: CGPoint(x: size * 0.455, y: size * 0.575)
                )
            }
            .stroke(OrbPalette.midnight.opacity(0.88), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: size, height: size)
            .offset(y: size * 0.09)
        }
        .offset(y: size * 0.035)
    }

    private var paws: some View {
        ZStack {
            Circle()
                .fill(OrbPalette.slate)
                .frame(width: size * 0.18, height: size * 0.21)
                .overlay(Circle().fill(.white.opacity(0.18)).scaleEffect(0.42).offset(y: size * -0.035))
                .shadow(color: OrbPalette.midnight.opacity(0.14), radius: 3, y: 2)
                .offset(x: size * -0.25, y: size * 0.31)

            Circle()
                .fill(OrbPalette.slate)
                .frame(width: size * 0.18, height: size * 0.21)
                .overlay(Circle().fill(.white.opacity(0.18)).scaleEffect(0.42).offset(y: size * -0.035))
                .shadow(color: OrbPalette.midnight.opacity(0.14), radius: 3, y: 2)
                .offset(x: size * 0.25, y: size * 0.31)
        }
    }

    private var feet: some View {
        ZStack {
            Ellipse()
                .fill(OrbPalette.midnight)
                .frame(width: size * 0.20, height: size * 0.11)
                .offset(x: size * -0.17, y: size * 0.565)
            Ellipse()
                .fill(OrbPalette.midnight)
                .frame(width: size * 0.20, height: size * 0.11)
                .offset(x: size * 0.17, y: size * 0.565)
        }
    }

    private var orbitBack: some View {
        orbitStroke
            .opacity(0.48)
            .mask(
                VStack(spacing: 0) {
                    Rectangle()
                        .frame(height: size * 0.60)
                    Spacer(minLength: 0)
                }
            )
            .offset(y: size * 0.085)
    }

    private var orbitFront: some View {
        ZStack {
            orbitStroke
                .mask(
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .frame(height: size * 0.78)
                    }
                )
                .offset(y: size * 0.085)

            Circle()
                .fill(OrbPalette.lavender)
                .frame(width: size * 0.145, height: size * 0.145)
                .overlay(Circle().fill(.white.opacity(0.55)).scaleEffect(0.40).offset(x: -2.4, y: -2.4))
                .shadow(color: OrbPalette.lavender.opacity(0.40), radius: 4)
                .offset(x: size * 0.54, y: size * -0.01)

            SparkleShape()
                .fill(OrbPalette.star)
                .frame(width: size * 0.155, height: size * 0.155)
                .shadow(color: OrbPalette.star.opacity(0.65), radius: 5)
                .offset(x: size * 0.32, y: size * 0.25)

            Circle()
                .fill(OrbPalette.indigo)
                .frame(width: size * 0.088, height: size * 0.088)
                .overlay(Circle().fill(.white.opacity(0.38)).scaleEffect(0.38).offset(x: -1.4, y: -1.4))
                .offset(x: size * -0.53, y: size * -0.11)
        }
    }

    private var orbitStroke: some View {
        Ellipse()
            .stroke(
                LinearGradient(
                    colors: [
                        OrbPalette.peach.opacity(0.72),
                        OrbPalette.lavender,
                        OrbPalette.indigo.opacity(0.68),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: size * 0.019
            )
            .frame(width: size * 1.42, height: size * 0.36)
            .rotationEffect(.degrees(-17))
            .shadow(color: OrbPalette.lavender.opacity(0.36), radius: 5)
    }

    private var mascotSparkles: some View {
        ZStack {
            ForEach(0..<OrbDecoration.mascotSparkles.count, id: \.self) { index in
                let sparkle = OrbDecoration.mascotSparkles[index]
                SparkleShape()
                    .fill(sparkle.color.opacity(sparkle.opacity))
                    .frame(width: sparkle.size * size, height: sparkle.size * size)
                    .offset(x: sparkle.x * size, y: sparkle.y * size)
            }

            ForEach(0..<OrbDecoration.mascotDots.count, id: \.self) { index in
                let dot = OrbDecoration.mascotDots[index]
                Circle()
                    .fill(dot.color.opacity(dot.opacity))
                    .frame(width: dot.size * size, height: dot.size * size)
                    .offset(x: dot.x * size, y: dot.y * size)
            }
        }
    }
}

private struct OrbMascotBodyShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let w = rect.width
        let h = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 100 * w, y: rect.minY + y / 112 * h)
        }

        var path = Path()
        path.move(to: p(50, 3))
        path.addCurve(to: p(88, 28), control1: p(66, 5), control2: p(80, 12))
        path.addCurve(to: p(96, 65), control1: p(97, 42), control2: p(99, 55))
        path.addCurve(to: p(84, 94), control1: p(94, 80), control2: p(90, 90))
        path.addCurve(to: p(50, 108), control1: p(74, 105), control2: p(62, 109))
        path.addCurve(to: p(16, 94), control1: p(38, 109), control2: p(26, 105))
        path.addCurve(to: p(4, 65), control1: p(10, 90), control2: p(6, 80))
        path.addCurve(to: p(12, 28), control1: p(1, 55), control2: p(3, 42))
        path.addCurve(to: p(50, 3), control1: p(20, 12), control2: p(34, 5))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct OrbEye: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: size, height: size)
                .shadow(color: .white.opacity(0.85), radius: size * 0.18)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.90),
                            OrbPalette.lavender,
                            OrbPalette.indigo,
                            OrbPalette.midnight,
                        ],
                        center: UnitPoint(x: 0.30, y: 0.24),
                        startRadius: 1,
                        endRadius: size * 0.50
                    )
                )
                .frame(width: size * 0.72, height: size * 0.72)

            Circle()
                .fill(OrbPalette.midnight.opacity(0.90))
                .frame(width: size * 0.40, height: size * 0.40)
                .offset(x: size * 0.02, y: size * 0.02)

            Circle()
                .fill(.white)
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(x: size * -0.14, y: size * -0.13)

            Circle()
                .fill(.white)
                .frame(width: size * 0.10, height: size * 0.10)
                .offset(x: size * 0.13, y: size * -0.13)

            Circle()
                .fill(.white.opacity(0.75))
                .frame(width: size * 0.09, height: size * 0.09)
                .offset(x: size * 0.10, y: size * 0.12)
        }
    }
}

private struct SparkleShape: Shape {
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

private enum ShareRenderError: Error {
    case failed
}

private enum OrbPalette {
    static let midnight = Color(hex: "1B1E3A")
    static let indigo = Color(hex: "5D5FAE")
    static let lavender = Color(hex: "B8A7D9")
    static let blush = Color(hex: "FFD6E0")
    static let peach = Color(hex: "FFE1C2")
    static let silver = Color(hex: "D7DCE6")
    static let star = Color(hex: "FFF5D6")
    static let slate = Color(hex: "71788F")
    static let mist = Color(hex: "F4F7FB")
    static let cream = Color(hex: "FFF8EB")
}

private enum OrbDecoration {
    static let furRim: [DecorationPoint] = [
        .init(x: -0.34, y: -0.28, size: 0.18, opacity: 0.72, color: OrbPalette.midnight),
        .init(x: -0.45, y: -0.12, size: 0.16, opacity: 0.76, color: OrbPalette.midnight),
        .init(x: -0.48, y: 0.10, size: 0.17, opacity: 0.78, color: OrbPalette.midnight),
        .init(x: -0.40, y: 0.31, size: 0.15, opacity: 0.74, color: OrbPalette.midnight),
        .init(x: -0.25, y: 0.48, size: 0.13, opacity: 0.72, color: OrbPalette.midnight),
        .init(x: 0.00, y: 0.54, size: 0.14, opacity: 0.70, color: OrbPalette.midnight),
        .init(x: 0.25, y: 0.48, size: 0.13, opacity: 0.72, color: OrbPalette.midnight),
        .init(x: 0.40, y: 0.31, size: 0.15, opacity: 0.74, color: OrbPalette.midnight),
        .init(x: 0.48, y: 0.10, size: 0.17, opacity: 0.78, color: OrbPalette.midnight),
        .init(x: 0.45, y: -0.12, size: 0.16, opacity: 0.76, color: OrbPalette.midnight),
        .init(x: 0.34, y: -0.28, size: 0.18, opacity: 0.72, color: OrbPalette.midnight),
        .init(x: 0.08, y: -0.43, size: 0.12, opacity: 0.56, color: OrbPalette.lavender),
        .init(x: -0.12, y: -0.41, size: 0.11, opacity: 0.48, color: OrbPalette.indigo),
    ]

    static let cardSparkles: [DecorationPoint] = [
        .init(x: -132, y: -168, size: 10, opacity: 0.55, color: OrbPalette.lavender),
        .init(x: 118, y: -175, size: 8, opacity: 0.58, color: OrbPalette.indigo),
        .init(x: 133, y: -104, size: 13, opacity: 0.48, color: OrbPalette.star),
        .init(x: -112, y: 30, size: 7, opacity: 0.40, color: OrbPalette.indigo),
        .init(x: 104, y: 116, size: 9, opacity: 0.42, color: OrbPalette.lavender),
        .init(x: -134, y: 164, size: 11, opacity: 0.50, color: OrbPalette.peach),
    ]

    static let cardDots: [DecorationPoint] = [
        .init(x: -94, y: -145, size: 5, opacity: 0.50, color: OrbPalette.indigo),
        .init(x: 86, y: -132, size: 4, opacity: 0.40, color: OrbPalette.lavender),
        .init(x: 136, y: 4, size: 5, opacity: 0.35, color: OrbPalette.peach),
        .init(x: -120, y: 104, size: 4, opacity: 0.34, color: OrbPalette.lavender),
        .init(x: 120, y: 178, size: 5, opacity: 0.36, color: OrbPalette.indigo),
    ]

    static let mascotSparkles: [DecorationPoint] = [
        .init(x: -0.26, y: -0.31, size: 0.060, opacity: 0.90, color: OrbPalette.star),
        .init(x: 0.18, y: -0.34, size: 0.050, opacity: 0.78, color: .white),
        .init(x: 0.31, y: -0.18, size: 0.042, opacity: 0.70, color: OrbPalette.peach),
        .init(x: -0.34, y: -0.07, size: 0.038, opacity: 0.62, color: OrbPalette.lavender),
        .init(x: 0.06, y: 0.25, size: 0.042, opacity: 0.72, color: .white),
        .init(x: 0.25, y: 0.10, size: 0.034, opacity: 0.62, color: OrbPalette.star),
        .init(x: -0.13, y: 0.10, size: 0.030, opacity: 0.56, color: OrbPalette.lavender),
        .init(x: 0.00, y: -0.43, size: 0.032, opacity: 0.60, color: OrbPalette.peach),
    ]

    static let mascotDots: [DecorationPoint] = [
        .init(x: -0.10, y: -0.36, size: 0.025, opacity: 0.70, color: .white),
        .init(x: 0.06, y: -0.26, size: 0.018, opacity: 0.55, color: OrbPalette.star),
        .init(x: 0.34, y: -0.02, size: 0.020, opacity: 0.50, color: .white),
        .init(x: -0.34, y: 0.17, size: 0.018, opacity: 0.54, color: OrbPalette.peach),
        .init(x: 0.26, y: 0.26, size: 0.015, opacity: 0.44, color: OrbPalette.lavender),
        .init(x: -0.23, y: -0.20, size: 0.017, opacity: 0.56, color: OrbPalette.star),
        .init(x: 0.22, y: -0.05, size: 0.014, opacity: 0.46, color: .white),
        .init(x: -0.03, y: -0.16, size: 0.013, opacity: 0.52, color: OrbPalette.lavender),
        .init(x: 0.15, y: 0.38, size: 0.014, opacity: 0.44, color: OrbPalette.star),
        .init(x: -0.18, y: 0.32, size: 0.013, opacity: 0.42, color: .white),
    ]
}

private struct DecorationPoint {
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
    let color: Color
}
