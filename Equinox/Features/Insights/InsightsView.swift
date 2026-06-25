import SwiftUI
import Combine

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published var insights: InsightsDTO?
    @Published var healthSnapshot: HealthKitService.HealthSnapshot?
    @Published var learningProfile: LearningProfileDTO?
    @Published var capacity: CapacityDTO?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api: APIClient
    private let health: HealthKitService

    init(api: APIClient? = nil, health: HealthKitService? = nil) {
        self.api = api ?? .shared
        self.health = health ?? .shared
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let insightsRequest = api.insights()
            async let profileRequest = api.learningProfile()
            async let capacityRequest = api.todayCapacity()
            insights = try await insightsRequest
            learningProfile = try? await profileRequest
            capacity = try? await capacityRequest
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        if health.isAvailable, await health.requestAuthorization() {
            healthSnapshot = await health.healthSnapshot()
        }
    }
}

struct InsightsView: View {
    @StateObject private var viewModel = InsightsViewModel()
    private let columns = [
        GridItem(.flexible(), spacing: Theme.Space.md),
        GridItem(.flexible(), spacing: Theme.Space.md),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    SectionHeader("Insights", subtitle: "Learning, energy, and health patterns")

                    if let error = viewModel.errorMessage {
                        InlineErrorView(message: error)
                    }

                    if viewModel.isLoading && viewModel.insights == nil {
                        ProgressView("Loading insights...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if let insights = viewModel.insights {
                        LazyVGrid(columns: columns, spacing: Theme.Space.md) {
                            ForEach(insights.stats) { stat in
                                statCard(stat)
                            }
                        }

                        healthCard(insights.healthAnalysis, snapshot: viewModel.healthSnapshot)

                        if let capacity = viewModel.capacity {
                            todayCapacityCard(capacity)
                        }

                        if let profile = viewModel.learningProfile {
                            learningProfileCard(profile)
                        }

                        // A. Hourly Rhythm card
                        hourlyRhythmCard(insights)

                        // B. Estimation bias card
                        if insights.timeBias != nil {
                            estimationBiasCard(insights)
                        }

                        // C. This week card
                        thisWeekCard(insights)

                        // D. Energy & output line chart
                        energyOutputCard(insights)

                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Image(systemName: "clock")
                                        .foregroundStyle(Theme.accent)
                                    Text("Peak hours")
                                        .font(Theme.sans(16, weight: .semibold))
                                        .foregroundStyle(Theme.ink)
                                }
                                Text(insights.peakHours.isEmpty
                                     ? "Not enough completed sessions yet."
                                     : insights.peakHours.map { "\($0):00" }.joined(separator: ", "))
                                    .font(Theme.sans(14))
                                    .foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Weekday rhythm")
                                    .font(Theme.sans(16, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                let maxVal = insights.rhythm.max() ?? 1
                                ForEach(Array(insights.rhythm.enumerated()), id: \.offset) { index, value in
                                    HStack(spacing: 10) {
                                        Text(dayName(index))
                                            .font(Theme.mono(12))
                                            .foregroundStyle(Theme.muted)
                                            .frame(width: 32, alignment: .leading)
                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Theme.bgWarm)
                                                    .frame(height: 8)
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Theme.accent)
                                                    .frame(
                                                        width: maxVal > 0
                                                            ? geo.size.width * CGFloat(value / maxVal)
                                                            : 0,
                                                        height: 8
                                                    )
                                            }
                                        }
                                        .frame(height: 8)
                                        Text(value > 0 ? String(format: "%.0f", value) : "–")
                                            .font(Theme.mono(11))
                                            .foregroundStyle(Theme.faint)
                                            .frame(width: 20, alignment: .trailing)
                                    }
                                }
                            }
                        }

                        // E. What Equinox will adjust card
                        adjustmentsCard(insights)
                    } else {
                        ContentUnavailableView("No insight data", systemImage: "chart.bar")
                    }
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("Insights")
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
        }
    }

    private func statCard(_ stat: InsightStatDTO) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(stat.n)
                    .font(Theme.serif(28, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(stat.unit)
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                Text(stat.sub)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func healthCard(
        _ analysis: HealthAnalysisDTO,
        snapshot: HealthKitService.HealthSnapshot?
    ) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Health & energy", systemImage: "heart.text.square.fill")
                        .font(Theme.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text(trendLabel(analysis.trend))
                        .font(Theme.mono(10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }

                Text(snapshot?.recommendation ?? analysis.summary)
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                HStack(spacing: 18) {
                    healthMetric(
                        value: formattedHours(snapshot?.lastNightSleepHours),
                        label: "last sleep"
                    )
                    healthMetric(
                        value: formattedHours(snapshot?.sevenDaySleepAverage),
                        label: "7-day avg"
                    )
                    healthMetric(
                        value: snapshot?.todaySteps.map(String.init) ?? "--",
                        label: "steps today"
                    )
                }

                HStack {
                    Text(snapshot?.status ?? "HealthKit data unavailable")
                    Spacer()
                    Text("\(analysis.checkinDays) energy check-ins")
                }
                .font(Theme.mono(11))
                .foregroundStyle(Theme.muted)
            }
        }
    }

    private func learningProfileCard(_ profile: LearningProfileDTO) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(Theme.accent)
                    Text("Your learning rhythm")
                        .font(Theme.sans(16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
                Text("\(profile.sampleCount) completed sessions · \(profile.confidence.capitalized) confidence")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.inkSoft)
                Text(profile.confidence == "low"
                     ? "Keep completing sessions to make scheduling more personal."
                     : "Future plans use your pace, strongest study windows, and energy patterns.")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func healthMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(Theme.serif(22, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func todayCapacityCard(_ capacity: CapacityDTO) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today's capacity")
                            .font(Theme.sans(16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(capacity.date)
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text("\(capacity.dcs)/100")
                        .font(Theme.serif(26, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }

                Text(capacity.dcs < 60
                     ? "A lighter learning load is recommended today."
                     : "Your plan is matched to today's capacity.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.inkSoft)

                HStack(spacing: 12) {
                    capacityMetric("Sleep", capacity.sleepScore)
                    capacityMetric("Activity", capacity.activityScore)
                    capacityMetric("Fatigue", capacity.fatigueScore)
                    capacityMetric("Completion", capacity.completionScore)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func capacityMetric(_ label: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.map { "\($0)" } ?? "--")
                .font(Theme.mono(13, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedHours(_ hours: Double?) -> String {
        guard let hours else {
            return "--"
        }
        return String(format: "%.1fh", hours)
    }

    private func trendLabel(_ trend: String) -> String {
        switch trend {
        case "improving": "IMPROVING"
        case "declining": "DECLINING"
        case "steady": "STEADY"
        default: "BUILDING BASELINE"
        }
    }

    private func dayName(_ index: Int) -> String {
        ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][index]
    }

    // MARK: - New cards

    private func hourlyRhythmCard(_ insights: InsightsDTO) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("YOUR RHYTHM")
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.muted)

                GeometryReader { geo in
                    let barCount = 15 // 7am..9pm
                    let spacing: CGFloat = 3
                    let totalSpacing = spacing * CGFloat(barCount - 1)
                    let barWidth = (geo.size.width - totalSpacing) / CGFloat(barCount)
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(0..<barCount, id: \.self) { i in
                            let hour = i + 7
                            let isPeak = insights.peakHours.contains(hour)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isPeak ? Theme.accent : Theme.shadowInk.opacity(0.13))
                                .frame(width: barWidth, height: 96)
                        }
                    }
                }
                .frame(height: 96)

                HStack {
                    Text("7a").font(Theme.mono(10)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("12p").font(Theme.mono(10)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("5p").font(Theme.mono(10)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("9p").font(Theme.mono(10)).foregroundStyle(Theme.muted)
                }

                let firstPeak = insights.peakHours.first.map { "\($0):00" } ?? "morning"
                let lastPeak  = insights.peakHours.last.map  { "\($0):00" } ?? "afternoon"
                Text("You finish your hardest tasks between \(firstPeak) and \(lastPeak) — that's your sharpest stretch.")
                    .font(Theme.serif(16.5).italic())
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func estimationBiasCard(_ insights: InsightsDTO) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("ESTIMATION BIAS")
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.muted)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("~\(Int((insights.timeBias ?? 0) * 100))%")
                        .font(Theme.serif(58, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("longer\non reading")
                        .font(Theme.sans(15, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("On average, your actual reading time runs \(Int((insights.timeBias ?? 0) * 100))% over your estimates. Equinox will buffer your schedule accordingly.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func thisWeekCard(_ insights: InsightsDTO) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("THIS WEEK")
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.muted)

                HStack(spacing: 0) {
                    ForEach(Array(insights.stats.prefix(3).enumerated()), id: \.offset) { i, stat in
                        if i > 0 {
                            Divider()
                                .frame(height: 44)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.n)
                                .font(Theme.serif(34, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text(stat.unit)
                                .font(Theme.sans(12, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                            Text(stat.sub)
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, i == 0 ? 0 : 12)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func energyOutputCard(_ insights: InsightsDTO) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("ENERGY & OUTPUT")
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.muted)

                // Legend
                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(Theme.inkSoft.opacity(0.55))
                            .frame(width: 20, height: 2)
                        Text("Energy")
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(width: 20, height: 2)
                        Text("Output")
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }

                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let capSeries  = insights.capacitySeries
                    let doneSeries = insights.doneSeries
                    let count = max(max(capSeries.count, doneSeries.count), 2)

                    ZStack {
                        // Horizontal guide lines at 0, 50, 100
                        ForEach([0, 50, 100], id: \.self) { level in
                            let y = h - (CGFloat(level) / 100.0) * h
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: y))
                                p.addLine(to: CGPoint(x: w, y: y))
                            }
                            .stroke(Theme.line2, lineWidth: 1)
                        }

                        // Capacity series (inkSoft, opacity 0.55)
                        if capSeries.count >= 2 {
                            Path { p in
                                for (i, val) in capSeries.enumerated() {
                                    let x = w * CGFloat(i) / CGFloat(count - 1)
                                    let y = h - (CGFloat(val) / 100.0) * h
                                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                                    else       { p.addLine(to: CGPoint(x: x, y: y)) }
                                }
                            }
                            .stroke(Theme.inkSoft.opacity(0.55), lineWidth: 1.8)

                            // End dot
                            if let lastVal = capSeries.last {
                                let x = w * CGFloat(capSeries.count - 1) / CGFloat(count - 1)
                                let y = h - (CGFloat(lastVal) / 100.0) * h
                                Circle()
                                    .fill(Theme.inkSoft.opacity(0.55))
                                    .frame(width: 6, height: 6)
                                    .position(x: x, y: y)
                            }
                        }

                        // Done series (accent)
                        if doneSeries.count >= 2 {
                            Path { p in
                                for (i, val) in doneSeries.enumerated() {
                                    let x = w * CGFloat(i) / CGFloat(count - 1)
                                    let y = h - (CGFloat(val) / 100.0) * h
                                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                                    else       { p.addLine(to: CGPoint(x: x, y: y)) }
                                }
                            }
                            .stroke(Theme.accent, lineWidth: 2.2)

                            // End dot
                            if let lastVal = doneSeries.last {
                                let x = w * CGFloat(doneSeries.count - 1) / CGFloat(count - 1)
                                let y = h - (CGFloat(lastVal) / 100.0) * h
                                Circle()
                                    .fill(Theme.accent)
                                    .frame(width: 7, height: 7)
                                    .position(x: x, y: y)
                            }
                        }
                    }
                }
                .frame(height: 120)

                HStack {
                    Text("14 days ago")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Text("today")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.muted)
                }

                Text("Your energy and output tracked over the last two weeks.")
                    .font(Theme.serif(13).italic())
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func adjustmentsCard(_ insights: InsightsDTO) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("WHAT EQUINOX WILL ADJUST")
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(Theme.muted)

                if insights.adjustments.isEmpty {
                    Text("No adjustments scheduled yet — keep completing sessions to personalise your plan.")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(insights.adjustments, id: \.self) { item in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Theme.bgWarm)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Image(systemName: adjustmentIcon(for: item))
                                            .font(.system(size: 14))
                                            .foregroundStyle(Theme.accent)
                                    )
                                Text(item)
                                    .font(Theme.sans(13.5))
                                    .foregroundStyle(Theme.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func adjustmentIcon(for text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("sleep") || lower.contains("rest") { return "moon.zzz" }
        if lower.contains("schedule") || lower.contains("time") { return "calendar.badge.clock" }
        if lower.contains("break") || lower.contains("pause") { return "cup.and.saucer" }
        if lower.contains("focus") || lower.contains("deep") { return "brain.head.profile" }
        if lower.contains("exercise") || lower.contains("workout") { return "figure.walk" }
        if lower.contains("reading") || lower.contains("study") { return "book" }
        return "slider.horizontal.3"
    }
}

#Preview {
    InsightsView()
}
