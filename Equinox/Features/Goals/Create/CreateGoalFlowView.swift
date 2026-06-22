import SwiftUI
import Combine

// MARK: - Flow view model

@MainActor
final class CreateGoalFlowViewModel: ObservableObject {
    enum Step: Equatable {
        case input
        case thinking
        case review
        case schedule
    }

    // Flow
    @Published var step: Step = .input
    @Published var isWorking = false
    @Published var errorMessage: String?

    // Input
    @Published var title = ""
    @Published var tag = ""
    @Published var sourceText = ""
    @Published var hasDeadline = true
    @Published var deadline = Date(timeIntervalSinceNow: 14 * 24 * 60 * 60)
    @Published var uploadedMaterial: MaterialDTO?
    @Published var isUploadingMaterial = false
    private var materialSummary: String?

    // Output
    @Published var goal: GoalDTO?
    @Published var planOrigin: PlanOrigin?
    @Published var schedulePreview: SchedulePreviewDTO?
    @Published var thinkingDetail = "Reading your goal..."

    private let api: APIClient
    private let planner = PlannerCoordinator()

    init(api: APIClient? = nil) {
        self.api = api ?? .shared
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Materials

    func attachMaterial(at url: URL) async {
        isUploadingMaterial = true
        defer { isUploadingMaterial = false }

        materialSummary = MaterialTextExtractor.summary(from: url)

        do {
            let needsScopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if needsScopedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            uploadedMaterial = try await api.uploadMaterial(filename: url.lastPathComponent, data: data)
            errorMessage = nil
        } catch {
            errorMessage = "Could not attach material: \(error.localizedDescription)"
        }
    }

    func removeMaterial() async {
        guard let material = uploadedMaterial else {
            return
        }
        uploadedMaterial = nil
        materialSummary = nil
        try? await api.deleteMaterial(id: material.id)
    }

    // MARK: Create + decompose

    func start() async {
        guard !trimmedTitle.isEmpty else {
            return
        }

        step = .thinking
        isWorking = true
        defer { isWorking = false }

        do {
            // 1. Generate locally before any goal data reaches the backend.
            thinkingDetail = OnDevicePlanner.isAvailable
                ? "Planning with Apple Intelligence..."
                : "Creating a private on-device template..."
            let profile = try? await api.learningProfile()
            guard let result = await planner.makePlan(
                title: trimmedTitle,
                deadline: hasDeadline ? deadline : nil,
                materialSummary: materialSummary,
                personalLearningContext: profile?.promptContext
            ) else { throw PlannerError.emptyPlan }

            // 2. Persist the locally generated sessions.  The backend only
            // validates, stores, and deterministically schedules them.
            thinkingDetail = "Saving your private plan..."
            let created = try await api.createGoal(
                title: trimmedTitle,
                deadline: hasDeadline ? deadline : nil,
                tag: tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : tag,
                materialIds: uploadedMaterial.map { [$0.id] } ?? [],
                sourceText: sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : sourceText,
                generatedPhases: result.plan.goalCreatePhases
            )
            planOrigin = result.origin

            goal = created
            errorMessage = nil
            step = .review
        } catch {
            errorMessage = error.localizedDescription
            step = .input
        }
    }

    /// Swap the server's draft sessions for the locally generated plan,
    /// reusing the server's phase records (mapped by order).
    private func replaceDraftSessions(of goal: GoalDTO, with plan: GeneratedPlan) async -> GoalDTO {
        let phases = goal.phases.sorted { $0.order < $1.order }
        guard !phases.isEmpty else {
            return goal
        }

        do {
            for phase in phases {
                for session in phase.sessions where session.status != "done" {
                    try await api.deleteSession(id: session.id)
                }
            }

            for (index, generatedPhase) in plan.phases.enumerated() {
                let phaseID = phases[min(index, phases.count - 1)].id
                for session in generatedPhase.sessions {
                    _ = try await api.addSession(
                        goalID: goal.id,
                        request: SessionCreateRequest(
                            title: session.title,
                            emoji: session.emoji,
                            priority: session.priority,
                            difficulty: session.difficulty,
                            minutes: session.minutes,
                            phaseId: phaseID
                        )
                    )
                }
            }

            return try await api.goal(id: goal.id)
        } catch {
            // Keep the server plan if the swap fails part-way.
            return (try? await api.goal(id: goal.id)) ?? goal
        }
    }

    // MARK: Review edits

    func updateSession(_ session: SessionDTO, request: SessionUpdateRequest) async {
        guard let goal else {
            return
        }
        do {
            _ = try await api.updateSession(id: session.id, request: request)
            self.goal = try await api.goal(id: goal.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSession(_ session: SessionDTO) async {
        guard let goal else {
            return
        }
        do {
            try await api.deleteSession(id: session.id)
            self.goal = try await api.goal(id: goal.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Scheduling

    func runScheduler() async {
        guard let goal else {
            return
        }
        isWorking = true
        defer { isWorking = false }

        do {
            schedulePreview = try await api.scheduleGoal(id: goal.id)
            errorMessage = nil
            step = .schedule
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmSchedule() async -> Bool {
        guard let goal else {
            return false
        }
        isWorking = true
        defer { isWorking = false }

        do {
            schedulePreview = try await api.confirmSchedule(goalID: goal.id)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

// MARK: - Flow container

struct CreateGoalFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CreateGoalFlowViewModel()

    /// Called after the flow completes so the Plans list can refresh.
    var onFinished: () -> Void = {}

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .input:
                    GoalInputStepView(viewModel: viewModel)
                case .thinking:
                    ThinkingStepView(viewModel: viewModel)
                case .review:
                    PlanReviewStepView(viewModel: viewModel)
                case .schedule:
                    SchedulePreviewStepView(viewModel: viewModel) {
                        onFinished()
                        dismiss()
                    }
                }
            }
            .background(Theme.paper)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.step == .input {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
            .interactiveDismissDisabled(viewModel.step == .thinking)
        }
    }

    private var navigationTitle: String {
        switch viewModel.step {
        case .input: "New Goal"
        case .thinking: "Planning"
        case .review: "Review Plan"
        case .schedule: "Schedule"
        }
    }
}

#Preview {
    CreateGoalFlowView()
}
