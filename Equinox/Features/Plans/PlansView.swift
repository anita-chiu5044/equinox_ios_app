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
            pendingRevisions.removeAll { $0.goalId == goal.id }
            store.removeGoal(id: goal.id)
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
    @State private var goalPendingDeletion: GoalDTO? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    HStack(alignment: .top, spacing: 12) {
                        SectionHeader("Plans", subtitle: "Goals, phases, and scheduled work")

                        if !viewModel.goals.isEmpty {
                            NewGoalMiniButton {
                                showingCreateGoal = true
                            }
                        }
                    }

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
                        VStack(spacing: 18) {
                            EmptyPlansView()
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
                                    ZStack(alignment: .topTrailing) {
                                        NavigationLink {
                                            GoalDetailView(goalID: goal.id) {
                                                Task {
                                                    await viewModel.load()
                                                }
                                            }
                                        } label: {
                                            GoalRow(goal: goal)
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            goalPendingDeletion = goal
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(Color.red.opacity(0.72))
                                                .frame(width: 34, height: 34)
                                                .background(Theme.surface2.opacity(0.92))
                                                .clipShape(Circle())
                                                .overlay {
                                                    Circle()
                                                        .strokeBorder(Color.red.opacity(0.14), lineWidth: 1)
                                                }
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 12)
                                        .padding(.trailing, 12)
                                        .accessibilityLabel("Delete plan")
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            goalPendingDeletion = goal
                                        } label: {
                                            Label("Delete plan", systemImage: "trash")
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
            .platformHideNavigationBarToolbar()
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
            .alert("Delete plan?", isPresented: deleteAlertBinding) {
                Button("Delete", role: .destructive) {
                    guard let goal = goalPendingDeletion else {
                        return
                    }
                    Task {
                        await viewModel.deleteGoal(goal)
                        goalPendingDeletion = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    goalPendingDeletion = nil
                }
            } message: {
                Text("This removes the plan and its sessions from Equinox. This cannot be undone.")
            }
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { goalPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    goalPendingDeletion = nil
                }
            }
        )
    }
}

private struct NewGoalMiniButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                Text("New Goal")
                    .font(Theme.sans(13, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.accent)
            .clipShape(.capsule)
            .shadow(color: Theme.accentDeep.opacity(0.28), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New Goal")
    }
}

private struct EmptyPlansView: View {
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.accentWash)
                    .frame(width: 62, height: 62)
                Image(systemName: "target")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            Text("No goals yet")
                .font(Theme.serif(28, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)

            Text("Create your first study goal.")
                .font(Theme.sans(15, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 18)
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.accentRing, lineWidth: 1)
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
                            .font(Theme.sans(17, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .padding(.trailing, 48)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(goal.tag ?? goal.status.capitalized)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
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
