import SwiftUI
import Combine

@MainActor
final class GoalDetailViewModel: ObservableObject {
    @Published var goal: GoalDTO?
    @Published var schedule: SchedulePreviewDTO?
    @Published var pendingSuggestion: SuggestionDTO?
    @Published var isLoading = false
    @Published var isRechecking = false
    @Published var recheckRevision: PlanRevisionDTO?
    @Published var errorMessage: String?

    @Published var isOffline = false

    private let goalID: String
    private let api: APIClient
    private let store: LocalStore
    private let sync: SyncService

    init(goalID: String, api: APIClient? = nil, store: LocalStore? = nil, sync: SyncService? = nil) {
        self.goalID = goalID
        self.api = api ?? .shared
        self.store = store ?? .shared
        self.sync = sync ?? .shared
    }

    func load() async {
        // Offline-first: render the cached goal, then refresh.
        if goal == nil {
            goal = store.cachedGoal(id: goalID)
        }

        isLoading = true
        defer { isLoading = false }

        do {
            async let goalRequest = api.goal(id: goalID)
            async let suggestionsRequest = api.pendingSuggestions()
            goal = try await goalRequest
            pendingSuggestion = ((try? await suggestionsRequest) ?? []).first { $0.goalId == goalID }
            if let goal {
                store.cacheGoal(goal)
            }
            isOffline = false
            errorMessage = nil
        } catch let error as APIError {
            if case .transport = error {
                goal = store.cachedGoal(id: goalID)
                isOffline = true
                errorMessage = nil
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scheduleGoal() async {
        do {
            schedule = try await api.scheduleGoal(id: goalID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func complete(_ session: SessionDTO) async -> SessionCompletionOutcome {
        do {
            let synced = try await sync.completeSession(id: session.id, actualMinutes: session.minutes)
            isOffline = !synced
            if synced {
                await load()
            } else {
                goal = store.cachedGoal(id: goalID)
            }
            return SessionCompletionOutcome(
                growthReward: nil,
                planCompletion: planCompletionReward()
            )
        } catch {
            errorMessage = error.localizedDescription
            return SessionCompletionOutcome(growthReward: nil, planCompletion: nil)
        }
    }

    private func planCompletionReward() -> PlanCompletionReward? {
        guard let goal else {
            return nil
        }
        let sessions = goal.phases.flatMap(\.sessions)
        guard !sessions.isEmpty, sessions.allSatisfy({ $0.status == "done" }) else {
            return nil
        }
        return PlanCompletionReward(
            goalId: goal.id,
            goalTitle: goal.title,
            completedSessionCount: sessions.count,
            completedMinutes: sessions.reduce(0) { $0 + ($1.actualMinutes ?? $1.minutes) }
        )
    }

    func setFamiliarity(_ value: Int, for session: SessionDTO) async {
        do {
            let synced = try await sync.setFamiliarity(id: session.id, value: value)
            isOffline = !synced
            if synced {
                await load()
            } else {
                goal = store.cachedGoal(id: goalID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func replan(
        instructions: String,
        targetSessionMinutes: Int,
        preserveCompleted: Bool
    ) async -> Bool {
        guard !isRechecking else {
            return false
        }
        isRechecking = true
        defer { isRechecking = false }

        do {
            guard let previousGoal = goal else {
                return false
            }
            var generatedPhases: [ReplanPhaseRequest]?
            var source = "cloud"
            if OnDevicePlanner.isAvailable {
                do {
                    let plan = try await OnDevicePlanner().makeRecheckedPlan(
                        goal: previousGoal,
                        instructions: instructions,
                        targetSessionMinutes: targetSessionMinutes,
                        preserveCompleted: preserveCompleted,
                        personalLearningContext: (try? await api.learningProfile())?.promptContext
                    )
                    generatedPhases = plan.replanRequestPhases
                    source = "apple_intelligence"
                } catch {
                    // Keep the cloud planner as a runtime fallback when the
                    // on-device model becomes unavailable during generation.
                }
            }

            let revision = try await api.replanGoal(
                id: goalID,
                request: ReplanGoalRequest(
                    instructions: instructions,
                    targetSessionMinutes: targetSessionMinutes,
                    preserveCompleted: preserveCompleted,
                    generatedPhases: generatedPhases,
                    source: source
                )
            )
            recheckRevision = revision
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func confirmSchedule() async {
        do {
            schedule = try await api.confirmSchedule(goalID: goalID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteGoal() async -> Bool {
        do {
            try await api.deleteGoal(id: goalID)
            store.removeGoal(id: goalID)
            goal = nil
            schedule = nil
            pendingSuggestion = nil
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct GoalDetailView: View {
    /// Behavioral anchors for the 1–4 familiarity scale (playbook Prompt 8).
    static let familiarityLabels = [
        "No real grasp",
        "Recognize it",
        "Can work through it",
        "I could teach this",
    ]

    @StateObject private var viewModel: GoalDetailViewModel
    @State private var showingRecheck = false
    @State private var showingDeletePlanAlert = false
    @State private var isDeletingPlan = false
    @State private var completionPresentation: GoalDetailCompletionPresentation?
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    private let onDeleted: (() -> Void)?

    init(goalID: String, onDeleted: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: GoalDetailViewModel(goalID: goalID))
        self.onDeleted = onDeleted
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 14) {
                if viewModel.isOffline {
                    OfflineBanner()
                }

                if let error = viewModel.errorMessage {
                    InlineErrorView(message: error)
                }

                if viewModel.isLoading && viewModel.goal == nil {
                    ProgressView("Loading goal...")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if let goal = viewModel.goal {
                    header(goal)

                    if !goal.materials.isEmpty {
                        materialsCard(goal.materials)
                    }

                    if let schedule = viewModel.schedule, !schedule.placed.isEmpty {
                        schedulePreview(schedule)
                    }

                    if let suggestion = viewModel.pendingSuggestion {
                        pendingSuggestionCard(suggestion)
                    }

                    ForEach(goal.phases.sorted(by: { $0.order < $1.order })) { phase in
                        SectionHeader(phase.name, subtitle: "\(phase.sessions.count) sessions")
                            .padding(.top, 8)

                        ForEach(phase.sessions) { session in
                            sessionCard(session)
                        }
                    }
                } else {
                    ContentUnavailableView("Goal unavailable", systemImage: "target")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 180)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.paper)
        .navigationTitle(viewModel.goal?.title ?? "Goal")
        .toolbar {
            Menu {
                Button {
                    Task {
                        await viewModel.scheduleGoal()
                    }
                } label: {
                    Label("Schedule", systemImage: "calendar.badge.plus")
                }

                Button {
                    Task {
                        await viewModel.confirmSchedule()
                    }
                } label: {
                    Label("Confirm schedule", systemImage: "checkmark.circle")
                }

                Button {
                    showingRecheck = true
                } label: {
                    Label("Recheck schedule with AI", systemImage: "sparkles")
                }

                Divider()

                Button(role: .destructive) {
                    showingDeletePlanAlert = true
                } label: {
                    Label("Delete plan", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .alert("Delete plan?", isPresented: $showingDeletePlanAlert) {
            Button("Delete", role: .destructive) {
                Task {
                    isDeletingPlan = true
                    let deleted = await viewModel.deleteGoal()
                    isDeletingPlan = false
                    if deleted {
                        onDeleted?()
                        dismiss()
                    }
                }
            }
            .disabled(isDeletingPlan)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the plan and its sessions from Equinox. This cannot be undone.")
        }
        .task {
            await viewModel.load()
        }
        .sheet(isPresented: $showingRecheck) {
            if let goal = viewModel.goal {
                RecheckPlanSheet(
                    goal: goal,
                    isSubmitting: viewModel.isRechecking,
                    errorMessage: viewModel.errorMessage
                ) { instructions, targetMinutes, preserveCompleted in
                    await viewModel.replan(
                        instructions: instructions,
                        targetSessionMinutes: targetMinutes,
                        preserveCompleted: preserveCompleted
                    )
                }
            } else {
                ProgressView("Loading plan...")
            }
        }
        .sheet(item: $completionPresentation) { presentation in
            SessionCompletionRewardContent(
                session: presentation.session,
                userName: appState.user?.name,
                actualMinutes: presentation.actualMinutes,
                completedAt: presentation.completedAt,
                completionOutcome: presentation.outcome,
                onDone: {
                    completionPresentation = nil
                }
            )
        }
        .sheet(item: $viewModel.recheckRevision) { revision in
            RevisionDiffView(revision: revision) {
                Task {
                    viewModel.recheckRevision = nil
                    await viewModel.load()
                    await viewModel.scheduleGoal()
                }
            }
        }
        .refreshable {
            await viewModel.load()
        }
    }

    private func header(_ goal: GoalDTO) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(goal.title)
                        .font(Theme.serif(30, weight: .semibold))
                        .foregroundStyle(Theme.ink)

                    Text(goal.tag ?? goal.status.capitalized)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.muted)
                }

                ProgressView(value: Double(goal.progress.pct), total: 100)
                    .tint(Theme.accent)

                planStarsStatus(goal.sessionStarProgress)

                HStack {
                    Text("\(goal.progress.pct)% complete")
                    Spacer()
                    if let deadline = goal.deadline {
                        Text(deadline.shortDisplay)
                    }
                }
                .font(Theme.mono(12))
                .foregroundStyle(Theme.muted)
            }
        }
    }

    private func planStarsStatus(_ progress: PlanStarProgress) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill((progress.isComplete ? Theme.prioLow : Theme.prioMed).opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: progress.isComplete ? "sparkles" : "star.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(progress.isComplete ? Theme.prioLow : Theme.prioMed)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(progress.isComplete ? "Plan stars complete" : "\(progress.collected) / \(progress.total) stars collected")
                    .font(Theme.sans(13.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                HStack(spacing: 4) {
                    ForEach(0..<max(progress.total, 1), id: \.self) { index in
                        Image(systemName: index < progress.collected ? "star.fill" : "star")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(index < progress.collected ? Theme.prioMed : Theme.faint.opacity(0.72))
                    }
                }

                Text(progress.isComplete ? "Your plan certificate is unlocked." : "Complete sessions to help Orb collect stars.")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.muted)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.surface2.opacity(0.82))
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder((progress.isComplete ? Theme.prioLow : Theme.prioMed).opacity(0.18), lineWidth: 1)
        }
    }

    private func recheckResult(_ summary: RecheckChangeSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("\(summary.source) updated your plan", systemImage: "checkmark.circle.fill")
                    .font(Theme.sans(14, weight: .semibold))
                    .foregroundStyle(Theme.prioLow)

                HStack(spacing: 22) {
                    changeMetric(
                        "Remaining sessions",
                        from: summary.previousRemainingCount,
                        to: summary.updatedRemainingCount
                    )
                    changeMetric(
                        "Remaining minutes",
                        from: summary.previousRemainingMinutes,
                        to: summary.updatedRemainingMinutes
                    )
                }

                Text("All \(summary.updatedRemainingCount) remaining sessions now use \(summary.targetMinutes)-minute blocks.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.inkSoft)

                ForEach(summary.changedTitles, id: \.self) { title in
                    Label(title, systemImage: "plus")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.muted)
                }

                if summary.preservedCompletedCount > 0 {
                    Text("\(summary.preservedCompletedCount) completed sessions were kept unchanged.")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func changeMetric(_ label: String, from previous: Int, to updated: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.sans(11))
                .foregroundStyle(Theme.muted)
            Text("\(previous) → \(updated)")
                .font(Theme.mono(14, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func materialsCard(_ materials: [MaterialDTO]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Materials")
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(materials.count)")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(materials) { material in
                        MaterialTile(material: material)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func schedulePreview(_ schedule: SchedulePreviewDTO) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Scheduled")
                    .font(Theme.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                ForEach(schedule.placed) { placed in
                    HStack {
                        Text(placed.label)
                            .foregroundStyle(Theme.inkSoft)
                        Spacer()
                        Text("\(placed.start)-\(placed.end)")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.muted)
                    }
                    .font(Theme.sans(13))
                }
            }
        }
    }

    private func pendingSuggestionCard(_ suggestion: SuggestionDTO) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("Plan needs review", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    .font(Theme.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(suggestion.reason)
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.inkSoft)
                Text("Review the proposed changes from Today. Your schedule will not change until you confirm.")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func sessionCard(_ session: SessionDTO) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.title)
                        .font(Theme.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    PriorityPill(priority: session.priority)
                }

                HStack(spacing: 10) {
                    Text("\(session.minutes) min")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.muted)
                    DifficultyBars(difficulty: session.difficulty)
                    if let start = session.scheduledStart {
                        Text(start.shortDisplay)
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.muted)
                    }
                }

                HStack {
                    Button(session.status == "done" ? "Done ✓" : "Mark done") {
                        Task {
                            let completedAt = Date()
                            let outcome = await viewModel.complete(session)
                            if outcome.planCompletion != nil {
                                completionPresentation = GoalDetailCompletionPresentation(
                                    session: session,
                                    actualMinutes: session.minutes,
                                    completedAt: completedAt,
                                    outcome: outcome
                                )
                            }
                        }
                    }
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(session.status == "done" ? Theme.muted : Theme.accent)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(session.status == "done" ? Theme.surface : Theme.accentWash)
                    .clipShape(.rect(cornerRadius: 10))
                    .disabled(session.status == "done")

                    Spacer()

                    // Familiarity 1–4 dots
                    HStack(spacing: 6) {
                        Text("Familiarity")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.faint)
                        ForEach(1...4, id: \.self) { value in
                            Button {
                                Task {
                                    await viewModel.setFamiliarity(value, for: session)
                                }
                            } label: {
                                Circle()
                                    .fill(session.familiarity == value ? Theme.accent : Theme.faint.opacity(0.4))
                                    .frame(width: 12, height: 12)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Familiarity \(value): \(Self.familiarityLabels[value - 1])")
                        }
                    }
                }
            }
        }
    }
}

private struct GoalDetailCompletionPresentation: Identifiable {
    let id = UUID()
    let session: SessionDTO
    let actualMinutes: Int
    let completedAt: Date
    let outcome: SessionCompletionOutcome
}

private struct RecheckPlanSheet: View {
    @Environment(\.dismiss) private var dismiss

    let goal: GoalDTO
    let isSubmitting: Bool
    let errorMessage: String?
    let onSubmit: (String, Int, Bool) async -> Bool

    @State private var instructions = ""
    @State private var targetMinutes: Int
    @State private var preserveCompleted = true

    private static let durationOptions = [20, 25, 30, 45, 60, 90]

    init(
        goal: GoalDTO,
        isSubmitting: Bool,
        errorMessage: String?,
        onSubmit: @escaping (String, Int, Bool) async -> Bool
    ) {
        self.goal = goal
        self.isSubmitting = isSubmitting
        self.errorMessage = errorMessage
        self.onSubmit = onSubmit

        let remainingMinutes = goal.phases
            .flatMap(\.sessions)
            .filter { $0.status != "done" }
            .map(\.minutes)
        let commonMinutes = Dictionary(grouping: remainingMinutes, by: { $0 })
            .max { $0.value.count < $1.value.count }?
            .key ?? 45
        let closest = Self.durationOptions.min {
            abs($0 - commonMinutes) < abs($1 - commonMinutes)
        } ?? 45
        _targetMinutes = State(initialValue: closest)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your changes") {
                    LabeledContent(
                        "Planner",
                        value: OnDevicePlanner.isAvailable
                            ? "Apple Intelligence (on-device)"
                            : "Equinox Cloud fallback"
                    )

                    TextEditor(text: $instructions)
                        .frame(minHeight: 110)
                        .overlay(alignment: .topLeading) {
                            if instructions.isEmpty {
                                Text("Example: shorter weekday sessions, more practice before review")
                                    .font(Theme.sans(13))
                                    .foregroundStyle(Theme.faint)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        }

                    Picker("Target session length", selection: $targetMinutes) {
                        ForEach(Self.durationOptions, id: \.self) { minutes in
                            Text("\(minutes) minutes").tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("Keep completed sessions", isOn: $preserveCompleted)
                }

                Section("Current plan") {
                    LabeledContent(
                        "Sessions",
                        value: "\(goal.phases.reduce(0) { $0 + $1.sessions.count })"
                    )
                    LabeledContent(
                        "Completed",
                        value: "\(goal.phases.flatMap(\.sessions).filter { $0.status == "done" }.count)"
                    )
                }

                if let errorMessage {
                    Section {
                        InlineErrorView(message: errorMessage)
                    }
                }

                Section {
                    Button {
                        Task {
                            if await onSubmit(instructions, targetMinutes, preserveCompleted) {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Label("Recheck & reschedule", systemImage: "sparkles")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
            .navigationTitle("AI schedule recheck")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }
}

// MARK: - MaterialTile

private struct MaterialTile: View {
    let material: MaterialDTO

    private var icon: String {
        switch material.type {
        case "pdf":  return "doc.fill"
        case "image", "photo": return "photo.fill"
        case "video": return "play.rectangle.fill"
        default: return "paperclip"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.accentWash)
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accent)
            }

            Text(material.name)
                .font(Theme.sans(12, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 90, alignment: .leading)

            Text(ByteCountFormatter.string(
                fromByteCount: Int64(material.sizeBytes),
                countStyle: .file
            ))
            .font(Theme.mono(10))
            .foregroundStyle(Theme.muted)
        }
        .padding(12)
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.line2, lineWidth: 1)
        )
        .frame(width: 114)
    }
}
