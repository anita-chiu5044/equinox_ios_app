import SwiftUI

/// Step 3 — review and edit the drafted sessions before scheduling.
struct PlanReviewStepView: View {
    @ObservedObject var viewModel: CreateGoalFlowViewModel
    @State private var editingSession: SessionDTO?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let origin = viewModel.planOrigin {
                    Label(origin.rawValue, systemImage: origin == .appleIntelligence ? "sparkles" : "cloud")
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }

                if let error = viewModel.errorMessage {
                    InlineErrorView(message: error)
                }

                if let goal = viewModel.goal {
                    Text("Check the breakdown — tap a session to adjust it.")
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.inkSoft)

                    ForEach(goal.phases.sorted(by: { $0.order < $1.order })) { phase in
                        if !phase.sessions.isEmpty {
                            SectionHeader(phase.name, subtitle: "\(phase.sessions.count) sessions")
                                .padding(.top, 6)

                            ForEach(phase.sessions) { session in
                                Button {
                                    editingSession = session
                                } label: {
                                    sessionRow(session)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Edit this session")
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Plan unavailable", systemImage: "sparkles")
                }
            }
            .padding(20)
            .padding(.bottom, 110)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(
                "Looks good — schedule it",
                systemImage: "calendar.badge.plus",
                isLoading: viewModel.isWorking
            ) {
                Task {
                    await viewModel.runScheduler()
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
        }
        .sheet(item: $editingSession) { session in
            SessionEditSheet(session: session) { request in
                await viewModel.updateSession(session, request: request)
            } onDelete: {
                await viewModel.deleteSession(session)
            }
        }
    }

    private func sessionRow(_ session: SessionDTO) -> some View {
        Card {
            HStack(spacing: 12) {
                Text(session.emoji ?? "📖")
                    .font(.title3)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(session.title)
                        .font(Theme.sans(15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 10) {
                        Text("\(session.minutes) min")
                        Text("difficulty \(session.difficulty)")
                    }
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.muted)
                }

                Spacer()

                PriorityPill(priority: session.priority)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.faint)
            }
        }
    }
}

// MARK: - Session edit sheet

struct SessionEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let session: SessionDTO
    let onSave: (SessionUpdateRequest) async -> Void
    let onDelete: () async -> Void

    @State private var title: String
    @State private var minutes: Int
    @State private var priority: String
    @State private var difficulty: Int
    @State private var isSaving = false

    init(
        session: SessionDTO,
        onSave: @escaping (SessionUpdateRequest) async -> Void,
        onDelete: @escaping () async -> Void
    ) {
        self.session = session
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: session.title)
        _minutes = State(initialValue: session.minutes)
        _priority = State(initialValue: session.priority)
        _difficulty = State(initialValue: session.difficulty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Title", text: $title)
                    Stepper("\(minutes) minutes", value: $minutes, in: 10...180, step: 5)
                    Picker("Priority", selection: $priority) {
                        Text("Low").tag("low")
                        Text("Medium").tag("med")
                        Text("High").tag("high")
                    }
                    Stepper("Difficulty \(difficulty)", value: $difficulty, in: 1...5)
                }

                Section {
                    Button("Remove session", role: .destructive) {
                        Task {
                            await onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        isSaving = true
                        Task {
                            await onSave(SessionUpdateRequest(
                                title: title == session.title ? nil : title,
                                emoji: nil,
                                priority: priority == session.priority ? nil : priority,
                                difficulty: difficulty == session.difficulty ? nil : difficulty,
                                minutes: minutes == session.minutes ? nil : minutes,
                                status: nil,
                                actualMinutes: nil,
                                familiarity: nil,
                                scheduledStart: nil,
                                scheduledEnd: nil
                            ))
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
