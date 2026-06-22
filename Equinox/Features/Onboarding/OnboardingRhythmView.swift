import SwiftUI

struct OnboardingRhythmView: View {
    var onContinue: () -> Void

    @AppStorage("productiveStart") private var productiveStart: Double = 9.0
    @AppStorage("productiveEnd") private var productiveEnd: Double = 17.0

    @State private var startHour: Double = 9.0
    @State private var endHour: Double = 17.0

    private func formatHour(_ hour: Double) -> String {
        let h = Int(hour)
        let m = hour.truncatingRemainder(dividingBy: 1) == 0.5 ? 30 : 0
        let ampm = h < 12 ? "AM" : "PM"
        let displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        if m == 0 {
            return "\(displayH) \(ampm)"
        } else {
            return "\(displayH):30 \(ampm)"
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Skip button row
                HStack {
                    Spacer()
                    Button("Skip") {
                        onContinue()
                    }
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.muted)
                }
                .padding(.top, 56)

                // Kicker
                Text("PRODUCTIVITY RHYTHM")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 32)

                // Headline
                Text("What's your\nrhythm?")
                    .font(Theme.serif(40))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                // Subhead
                Text("Equinox schedules your most important work when you're naturally in the zone.")
                    .font(Theme.sans(15))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(4)
                    .padding(.top, 12)

                // Productivity card
                VStack(alignment: .leading, spacing: 20) {
                    // Dynamic sentence
                    Text("I'm usually productive from ")
                        .font(Theme.serif(17).italic())
                        .foregroundStyle(Theme.inkSoft)
                    + Text(formatHour(startHour))
                        .font(Theme.serif(17).italic())
                        .foregroundStyle(Theme.accent)
                    + Text(" to ")
                        .font(Theme.serif(17).italic())
                        .foregroundStyle(Theme.inkSoft)
                    + Text(formatHour(endHour))
                        .font(Theme.serif(17).italic())
                        .foregroundStyle(Theme.accent)

                    // Range Slider
                    RangeSlider(startValue: $startHour, endValue: $endHour,
                                range: 5...23, step: 0.5)
                        .frame(height: 56)

                    // Labels
                    HStack {
                        Text("Early")
                        Spacer()
                        Text("Midday")
                        Spacer()
                        Text("Evening")
                    }
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.faint)
                }
                .padding(20)
                .background(Theme.surface)
                .clipShape(.rect(cornerRadius: 20))
                .shadow(color: Theme.ink.opacity(0.06), radius: 12, x: 0, y: 4)
                .padding(.top, 28)

                // Time zone row
                HStack {
                    Text("Time zone")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text(TimeZone.current.identifier.replacingOccurrences(of: "_", with: " "))
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.inkSoft)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.faint)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Theme.bgWarm)
                .clipShape(.rect(cornerRadius: 14))
                .padding(.top, 16)

                Spacer()

                // Continue button
                Button {
                    productiveStart = startHour
                    productiveEnd = endHour
                    onContinue()
                } label: {
                    Text("Continue")
                        .font(Theme.sans(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.plain)
                .background(Theme.accent)
                .clipShape(.rect(cornerRadius: 16))
                .shadow(color: Theme.accent.opacity(0.32), radius: 12, x: 0, y: 6)
                .padding(.bottom, 44)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            startHour = productiveStart
            endHour = productiveEnd
        }
    }
}

// MARK: - Range Slider

struct RangeSlider: View {
    @Binding var startValue: Double
    @Binding var endValue: Double
    let range: ClosedRange<Double>
    var step: Double = 0.5

    @State private var draggingStart = false
    @State private var draggingEnd = false

    private let thumbSize: CGFloat = 28
    private let trackHeight: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let trackWidth = width - thumbSize
            let startFraction = (startValue - range.lowerBound) / (range.upperBound - range.lowerBound)
            let endFraction = (endValue - range.lowerBound) / (range.upperBound - range.lowerBound)
            let startX = thumbSize / 2 + startFraction * trackWidth
            let endX = thumbSize / 2 + endFraction * trackWidth

            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Theme.bgWarm)
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbSize / 2)

                // Active fill between thumbs
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(0, endX - startX), height: trackHeight)
                    .offset(x: startX)

                // Start thumb
                thumbView(value: startValue, x: startX, isDragging: draggingStart)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                draggingStart = true
                                let fraction = (value.location.x - thumbSize / 2) / trackWidth
                                let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
                                let snapped = (raw / step).rounded() * step
                                let clamped = min(max(snapped, range.lowerBound), endValue - step)
                                startValue = clamped
                            }
                            .onEnded { _ in draggingStart = false }
                    )

                // End thumb
                thumbView(value: endValue, x: endX, isDragging: draggingEnd)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                draggingEnd = true
                                let fraction = (value.location.x - thumbSize / 2) / trackWidth
                                let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
                                let snapped = (raw / step).rounded() * step
                                let clamped = min(max(snapped, startValue + step), range.upperBound)
                                endValue = clamped
                            }
                            .onEnded { _ in draggingEnd = false }
                    )
            }
            .frame(height: geo.size.height)
        }
    }

    private func formatHour(_ hour: Double) -> String {
        let h = Int(hour)
        let m = hour.truncatingRemainder(dividingBy: 1) == 0.5 ? 30 : 0
        let ampm = h < 12 ? "AM" : "PM"
        let displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        if m == 0 {
            return "\(displayH)\(ampm)"
        } else {
            return "\(displayH):30\(ampm)"
        }
    }

    @ViewBuilder
    private func thumbView(value: Double, x: CGFloat, isDragging: Bool) -> some View {
        VStack(spacing: 4) {
            // Floating label
            Text(formatHour(value))
                .font(Theme.mono(11))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.surface)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
                )
                .opacity(isDragging ? 1 : 0.75)
                .scaleEffect(isDragging ? 1.05 : 1)
                .animation(.spring(response: 0.25), value: isDragging)

            // Thumb circle
            ZStack {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Circle()
                            .inset(by: 2)
                            .strokeBorder(Theme.accent, lineWidth: 2)
                    )
                    .shadow(color: Theme.ink.opacity(0.10), radius: 4, x: 0, y: 2)

                Circle()
                    .fill(Theme.accent)
                    .frame(width: 8, height: 8)
            }
        }
        .offset(x: x - thumbSize / 2)
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

#Preview {
    OnboardingRhythmView(onContinue: {})
        .environmentObject(AppState())
}
