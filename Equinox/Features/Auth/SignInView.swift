import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Wordmark (design: orbit glyph + serif name)
            HStack(spacing: 9) {
                OrbitMark(size: 22)
                Text("Equinox")
                    .font(Theme.serif(21))
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Equinox")

            Spacer()

            OrbitAmbient()
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .accessibilityHidden(true)
                .padding(.bottom, 6)

            Text("Planning that\nevolves with you")
                .font(Theme.serif(42, weight: .regular))
                .foregroundStyle(Theme.ink)
                .lineSpacing(2)
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
                .accessibilityLabel("Continue with Apple")

                Button {
                    Task {
                        // Real browser OAuth (PKCE) when GOOGLE_IOS_CLIENT_ID
                        // is set; DEBUG dev bypass otherwise.
                        await appState.signInWithGoogle()
                    }
                } label: {
                    Label("Continue with Google", systemImage: "g.circle.fill")
                        .font(Theme.sans(16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink)
                .background(Theme.surface2)
                .clipShape(.rect(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.faint.opacity(0.6), lineWidth: 1)
                )
                .accessibilityLabel("Continue with Google")

                #if DEBUG
                PrimaryButton(
                    "Development Sign In",
                    systemImage: "bolt.fill",
                    isLoading: appState.authStatus == .signingIn
                ) {
                    Task {
                        await appState.signInForDevelopment()
                    }
                }
                #endif

                Text("By continuing you agree to our Terms & Privacy.")
                    .font(Theme.sans(11.5))
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 70)
        .padding(.bottom, 40)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Theme.paper.overlay(
                RadialGradient(
                    colors: [Color.white.opacity(0.5), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 420
                )
            )
        )
        .ignoresSafeArea()
    }
}

// MARK: - Orbit artwork (from the design prototypes)

/// Small wordmark glyph: a tilted orbit ring with the warm planet.
struct OrbitMark: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Ellipse()
                .stroke(Theme.ink, lineWidth: size * 0.045 * 2)
                .frame(width: size * 0.84, height: size * 0.30)
                .rotationEffect(.degrees(-22))
            Circle()
                .fill(Theme.accent)
                .frame(width: size * 0.20, height: size * 0.20)
                .offset(x: size * 0.29, y: -size * 0.20)
        }
        .frame(width: size, height: size)
    }
}

/// Ambient orbital illustration: three tilted rings, drifting planet.
struct OrbitAmbient: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            ring(rx: 264, ry: 88, opacity: 0.16)
            ring(rx: 192, ry: 64, opacity: 0.22)
            ring(rx: 116, ry: 38, opacity: 0.30)

            // faint center sun
            Circle()
                .fill(Theme.ink.opacity(0.35))
                .frame(width: 6.5, height: 6.5)

            // inner trail dot
            Circle()
                .fill(Theme.faint.opacity(0.7))
                .frame(width: 9, height: 9)
                .offset(orbitOffset(rx: 58, ry: 19, angle: 0.9))

            // mid companion
            Circle()
                .fill(Theme.accentSoft)
                .frame(width: 13, height: 13)
                .offset(orbitOffset(rx: 96, ry: 32, angle: 2.1))

            // the warm planet, gently drifting
            Circle()
                .fill(Theme.accent)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .fill(.white.opacity(0.55))
                        .frame(width: 8, height: 8)
                        .offset(x: -4.5, y: -4.5)
                )
                .offset(orbitOffset(rx: 132, ry: 44, angle: -0.7))
                .offset(y: drift ? -4 : 4)
                .animation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: drift)
        }
        .onAppear {
            drift = true
        }
    }

    private func ring(rx: CGFloat, ry: CGFloat, opacity: Double) -> some View {
        Ellipse()
            .stroke(Theme.ink.opacity(opacity), lineWidth: 1.4)
            .frame(width: rx, height: ry)
            .rotationEffect(.degrees(-20))
    }

    /// Point on a tilted (-20°) ellipse, mirroring the prototype's math.
    private func orbitOffset(rx: CGFloat, ry: CGFloat, angle: CGFloat) -> CGSize {
        let rot: CGFloat = -20 * .pi / 180
        let x = cos(angle) * rx
        let y = sin(angle) * ry
        return CGSize(
            width: x * cos(rot) - y * sin(rot),
            height: x * sin(rot) + y * cos(rot)
        )
    }
}

#Preview {
    SignInView()
        .environmentObject(AppState())
}
