import SwiftUI
import Combine

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var sessions: [SessionDTO] = []
    @Published var checkin: CheckinDTO?
    @Published var suggestion: SuggestionDTO?
    @Published var healthSuggestion: HealthKitService.EnergySuggestion?
    @Published var capacity: CapacityDTO?
    @Published var pendingRevisions: [PlanRevisionDTO] = []
    @Published var isLoading = false
    @Published var isCheckingIn = false
    @Published var isOffline = false
    @Published var errorMessage: String?

    private let api: APIClient
    private let store: LocalStore
    private let sync: SyncService
    private let health: HealthKitService

    init(api: APIClient? = nil, store: LocalStore? = nil, sync: SyncService? = nil, health: HealthKitService? = nil) {
        self.api = api ?? .shared
        self.store = store ?? .shared
        self.sync = sync ?? .shared
        self.health = health ?? .shared
    }

    /// Ask HealthKit for a sleep-based energy suggestion (only useful while
    /// today's check-in hasn't been answered yet).
    func loadHealthSuggestion() async {
        guard checkin == nil, health.isAvailable else {
            return
        }
        guard await health.requestAuthorization() else {
            return
        }
        healthSuggestion = await health.suggestedEnergy()
        let snapshot = await health.healthSnapshot()
        do {
            try await api.syncHealth(
                sleepHours: snapshot.lastNightSleepHours,
                steps: snapshot.todaySteps
            )
            capacity = try await api.todayCapacity()
        } catch {
            // HealthKit remains a local, opt-in enhancement when offline.
        }
    }

    func load() async {
        // 1. Render the local cache immediately (offline-first).
        if sessions.isEmpty {
            sessions = store.cachedTodaySessions()
            checkin = store.cachedTodayCheckin()
        }

        isLoading = true
        defer { isLoading = false }

        // 2. Replay any queued offline mutations, then refresh from network.
        await sync.replayPending()

        do {
            async let sessions = api.todaySessions()
            async let checkin = api.todayCheckin()
            async let suggestion = api.todaySuggestion()
            async let capacity = api.todayCapacity()

            self.sessions = try await sessions
            self.checkin = try await checkin
            self.suggestion = try await suggestion
            self.capacity = try? await capacity
            self.pendingRevisions = (try? await api.pendingRevisions()) ?? []
            store.cacheSessions(self.sessions)
            if let checkin = self.checkin {
                store.cacheCheckin(checkin)
            }
            isOffline = false
            errorMessage = nil
        } catch let error as APIError {
            if case .transport = error {
                // Offline: keep showing the cache.
                sessions = store.cachedTodaySessions()
                checkin = store.cachedTodayCheckin()
                isOffline = true
                errorMessage = nil
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkIn(energy: String) async {
        guard checkin == nil, !isCheckingIn else {
            return
        }
        isCheckingIn = true
        defer { isCheckingIn = false }

        do {
            let synced = try await sync.checkIn(energy: energy)
            isOffline = !synced
            checkin = store.cachedTodayCheckin()
            if synced {
                await load()
            }
        } catch let error as APIError {
            if case .status(409, _) = error {
                await load()
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func statusAdvice(for energy: String) -> String {
        switch energy {
        case "great":
            "Energy is strong. Start with one demanding session while your focus is fresh."
        case "ok":
            "Keep a balanced pace and leave a short break between focused sessions."
        case "tired":
            "Choose a shorter focus block first, then reassess before taking on harder work."
        case "drained":
            "Protect recovery today. Prioritize one essential task and defer optional deep work."
        default:
            "Use today's energy as a guide and adjust the plan when your focus changes."
        }
    }

    func complete(_ session: SessionDTO, actualMinutes: Int, familiarity: Int) async {
        do {
            let synced = try await sync.completeSession(id: session.id, actualMinutes: actualMinutes, familiarity: familiarity)
            isOffline = !synced
            if synced {
                await load()
            } else {
                sessions = store.cachedTodaySessions()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func previewSuggestion(_ option: SuggestionOptionDTO) async -> SuggestionPreviewDTO? {
        guard let suggestion else {
            return nil
        }

        do {
            return try await api.previewSuggestion(id: suggestion.id, choice: option.key)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func applySuggestion(_ option: SuggestionOptionDTO, rejectionReason: String? = nil) async -> Bool {
        guard let suggestion else { return false }
        do {
            _ = try await api.applySuggestion(
                id: suggestion.id, choice: option.key, rejectionReason: rejectionReason
            )
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = TodayViewModel()
    @State private var showingSuggestion = false
    @State private var completingSession: SessionDTO?
    @State private var showingCheckinChange = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    greetingHeader

                    if viewModel.isOffline {
                        OfflineBanner()
                    }

                    if let error = viewModel.errorMessage {
                        InlineErrorView(message: error)
                    }

                    energyCheckin

                    if !viewModel.pendingRevisions.isEmpty {
                        pendingRevisionsBanner
                    }

                    if let capacity = viewModel.capacity {
                        capacityCard(capacity)
                    }

                    if let checkin = viewModel.checkin {
                        statusAdvice(for: checkin)
                    }

                    if let suggestion = viewModel.suggestion, suggestion.status == "pending" {
                        suggestionTeaser(suggestion)
                    }

                    if let hero = heroSession {
                        nowHero(hero)
                    }

                    SectionHeader("Sessions", subtitle: "\(viewModel.sessions.count) scheduled")

                    if viewModel.isLoading && viewModel.sessions.isEmpty {
                        ProgressView("Loading today's plan...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if viewModel.sessions.isEmpty {
                        // Edge state: OpenDay — no sessions, pull next task forward
                        OpenDayBanner()
                            .padding(.top, 8)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.sessions.enumerated()), id: \.element.id) { idx, session in
                                timelineRow(session, isLast: idx == viewModel.sessions.count - 1)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.paper)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await viewModel.load()
                await viewModel.loadHealthSuggestion()
            }
            .refreshable {
                await viewModel.load()
            }
        }
        .sheet(item: $completingSession) { session in
            CompletionFeedbackSheet(session: session) { actualMinutes, familiarity in
                await viewModel.complete(session, actualMinutes: actualMinutes, familiarity: familiarity)
            }
        }
    }

    // MARK: Greeting (design: mono date over serif greeting)

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.wide).day()).uppercased())
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .kerning(1.0)

            Text("\(greeting), \(appState.user?.name ?? "there")")
                .font(Theme.serif(28, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(summaryLine)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var summaryLine: String {
        let remaining = viewModel.sessions.filter { $0.status != "done" }
        let minutes = remaining.reduce(0) { $0 + $1.minutes }
        if remaining.isEmpty {
            return "Nothing left today — well done"
        }
        return "\(remaining.count) sessions today · ~\(minutes / 60)h \(minutes % 60)m"
    }

    // MARK: "Right now" hero (design: pulse label + big title, accentWash bg)

    private var heroSession: SessionDTO? {
        viewModel.sessions.first { $0.status == "now" }
            ?? viewModel.sessions.first { $0.status != "done" }
    }

    /// True if the user is reportedly tired or drained today.
    private var isLowEnergy: Bool {
        guard let e = viewModel.checkin?.energy else { return false }
        return e == "tired" || e == "drained"
    }

    /// True if DCS < 40 (low capacity day).
    private var isDCSLow: Bool {
        (viewModel.capacity?.dcs ?? 100) < 40
    }

    private func nowHero(_ session: SessionDTO) -> some View {
        NowHeroCard(
            session: session,
            isLowEnergy: isLowEnergy || isDCSLow,
            onStart: { completingSession = session },
            onMarkDone: { completingSession = session }
        )
    }

    /// Energy options, matching the design (emoji + label per key).
    static let energyOptions: [(key: String, emoji: String, label: String)] = [
        ("great", "⚡", "Very good"),
        ("ok", "🔋", "Okay"),
        ("tired", "🥱", "A bit tired"),
        ("drained", "🪫", "Drained"),
    ]

    @ViewBuilder
    private var energyCheckin: some View {
        if let checkin = viewModel.checkin,
           let option = Self.energyOptions.first(where: { $0.key == checkin.energy }) {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.prioLow)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Today's check-in received")
                            .font(Theme.sans(14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text("Your energy status is locked until tomorrow.")
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.muted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        VStack(spacing: 2) {
                            Text(option.emoji)
                                .font(.title3)
                            Text(option.label)
                                .font(Theme.mono(10, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Button("Change") {
                            showingCheckinChange = true
                        }
                        .font(Theme.sans(11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .accessibilityLabel("Change today's energy check-in")
                    }
                }
            }
            .sheet(isPresented: $showingCheckinChange) {
                CheckinChangeSheet { energy in
                    await viewModel.checkIn(energy: energy)
                    showingCheckinChange = false
                }
            }
            .accessibilityLabel("Today's check-in received. Energy: \(option.label). Tap Change to update.")
        } else {
            // Not answered yet → the four-option grid from the design.
            Card {
                VStack(alignment: .leading, spacing: 13) {
                    Text("How's your energy today?")
                        .font(Theme.serif(17, weight: .regular))
                        .foregroundStyle(Theme.ink)

                    if let hint = viewModel.healthSuggestion,
                       let option = Self.energyOptions.first(where: { $0.key == hint.energyKey }) {
                        let hours = String(format: "%.1f", hint.sleepHours)
                        Label(
                            "Last night you slept \(hours) h — you might be feeling \"\(option.label)\".",
                            systemImage: "heart.fill"
                        )
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.inkSoft)
                        .accessibilityLabel("Health suggestion: you slept \(hours) hours, you might be feeling \(option.label)")
                    }

                    HStack(spacing: 8) {
                        ForEach(Self.energyOptions, id: \.key) { option in
                            Button {
                                Task {
                                    await viewModel.checkIn(energy: option.key)
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Text(option.emoji)
                                        .font(.system(size: 23))
                                    Text(option.label)
                                        .font(Theme.sans(10.5, weight: .medium))
                                        .foregroundStyle(Theme.inkSoft)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            .background(Theme.surface2)
                            .clipShape(.rect(cornerRadius: 10))
                            .disabled(viewModel.isCheckingIn)
                            .accessibilityLabel("Energy: \(option.label)")
                        }
                    }

                    if viewModel.isCheckingIn {
                        ProgressView("Saving today's check-in...")
                            .font(Theme.sans(12))
                    }
                }
            }
        }
    }

    private func statusAdvice(for checkin: CheckinDTO) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Status suggestion")
                        .font(Theme.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(TodayViewModel.statusAdvice(for: checkin.energy))
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func suggestionTeaser(_ suggestion: SuggestionDTO) -> some View {
        Button {
            showingSuggestion = true
        } label: {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Equinox has a suggestion")
                            .font(Theme.sans(14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(suggestion.reason)
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Image(systemName: "chevron.up")
                        .font(.caption)
                        .foregroundStyle(Theme.faint)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Suggestion: \(suggestion.reason). Tap to review options.")
        .sheet(isPresented: $showingSuggestion) {
            SuggestionSheet(suggestion: suggestion) { option in
                await viewModel.previewSuggestion(option)
            } onApply: { option, rejectionReason in
                await viewModel.applySuggestion(option, rejectionReason: rejectionReason)
            }
        }
    }

    private func capacityCard(_ capacity: CapacityDTO) -> some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Today's capacity: \(capacity.dcs)/100")
                        .font(Theme.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(capacity.dcs < 60 ? "A lighter learning load is recommended." : "Your plan is matched to today's capacity.")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
            }
        }
    }

    private var pendingRevisionsBanner: some View {
        Button {
            // Navigate to Plans tab
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3)
                    .foregroundStyle(Theme.amberText)
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.pendingRevisions.count == 1 ? "Your plan needs a review" : "\(viewModel.pendingRevisions.count) plans need review")
                        .font(Theme.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Tap to see what changed and confirm the new schedule.")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.faint)
            }
            .padding(14)
            .background(Theme.prioMed.opacity(0.10))
            .clipShape(.rect(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).strokeBorder(Theme.prioMed.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Timeline row (design: time gutter · rail dot · card)

    private func timelineRow(_ session: SessionDTO, isLast: Bool) -> some View {
        let isDone    = session.status == "done"
        let isNow     = session.status == "now"
        let isOverdue = session.status == "overdue"

        let railColor: Color = isDone ? Theme.faint
                             : isOverdue ? Theme.prioMed
                             : isNow ? Theme.accent
                             : Theme.faint

        return HStack(alignment: .top, spacing: 11) {
            // Time gutter — fixed 42 pt, right-aligned mono times
            VStack(alignment: .trailing, spacing: 2) {
                if let start = session.scheduledStart {
                    Text(start.timeDisplay)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.inkSoft)
                }
                if let end = session.scheduledEnd {
                    Text(end.timeDisplay)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.faint)
                }
            }
            .frame(width: 42, alignment: .trailing)
            .padding(.top, 14)

            // Rail: dot + vertical connector line
            VStack(spacing: 0) {
                Circle()
                    .fill(isNow ? Theme.accent : Color.white)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(railColor, lineWidth: 2))
                    .overlay(isNow ? Circle().stroke(Theme.accentWash, lineWidth: 4).padding(-2) : nil)
                    .padding(.top, 16)

                if !isLast {
                    Rectangle()
                        .fill(Theme.line)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 4)
                }
            }
            .frame(width: 14)

            // Card
            HStack(alignment: .center, spacing: 11) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.title)
                        .font(Theme.sans(14.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .strikethrough(isDone, color: Theme.faint)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        PriorityPill(priority: session.priority)
                        Text("\(session.minutes) min")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.muted)
                        if isOverdue {
                            Text("Overdue · reschedule?")
                                .font(Theme.sans(10.5, weight: .semibold))
                                .foregroundStyle(Theme.amberText)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Theme.prioMed.opacity(0.16))
                                .clipShape(.capsule)
                        }
                    }
                }

                Spacer()

                Button {
                    completingSession = session
                } label: {
                    ZStack {
                        Circle()
                            .fill(isDone ? Theme.accent : Color.clear)
                            .frame(width: 26, height: 26)
                        Circle()
                            .stroke(isDone ? Color.clear : (isOverdue ? Theme.prioMed : Theme.faint), lineWidth: 2)
                            .frame(width: 26, height: 26)
                        if isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isDone)
                .accessibilityLabel(isDone ? "Completed" : "Mark \(session.title) as done")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(
                isNow ? Theme.surface2 :
                isOverdue ? Theme.overdueSurface :
                Theme.surface
            )
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isNow ? Theme.accentSoft.opacity(0.4) :
                        isOverdue ? Theme.prioMed.opacity(0.27) :
                        Theme.line2,
                        lineWidth: 1
                    )
            }
            .shadow(
                color: isNow ? Theme.accentRing.opacity(0.5) : Theme.shadowInk.opacity(0.04),
                radius: isNow ? 12 : 1, x: 0, y: isNow ? 6 : 1
            )
            .opacity(isDone ? 0.55 : 1)
            .padding(.bottom, 10)
        }
    }
}

// MARK: - NowHeroCard (pulse animation + Start / Mark done)

private struct NowHeroCard: View {
    let session: SessionDTO
    var isLowEnergy: Bool = false
    let onStart: () -> Void
    let onMarkDone: () -> Void

    @State private var pulsing = false
    @State private var sessionStarted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                // Pulsing dot
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.30))
                        .frame(width: 16, height: 16)
                        .scaleEffect(pulsing ? 1.6 : 1.0)
                        .opacity(pulsing ? 0 : 0.7)
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 8, height: 8)
                }
                .onAppear {
                    withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                        pulsing = true
                    }
                }
                .accessibilityHidden(true)

                Text("RIGHT NOW")
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .kerning(1.4)
                Spacer()
                if let start = session.scheduledStart, let end = session.scheduledEnd {
                    Text("\(start.timeDisplay)–\(end.timeDisplay)")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.muted)
                }
            }

            Text(session.title)
                .font(Theme.sans(22, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if isLowEnergy {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.slash")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.amberText)
                    Text("Low energy day — take it easy if needed")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.amberText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.prioMed.opacity(0.13))
                .clipShape(.capsule)
            }

            HStack(spacing: 10) {
                PriorityPill(priority: session.priority)
                Text("\(session.minutes) min")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.muted)
                DifficultyBars(difficulty: session.difficulty)
            }

            if sessionStarted {
                // After tapping "Start" — show Mark done prominently
                Button {
                    onMarkDone()
                } label: {
                    Label("Mark done", systemImage: "checkmark")
                        .font(Theme.sans(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Theme.accent)
                .clipShape(.rect(cornerRadius: 14))
                .shadow(color: Theme.accentRing, radius: 11, x: 0, y: 5)
                .accessibilityLabel("Mark \(session.title) as done")
            } else {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            sessionStarted = true
                        }
                    } label: {
                        Label("Start session", systemImage: "play.fill")
                            .font(Theme.sans(14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Theme.accent)
                    .clipShape(.rect(cornerRadius: 14))
                    .shadow(color: Theme.accentRing, radius: 11, x: 0, y: 5)
                    .accessibilityLabel("Start \(session.title)")

                    Button {
                        onMarkDone()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .font(Theme.sans(13, weight: .semibold))
                            .padding(.vertical, 13)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .background(Theme.accentWash)
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Theme.accentRing, lineWidth: 1)
                    )
                    .accessibilityLabel("Mark \(session.title) as done directly")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.accentWash)
        .clipShape(.rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(Theme.accentRing, lineWidth: 1)
        }
        .shadow(color: Theme.shadowInk.opacity(0.05), radius: 1, x: 0, y: 1)
        .shadow(color: Theme.shadowInk.opacity(0.22), radius: 20, x: 0, y: 12)
    }
}

// MARK: - DifficultyBars (5 interactive squares)

struct DifficultyBars: View {
    let difficulty: Int
    var interactive: Bool = false
    var onSelect: ((Int) -> Void)? = nil

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { level in
                let filled = level <= difficulty
                RoundedRectangle(cornerRadius: 2)
                    .fill(filled ? Theme.accent : Theme.accent.opacity(0.15))
                    .frame(width: 6, height: level <= 2 ? 8 : level <= 4 ? 11 : 14)
                    .animation(.easeInOut(duration: 0.18), value: difficulty)
                    .if(interactive) { view in
                        view.onTapGesture {
                            onSelect?(level)
                        }
                    }
            }
        }
        .accessibilityLabel("Difficulty \(difficulty) out of 5")
    }
}

