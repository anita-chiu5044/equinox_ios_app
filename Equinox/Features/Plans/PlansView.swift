import SwiftUI
import Combine

@MainActor
final class PlansViewModel: ObservableObject {
    @Published var goals: [GoalDTO] = []
    @Published var pendingRevisions: [PlanRevisionDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var isOffline = false

    private let api: APIClient
    private let store: LocalStore

    init(api: APIClient? = nil, store: LocalStore? = nil) {
        self.api = api ?? .shared
        self.store = store ?? .shared
    }

    func load() async {
        // Offline-first: render the cache, then refresh.
        if goals.isEmpty {
            goals = store.cachedGoals()
        }

        isLoading = true
        defer { isLoading = false }

        do {
            async let goalsRequest = api.listGoals()
            async let revisionsRequest = api.pendingRevisions()

            goals = try await goalsRequest
            pendingRevisions = (try? await revisionsRequest) ?? []
            store.cacheGoals(goals)
            isOffline = false
            errorMessage = nil
        } catch let error as APIError {
            if case .transport = error {
                goals = store.cachedGoals()
                isOffline = true
                errorMessage = nil
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteGoal(_ goal: GoalDTO) async {
        do {
            try await api.deleteGoal(id: goal.id)
            goals.removeAll { $0.id == goal.id }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PlansView: View {
    @StateObject private var viewModel = PlansViewModel()
    @State private var showingCreateGoal = false
    @State private var selectedRevision: PlanRevisionDTO? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    SectionHeader("Plans", subtitle: "Goals, phases, and scheduled work")

                    if viewModel.isOffline {
                        OfflineBanner()
                    }

                    if let error = viewModel.errorMessage {
                        InlineErrorView(message: error)
                    }

                    if viewModel.isLoading && viewModel.goals.isEmpty {
                        ProgressView("Loading goals...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if viewModel.goals.isEmpty {
                        VStack(spacing: 16) {
                            ContentUnavailableView(
                                "No goals yet",
                                systemImage: "target",
                                description: Text("Create your first study goal.")
                            )
                            PrimaryButton("New Goal", systemImage: "plus") {
                                showingCreateGoal = true
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        VStack(spacing: Theme.Space.md) {
                            ForEach(viewModel.goals) { goal in
                                VStack(spacing: 0) {
                                    NavigationLink {
                                        GoalDetailView(goalID: goal.id)
                                    } label: {
                                        GoalRow(goal: goal)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            Task {
                                                await viewModel.deleteGoal(goal)
                                            }
                                        } label: {
                                            Label("Delete goal", systemImage: "trash")
                                        }
                                    }

                                    if let revision = viewModel.pendingRevisions.first(where: { $0.goalId == goal.id }) {
                                        RevisionBannerView(revision: revision) {
                                            selectedRevision = revision
                                        }
                                        .padding(.top, 8)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("Plans")
            .toolbar {
                Button {
                    showingCreateGoal = true
                } label: {
                    Label("New Goal", systemImage: "plus")
                }
            }
            .sheet(isPresented: $showingCreateGoal) {
                CreateGoalFlowView {
                    Task {
                        await viewModel.load()
                    }
                }
            }
            .sheet(item: $selectedRevision) { revision in
                RevisionDiffView(revision: revision) {
                    Task { await viewModel.load() }
                }
            }
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
        }
    }
}

private struct GoalRow: View {
    let goal: GoalDTO

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.title)
                            .font(Theme.sans(16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(goal.tag ?? goal.status.capitalized)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Text("\(goal.progress.pct)%")
                            .font(Theme.mono(13, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }

                PlanStarsRow(progress: goal.sessionStarProgress, compact: true)

                ProgressView(value: Double(goal.progress.pct), total: 100)
                    .tint(Theme.accent)

                HStack {
                    Text("\(goal.progress.doneMinutes)/\(goal.progress.totalMinutes) min")
                    Spacer()
                    if let days = goal.progress.daysLeft {
                        Text("\(days) days left")
                    }
                }
                .font(Theme.mono(12))
                .foregroundStyle(Theme.muted)
            }
        }
    }
}

private struct PlanStarsRow: View {
    let progress: PlanStarProgress
    var compact = false

    private var visibleStarCount: Int {
        min(max(progress.total, 1), compact ? 6 : 10)
    }

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: compact ? 3 : 4) {
                ForEach(0..<visibleStarCount, id: \.self) { index in
                    Image(systemName: index < progress.collected ? "star.fill" : "star")
                        .font(.system(size: compact ? 12 : 14, weight: .semibold))
                        .foregroundStyle(index < progress.collected ? Theme.prioMed : Theme.faint.opacity(0.72))
                }

                if progress.total > visibleStarCount {
                    Text("+\(progress.total - visibleStarCount)")
                        .font(Theme.mono(10, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }

            Text(progress.isComplete ? "Complete" : progress.displayText)
                .font(Theme.mono(compact ? 10.5 : 11.5, weight: .semibold))
                .foregroundStyle(progress.isComplete ? Theme.prioLow : Theme.prioMed)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 8 : 10)
        .background(Theme.surface2.opacity(0.78))
        .clipShape(.rect(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder((progress.isComplete ? Theme.prioLow : Theme.prioMed).opacity(0.18), lineWidth: 1)
        }
    }
}

#Preview {
    PlansView()
}
