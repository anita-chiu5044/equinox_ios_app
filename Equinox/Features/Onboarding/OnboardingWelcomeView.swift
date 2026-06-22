import SwiftUI
import AuthenticationServices

struct OnboardingWelcomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            // Background
            Theme.bg
                .ignoresSafeArea()

            // Accent radial glow at top
            RadialGradient(
                colors: [Theme.accent.opacity(0.18), Theme.accent.opacity(0.07), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 380
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Top logo row
                HStack(spacing: 9) {
                    OrbitMark(size: 22)
                    Text("Equinox")
                        .font(Theme.serif(21))
                        .foregroundStyle(Theme.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Equinox")
                .padding(.top, 60)

                Spacer()

                // Orbital ambient illustration
                OrbitAmbient()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .accessibilityHidden(true)
                    .padding(.bottom, 8)

                // Hero text
                Text("Planning that\nevolves with you")
                    .font(Theme.serif(46))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Tell Equinox a goal and a deadline. It shapes the path — and quietly reshapes it as life moves.")
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(4)
                    .padding(.top, 16)
                    .frame(maxWidth: 320, alignment: .leading)

                Spacer()

                if let error = appState.authError {
                    InlineErrorView(message: error)
                        .padding(.bottom, 12)
                }

                VStack(spacing: 12) {
                    // Sign in with Apple
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task {
                            await appState.handleAppleAuthorization(result)
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 54)
                    .clipShape(.rect(cornerRadius: 16))
                    .shadow(color: Theme.ink.opacity(0.18), radius: 8, x: 0, y: 4)
                    .accessibilityLabel("Sign in with Apple")

                    // Sign in with Google
                    Button {
                        Task {
                            await appState.signInWithGoogle()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            GoogleGlyph(size: 20)
                            Text("Continue with Google")
                                .font(Theme.sans(16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.ink)
                    .background(Theme.surface)
                    .clipShape(.rect(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Theme.faint.opacity(0.6), lineWidth: 1)
                    )
                    .shadow(color: Theme.ink.opacity(0.06), radius: 6, x: 0, y: 2)
                    .accessibilityLabel("Sign in with Google")

                    // Authorization text
                    Text("By continuing you agree to our Terms & Privacy.")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
                .padding(.bottom, 44)
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Google four-color G glyph

struct GoogleGlyph: View {
    var size: CGFloat = 20

    var body: some View {
        Canvas { ctx, _ in
            // Draw a simplified four-color Google "G"
            let s = size
            let center = CGPoint(x: s / 2, y: s / 2)
            let r = s * 0.46
            let strokeW = s * 0.22

            // Red arc  (top-right, 315° → 45°)
            drawArc(ctx: ctx, center: center, radius: r, strokeWidth: strokeW,
                    from: -45, to: 45, color: Color(hex: "EA4335"))
            // Yellow arc (bottom-right, 45° → 135°)
            drawArc(ctx: ctx, center: center, radius: r, strokeWidth: strokeW,
                    from: 45, to: 135, color: Color(hex: "FBBC05"))
            // Green arc (bottom-left, 135° → 225°)
            drawArc(ctx: ctx, center: center, radius: r, strokeWidth: strokeW,
                    from: 135, to: 225, color: Color(hex: "34A853"))
            // Blue arc (top-left, 225° → 315°)
            drawArc(ctx: ctx, center: center, radius: r, strokeWidth: strokeW,
                    from: 225, to: 315, color: Color(hex: "4285F4"))

            // Horizontal arm of the G
            let armY = center.y
            let armLeft = center.x - strokeW * 0.1
            let armRight = center.x + r + strokeW * 0.5
            var armPath = Path()
            armPath.move(to: CGPoint(x: armLeft, y: armY))
            armPath.addLine(to: CGPoint(x: armRight, y: armY))
            ctx.stroke(armPath, with: .color(Color(hex: "4285F4")), lineWidth: strokeW)
        }
        .frame(width: size, height: size)
    }

    private func drawArc(ctx: GraphicsContext, center: CGPoint, radius: CGFloat,
                         strokeWidth: CGFloat, from startDeg: CGFloat, to endDeg: CGFloat,
                         color: Color) {
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startDeg),
            endAngle: .degrees(endDeg),
            clockwise: false
        )
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .butt))
    }
}


#Preview {
    OnboardingWelcomeView()
        .environmentObject(AppState())
}