// MARK: - OpenDay edge state banner

private struct OpenDayBanner: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Theme.accentWash)
                    .frame(width: 64, height: 64)
                Image(systemName: "sun.horizon")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.accent)
            }

            VStack(spacing: 6) {
                Text("Open day")
                    .font(Theme.serif(22))
                    .foregroundStyle(Theme.ink)
                Text("No sessions are scheduled yet. Add a goal from Plans to start building your schedule.")
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

// MARK: - CheckinChangeSheet

private struct CheckinChangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) async -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Update today's energy")
                    .font(Theme.serif(24))
                    .foregroundStyle(Theme.ink)

                HStack(spacing: 12) {
                    ForEach(TodayView.energyOptions, id: \.key) { option in
                        Button {
                            Task {
                                await onSelect(option.key)
                            }
                        } label: {
                            VStack(spacing: 8) {
                                Text(option.emoji)
                                    .font(.system(size: 28))
                                Text(option.label)
                                    .font(Theme.sans(11, weight: .medium))
                                    .foregroundStyle(Theme.inkSoft)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .background(Theme.surface)
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Theme.faint.opacity(0.5), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding(.top, 32)
            .background(Theme.paper)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.45)])
    }
}

// MARK: - View extension helper

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    TodayView()
        .environmentObject(AppState())
}
