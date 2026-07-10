import SwiftUI
import Combine

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var sessions: [SessionDTO] = []
    @Published var checkin: CheckinDTO?
    @Published var suggestion: SuggestionDTO?
    @Published var healthSuggestion: HealthKitService.EnergySuggestion?
    @Published var capacity: CapacityDTO?
    @Published var growth: GrowthCycleDTO?
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

    static func statusAdvice(for energy: String) -> String {
        switch energy {
        case "great":
            "Great energy today. Put the most demanding session near the front while focus is available."
        case "ok":
            "Steady energy today. Keep the plan realistic and protect one clear next step."
        case "tired":
            "Low energy today. Shorten the hardest block and leave room to recover."
        case "drained":
            "Protect recovery today. Choose a lighter task or move the hardest session forward."
        default:
            "Use your energy as a guide, then let Equinox shape today's plan around your actual capacity."
        }
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
                steps: snapshot.todaySteps,
                cyclePhase: snapshot.cyclePhase,
                cycleImpact: snapshot.cycleImpact
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
            async let growth = api.currentGrowth()

            self.sessions = try await sessions
            self.checkin = try await checkin
            self.suggestion = try await suggestion
            self.capacity = try? await capacity
            self.growth = try? await growth
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

    func complete(_ session: SessionDTO, actualMinutes: Int, familiarity: Int) async -> SessionCompletionOutcome {
        let previousGrowth = growth
        var planCompletion: PlanCompletionReward?
        do {
            let synced = try await sync.completeSession(id: session.id, actualMinutes: actualMinutes, familiarity: familiarity)
            isOffline = !synced
            if synced {
                await load()
                planCompletion = await planCompletionReward(for: session)
            } else {
                sessions = store.cachedTodaySessions()
            }
            return SessionCompletionOutcome(
                growthReward: growthReward(before: previousGrowth, after: growth),
                planCompletion: planCompletion
            )
        } catch {
            errorMessage = error.localizedDescription
            return SessionCompletionOutcome(growthReward: nil, planCompletion: nil)
        }
    }

    private func planCompletionReward(for session: SessionDTO) async -> PlanCompletionReward? {
        do {
            let goal = try await api.goal(id: session.goalId)
            let goalSessions = goal.phases.flatMap(\.sessions)
            guard !goalSessions.isEmpty, goalSessions.allSatisfy({ $0.status == "done" }) else {
                return nil
            }
            return PlanCompletionReward(
                goalId: goal.id,
                goalTitle: goal.title,
                completedSessionCount: goalSessions.count,
                completedMinutes: goalSessions.reduce(0) { $0 + ($1.actualMinutes ?? $1.minutes) }
            )
        } catch {
            return nil
        }
    }

    private func growthReward(before: GrowthCycleDTO?, after: GrowthCycleDTO?) -> GrowthReward? {
        guard let after else {
            return nil
        }
        let previousProgress = before?.progress ?? 0
        let points = max(0, after.progress - previousProgress)
        let didHatch = before?.state != "hatched" && after.state == "hatched"
        guard points > 0 || didHatch else {
            return nil
        }
        return GrowthReward(points: max(points, didHatch ? 1 : 0), didHatch: didHatch, cycle: after)
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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("growthCompanionEnabled") private var growthCompanionEnabled = true
    @AppStorage("activeSessionTimerID") private var activeSessionTimerID = ""
    @AppStorage("activeSessionTimerStartedAt") private var activeSessionTimerStartedAt = 0.0
    @AppStorage("lastSeenGrowthCycleID") private var lastSeenGrowthCycleID = ""
    @AppStorage("lastSeenGrowthProgress") private var lastSeenGrowthProgress = 0
    @StateObject private var viewModel = TodayViewModel()
    @State private var showingSuggestion = false
    @State private var showingEnergyPrompt = false
    @State private var hasPresentedEnergyPrompt = false
    @State private var energyPromptDayKey = ""
    @State private var completingSession: SessionDTO?
    @State private var measuredActualMinutes: [String: Int] = [:]
    @State private var companionRewardPoints = 0
    @State private var showingNest = false
    var openPlans: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    greetingHeader

                    if growthCompanionEnabled {
                        growthCompanionCard
                    }

                    if viewModel.isOffline {
                        OfflineBanner()
                    }

                    if let error = viewModel.errorMessage {
                        InlineErrorView(message: error)
                    }

                    if !viewModel.pendingRevisions.isEmpty {
                        pendingRevisionsBanner
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
            .platformHideNavigationBarToolbar()
            .task {
                await viewModel.load()
                await viewModel.loadHealthSuggestion()
                presentEnergyPromptIfNeeded()
            }
            .refreshable {
                await viewModel.load()
            }
            .onChange(of: viewModel.growth, initial: false) { _, growth in
                handleGrowthChange(growth)
            }
            .onChange(of: viewModel.checkin, initial: false) { _, checkin in
                if checkin != nil {
                    withAnimation(.easeOut(duration: 0.18)) {
                        showingEnergyPrompt = false
                    }
                }
            }
            .onChange(of: scenePhase, initial: false) { _, phase in
                guard phase == .active else {
                    return
                }
                Task {
                    await viewModel.load()
                    await viewModel.loadHealthSuggestion()
                    presentEnergyPromptIfNeeded()
                }
            }
        }
        .overlay {
            if showingEnergyPrompt {
                EnergyCheckinPromptDialog(
                    healthSuggestion: viewModel.healthSuggestion,
                    isSaving: viewModel.isCheckingIn
                ) { energy in
                    withAnimation(.easeOut(duration: 0.18)) {
                        showingEnergyPrompt = false
                    }
                    await viewModel.checkIn(energy: energy)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: showingEnergyPrompt)
        .sheet(item: $completingSession) { session in
            CompletionFeedbackSheet(
                session: session,
                userName: appState.user?.name,
                measuredActualMinutes: measuredActualMinutes[session.id]
            ) { actualMinutes, familiarity in
                let outcome = await viewModel.complete(session, actualMinutes: actualMinutes, familiarity: familiarity)
                if let reward = outcome.growthReward, reward.points > 0 {
                    showCompanionReward(points: reward.points)
                    if let cycle = reward.cycle {
                        lastSeenGrowthCycleID = cycle.id
                        lastSeenGrowthProgress = cycle.progress
                    }
                }
                clearTimerIfNeeded(for: session)
                measuredActualMinutes[session.id] = nil
                return outcome
            }
        }
        .sheet(isPresented: $showingNest) {
            if let growth = viewModel.growth {
                NestSheet(growth: growth)
            }
        }
    }

    // MARK: Greeting (design: mono date over serif greeting)

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.wide).day()).uppercased())
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .kerning(1.0)

                Spacer(minLength: 8)

                if growthCompanionEnabled, let growth = viewModel.growth {
                    EggStatusPill(growth: growth) {
                        showingNest = true
                    }
                }
            }

            Text("\(greeting), \(appState.user?.name ?? "there")")
                .font(Theme.serif(28, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(summaryLine)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }

    private var growthCompanionCard: some View {
        GrowthCompanionCard(
            growth: viewModel.growth,
            nextSession: heroSession,
            isActiveSessionRunning: activeSessionTimerID == heroSession?.id,
            isLowEnergy: isLowEnergy || isDCSLow,
            rewardPoints: companionRewardPoints,
            action: {
                if viewModel.growth != nil {
                    showingNest = true
                } else {
                    openPlans()
                }
            }
        )
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
            activeStartedAt: activeStartedAt(for: session),
            onStart: { startTimer(for: session) },
            onEnd: { endTimer(for: session) },
            onMarkDone: { completingSession = session }
        )
    }

    private func activeStartedAt(for session: SessionDTO) -> Date? {
        guard activeSessionTimerID == session.id, activeSessionTimerStartedAt > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: activeSessionTimerStartedAt)
    }

    private func startTimer(for session: SessionDTO) {
        activeSessionTimerID = session.id
        activeSessionTimerStartedAt = Date().timeIntervalSince1970
        measuredActualMinutes[session.id] = nil
    }

    private func endTimer(for session: SessionDTO) {
        guard let startedAt = activeStartedAt(for: session) else {
            completingSession = session
            return
        }
        measuredActualMinutes[session.id] = measuredMinutes(since: startedAt)
        clearTimerIfNeeded(for: session)
        completingSession = session
    }

    private func clearTimerIfNeeded(for session: SessionDTO) {
        guard activeSessionTimerID == session.id else {
            return
        }
        activeSessionTimerID = ""
        activeSessionTimerStartedAt = 0
    }

    private func measuredMinutes(since startedAt: Date, now: Date = .now) -> Int {
        max(1, Int(ceil(max(0, now.timeIntervalSince(startedAt)) / 60)))
    }

    private func handleGrowthChange(_ growth: GrowthCycleDTO?) {
        guard let growth else {
            return
        }
        guard lastSeenGrowthCycleID == growth.id else {
            lastSeenGrowthCycleID = growth.id
            lastSeenGrowthProgress = growth.progress
            return
        }
        if growth.progress > lastSeenGrowthProgress {
            showCompanionReward(points: growth.progress - lastSeenGrowthProgress)
        }
        lastSeenGrowthProgress = growth.progress
    }

    private func showCompanionReward(points: Int) {
        guard points > 0 else {
            return
        }
        companionRewardPoints = points
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if companionRewardPoints == points {
                companionRewardPoints = 0
            }
        }
    }

    private func presentEnergyPromptIfNeeded() {
        resetEnergyPromptGateIfNeeded()
        #if DEBUG
        let forceEnergyPrompt = ProcessInfo.processInfo.arguments.contains("-ForceEnergyPrompt")
        if forceEnergyPrompt, !hasPresentedEnergyPrompt {
            hasPresentedEnergyPrompt = true
            withAnimation(.easeOut(duration: 0.18)) {
                showingEnergyPrompt = true
            }
            return
        }
        #endif
        guard viewModel.checkin == nil, !hasPresentedEnergyPrompt else {
            return
        }
        hasPresentedEnergyPrompt = true
        withAnimation(.easeOut(duration: 0.18)) {
            showingEnergyPrompt = true
        }
    }

    private func resetEnergyPromptGateIfNeeded() {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        let dayKey = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        guard energyPromptDayKey != dayKey else {
            return
        }
        energyPromptDayKey = dayKey
        hasPresentedEnergyPrompt = false
    }

    /// Energy options, matching the design (emoji + label per key).
    static let energyOptions: [(key: String, emoji: String, label: String)] = [
        ("great", "⚡", "Very good"),
        ("ok", "🔋", "Okay"),
        ("tired", "🥱", "A bit tired"),
        ("drained", "🪫", "Drained"),
    ]

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
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
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
                        .fixedSize(horizontal: false, vertical: true)
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

    // Timeline focus discipline: exactly one accent dot per screen (status "now")
    private func dotColor(for session: SessionDTO) -> Color {
        if session.status == "now"     { return Theme.accent }   // Vermillion, the single focus point
        if session.status == "overdue" { return Theme.prioMed }  // Amber
        return Theme.faint                                       // Muted for everything else
    }

    private func timelineRow(_ session: SessionDTO, isLast: Bool) -> some View {
        let isDone    = session.status == "done"
        let isNow     = session.status == "now"
        let isOverdue = session.status == "overdue"

        return HStack(alignment: .top, spacing: 11) {
            // Time gutter — wide enough for localized AM/PM without wrapping.
            VStack(alignment: .trailing, spacing: 2) {
                if let start = session.scheduledStart {
                    Text(start.timeDisplay)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                if let end = session.scheduledEnd {
                    Text(end.timeDisplay)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            .frame(width: 54, alignment: .trailing)
            .padding(.top, 14)

            // Rail: dot + vertical connector line
            VStack(spacing: 0) {
                Circle()
                    .fill(dotColor(for: session))
                    .frame(width: 11, height: 11)
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
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

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
                .layoutPriority(1)

                Spacer(minLength: 8)

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

// MARK: - Energy check-in prompt

private struct EnergyCheckinPromptDialog: View {
    let healthSuggestion: HealthKitService.EnergySuggestion?
    let isSaving: Bool
    let onSelect: (String) async -> Void

    @State private var selectedIndex = 2

    private static let dialOptions: [EnergyDialOption] = [
        EnergyDialOption(key: "drained", emoji: "🪫", label: "Drained", progress: 0.00, tint: Color(hex: "c94f46")),
        EnergyDialOption(key: "tired", emoji: "🥱", label: "A bit tired", progress: 0.33, tint: Color(hex: "d5973d")),
        EnergyDialOption(key: "ok", emoji: "🔋", label: "Okay", progress: 0.67, tint: Color(hex: "7fa66a")),
        EnergyDialOption(key: "great", emoji: "⚡", label: "Very good", progress: 1.00, tint: Color(hex: "45a66f")),
    ]

    private var selectedOption: EnergyDialOption {
        Self.dialOptions[min(max(selectedIndex, 0), Self.dialOptions.count - 1)]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("How's your energy today?")
                        .font(Theme.serif(23, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Equinox will use this to keep today's plan humane, not to judge your pace.")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let hint = healthSuggestion,
                   let option = TodayView.energyOptions.first(where: { $0.key == hint.energyKey }) {
                    let hours = String(format: "%.1f", hint.sleepHours)
                    Label(
                        "Last night you slept \(hours) h — you might be feeling \"\(option.label)\".",
                        systemImage: "heart.fill"
                    )
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(Theme.surface2)
                    .clipShape(.rect(cornerRadius: 13))
                    .accessibilityLabel("Health suggestion: you slept \(hours) hours, you might be feeling \(option.label)")
                }

                EnergyProgressDial(
                    options: Self.dialOptions,
                    selectedIndex: $selectedIndex
                )
                .frame(maxWidth: .infinity)

                Button {
                    Task {
                        await onSelect(selectedOption.key)
                    }
                } label: {
                    Text("Set energy")
                        .font(Theme.sans(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(selectedOption.tint)
                .clipShape(.rect(cornerRadius: 15))
                .shadow(color: selectedOption.tint.opacity(0.28), radius: 10, x: 0, y: 5)
                .disabled(isSaving)
                .accessibilityLabel("Set energy to \(selectedOption.label)")

                if isSaving {
                    ProgressView("Saving today's check-in...")
                        .font(Theme.sans(12))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .frame(maxWidth: 344, alignment: .leading)
            .background(Theme.paper)
            .clipShape(.rect(cornerRadius: 26))
            .overlay {
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(Theme.line2, lineWidth: 1)
            }
            .shadow(color: Theme.shadowInk.opacity(0.22), radius: 28, x: 0, y: 16)
            .padding(.horizontal, 24)
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            if let hintIndex = Self.dialOptions.firstIndex(where: { $0.key == healthSuggestion?.energyKey }) {
                selectedIndex = hintIndex
            }
        }
    }
}

private struct EnergyDialOption: Identifiable {
    let key: String
    let emoji: String
    let label: String
    let progress: Double
    let tint: Color

    var id: String { key }
    var percentLabel: String { "\(Int(round(progress * 100)))%" }
}

private struct EnergyProgressDial: View {
    let options: [EnergyDialOption]
    @Binding var selectedIndex: Int

    private var selectedOption: EnergyDialOption {
        options[min(max(selectedIndex, 0), options.count - 1)]
    }

    private var gaugeGradient: LinearGradient {
        LinearGradient(
            colors: options.map(\.tint),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                let center = CGPoint(x: width / 2, y: height * 0.78)
                let radius = min(width * 0.41, height * 0.68)
                let needleLength = radius * 0.78

                ZStack {
                    GaugeArc(progress: 1)
                        .stroke(
                            gaugeGradient,
                            style: StrokeStyle(lineWidth: 24, lineCap: .round)
                        )
                        .frame(width: radius * 2, height: radius)
                        .position(x: center.x, y: center.y - radius / 2)
                        .opacity(0.22)

                    GaugeArc(progress: selectedOption.progress)
                        .stroke(
                            gaugeGradient,
                            style: StrokeStyle(lineWidth: 24, lineCap: .round)
                        )
                        .frame(width: radius * 2, height: radius)
                        .position(x: center.x, y: center.y - radius / 2)
                        .animation(.easeOut(duration: 0.22), value: selectedIndex)

                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) {
                                selectedIndex = index
                            }
                        } label: {
                            GaugeTick(tint: option.tint, isSelected: index == selectedIndex)
                        }
                        .buttonStyle(.plain)
                        .disabled(options.isEmpty)
                        .position(point(for: option.progress, center: center, radius: radius))
                        .accessibilityLabel("Choose \(option.label), \(option.percentLabel)")
                    }

                    GaugeNeedle(progress: selectedOption.progress)
                        .fill(selectedOption.tint)
                        .frame(width: needleLength * 2, height: needleLength)
                        .position(x: center.x, y: center.y - needleLength / 2)
                        .shadow(color: selectedOption.tint.opacity(0.24), radius: 6, x: 0, y: 3)
                        .animation(.spring(response: 0.34, dampingFraction: 0.76), value: selectedIndex)

                    VStack(spacing: 3) {
                        Text(selectedOption.label)
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(selectedOption.percentLabel)
                            .font(Theme.mono(12, weight: .semibold))
                            .foregroundStyle(selectedOption.tint)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(selectedOption.tint.opacity(0.10))
                    .clipShape(.capsule)
                    .overlay {
                        Capsule()
                            .strokeBorder(selectedOption.tint.opacity(0.18), lineWidth: 1)
                    }
                    .position(x: center.x, y: height - 16)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            withAnimation(.easeOut(duration: 0.12)) {
                                selectedIndex = nearestIndex(to: value.location, center: center)
                            }
                        }
                )
            }
            .frame(height: 174)

            Text("Move the needle to match your current capacity.")
                .font(Theme.sans(12))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityElement(children: .contain)
    }

    private func point(for progress: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = CGFloat(Double.pi - progress * Double.pi)
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y - sin(angle) * radius
        )
    }

    private func nearestIndex(to location: CGPoint, center: CGPoint) -> Int {
        guard !options.isEmpty else {
            return 0
        }
        let angle = atan2(center.y - location.y, location.x - center.x)
        let clampedAngle = min(max(Double(angle), 0), Double.pi)
        let normalizedProgress = 1 - (clampedAngle / Double.pi)
        let nearest = options.enumerated().min { lhs, rhs in
            abs(lhs.element.progress - normalizedProgress) < abs(rhs.element.progress - normalizedProgress)
        }
        return nearest?.offset ?? selectedIndex
    }
}

private struct GaugeArc: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let radius = min(rect.width / 2, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let samples = max(2, Int(64 * clampedProgress))
        var path = Path()

        for step in 0...samples {
            let localProgress = clampedProgress * Double(step) / Double(samples)
            let angle = Double.pi - localProgress * Double.pi
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y - sin(angle) * radius
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }
}

private struct GaugeNeedle: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let length = min(rect.width / 2, rect.height) * 0.96
        let angle = Double.pi - min(max(progress, 0), 1) * Double.pi
        let tip = CGPoint(
            x: center.x + cos(angle) * length,
            y: center.y - sin(angle) * length
        )
        let perpendicular = angle + Double.pi / 2
        let baseWidth: CGFloat = 13
        let left = CGPoint(
            x: center.x + cos(perpendicular) * baseWidth,
            y: center.y - sin(perpendicular) * baseWidth
        )
        let right = CGPoint(
            x: center.x - cos(perpendicular) * baseWidth,
            y: center.y + sin(perpendicular) * baseWidth
        )

        var path = Path()
        path.move(to: tip)
        path.addLine(to: left)
        path.addQuadCurve(to: right, control: CGPoint(x: center.x, y: center.y + 16))
        path.closeSubpath()
        return path
    }
}

private struct GaugeTick: View {
    let tint: Color
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(isSelected ? tint : Theme.paper)
            .frame(width: isSelected ? 18 : 12, height: isSelected ? 18 : 12)
            .overlay {
                Circle()
                    .strokeBorder(isSelected ? tint.opacity(0.40) : Theme.line2, lineWidth: 1.2)
            }
            .shadow(color: isSelected ? tint.opacity(0.26) : .clear, radius: 7, x: 0, y: 3)
            .frame(width: 44, height: 44)
    }
}

// MARK: - NowHeroCard (pulse animation + Start / Mark done)

private struct NowHeroCard: View {
    let session: SessionDTO
    var isLowEnergy: Bool = false
    let activeStartedAt: Date?
    let onStart: () -> Void
    let onEnd: () -> Void
    let onMarkDone: () -> Void

    @State private var pulsing = false

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
                .font(Theme.TextStyle.heroTitle)
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

            if let activeStartedAt {
                TimelineView(.periodic(from: activeStartedAt, by: 1)) { context in
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        Text(elapsedText(from: activeStartedAt, to: context.date))
                            .font(Theme.mono(13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text("actual time running")
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.muted)
                        Spacer()
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Theme.surface.opacity(0.72))
                    .clipShape(.capsule)
                }

                Button {
                    onEnd()
                } label: {
                    Label("End session", systemImage: "stop.fill")
                        .font(Theme.sans(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Theme.accent)
                .clipShape(.rect(cornerRadius: 14))
                .shadow(color: Theme.accentRing, radius: 11, x: 0, y: 5)
                .accessibilityLabel("End \(session.title) and record actual time")
            } else {
                HStack(spacing: 10) {
                    Button {
                        onStart()
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
        .shadowE2()
    }

    private func elapsedText(from start: Date, to now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(start)))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m \(String(format: "%02d", seconds))s"
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
