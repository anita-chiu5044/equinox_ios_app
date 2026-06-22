import SwiftUI
import Combine

@MainActor
final class RevisionDiffViewModel: ObservableObject {
    @Published var revision: PlanRevisionDTO
    @Published var isApplying = false
    @Published var isRejecting = false
    @Published var appliedSuccessfully = false
    @Published var errorMessage: String?

    private let api: APIClient

    init(revision: PlanRevisionDTO, api: APIClient = .shared) {
        self.revision = revision
        self.api = api
    }

    func accept() async {
        isApplying = true
        defer { isApplying = false }
        do {
            revision = try await api.respondToRevision(id: revision.id, action: "accept")
            appliedSuccessfully = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reject(reason: String?) async {
        isRejecting = true
        defer { isRejecting = false }
        do {
            revision = try await api.respondToRevision(id: revision.id, action: "reject", rejectionReason: reason)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestEdit() async {
        do {
            revision = try await api.respondToRevision(id: revision.id, action: "edit")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RevisionDiffView: View {
    @StateObject private var vm: RevisionDiffViewModel
    @Environment(\.dismiss) private var dismiss
    let onAccepted: () -> Void

    init(revision: PlanRevisionDTO, onAccepted: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: RevisionDiffViewModel(revision: revision))
        self.onAccepted = onAccepted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    aiSourcePill
                    if let diff = vm.revision.diff {
                        metricsRow(diff)
                        diffSections(diff)
                    } else {
                        Text("Generating proposal…")
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    }
                    if let error = vm.errorMessage {
                        Text(error)
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.prioHigh)
                            .padding(12)
                            .background(Theme.prioHigh.opacity(0.08))
                            .clipShape(.rect(cornerRadius: 10))
                    }
                    Spacer().frame(height: 20)
                }
                .padding(20)
            }
            .background(Theme.paper)
            .safeAreaInset(edge: .bottom) {
                actionButtons
                    .padding(20)
                    .background(.ultraThinMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.muted)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: vm.appliedSuccessfully) { _, applied in
            if applied {
                onAccepted()
                dismiss()
            }
        }
        .onChange(of: vm.revision.status) { _, status in
            if status == "rejected" { dismiss() }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PLAN REVISION")
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Text(triggerTitle)
                .font(Theme.serif(26))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !vm.revision.triggerDetail.isEmpty {
                Text(vm.revision.triggerDetail)
                    .font(Theme.sans(14))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var aiSourcePill: some View {
        HStack(spacing: 6) {
            Image(systemName: vm.revision.aiDraft?.source == "apple_intelligence" ? "apple.logo" : "cloud")
                .font(.system(size: 11))
            Text(vm.revision.aiDraft?.source == "apple_intelligence" ? "Apple Intelligence" : "Equinox Cloud")
                .font(Theme.mono(11))
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.bgWarm)
        .clipShape(.capsule)
    }

    private var triggerTitle: String {
        switch vm.revision.trigger {
        case "energy_high_difficulty": return "Low energy ahead"
        case "slow_sessions": return "Sessions running long"
        case "overdue": return "Sessions slipping"
        case "low_familiarity": return "Material not sticking"
        case "deadline_infeasible": return "Deadline at risk"
        case "manual": return "Requested recheck"
        default: return "Plan update suggested"
        }
    }

    private func metricsRow(_ diff: RevisionDiffDTO) -> some View {
        HStack(spacing: 0) {
            metricCell(label: "Sessions", before: diff.totalBefore, after: diff.totalAfter)
            Divider().frame(height: 36)
            metricCell(label: "Minutes", before: diff.minutesBefore, after: diff.minutesAfter)
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line2, lineWidth: 1))
    }

    private func metricCell(label: String, before: Int, after: Int) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                Text("\(before)")
                    .font(Theme.serif(20))
                    .foregroundStyle(Theme.inkSoft)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.faint)
                Text("\(after)")
                    .font(Theme.serif(20, weight: .semibold))
                    .foregroundStyle(after < before ? Theme.prioLow : Theme.ink)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func diffSections(_ diff: RevisionDiffDTO) -> some View {
        if !diff.added.isEmpty {
            diffSection(title: "Added", color: Theme.prioLow, icon: "plus.circle.fill",
                       sessions: diff.added.map { ($0.title, $0.minutes, false) })
        }
        if !diff.removed.isEmpty {
            diffSection(title: "Removed", color: Theme.prioHigh, icon: "minus.circle.fill",
                       sessions: diff.removed.map { ($0.title, $0.minutes, true) })
        }
        if !diff.modified.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Modified", systemImage: "pencil.circle.fill")
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                ForEach(diff.modified, id: \.title) { mod in
                    HStack {
                        Text(mod.title)
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(mod.minutesBefore)→\(mod.minutesAfter) min")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.bgWarm)
                    .clipShape(.rect(cornerRadius: 8))
                }
            }
        }
        if !diff.preservedDone.isEmpty {
            diffSection(title: "Kept (already done)", color: Theme.faint, icon: "checkmark.circle.fill",
                       sessions: diff.preservedDone.map { ($0.title, $0.minutes, false) })
        }
    }

    private func diffSection(title: String, color: Color, icon: String, sessions: [(String, Int, Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(Theme.sans(13, weight: .semibold))
                .foregroundStyle(color)
            ForEach(sessions, id: \.0) { name, minutes, struck in
                HStack {
                    Text(name)
                        .font(Theme.sans(13))
                        .foregroundStyle(struck ? Theme.faint : Theme.ink)
                        .strikethrough(struck, color: Theme.faint)
                    Spacer()
                    Text("\(minutes) min")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(color.opacity(0.07))
                .clipShape(.rect(cornerRadius: 8))
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                Task { await vm.accept() }
            } label: {
                HStack {
                    if vm.isApplying { ProgressView().tint(.white) }
                    else { Label("Accept changes", systemImage: "checkmark") }
                }
                .font(Theme.sans(16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(vm.revision.diff == nil ? Theme.faint : Theme.accent)
            .clipShape(.rect(cornerRadius: 14))
            .disabled(vm.isApplying || vm.revision.diff == nil)

            Button {
                Task { await vm.requestEdit() }
            } label: {
                Label("Edit proposal", systemImage: "pencil")
                    .font(Theme.sans(15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .background(Theme.accentWash)
            .clipShape(.rect(cornerRadius: 14))
            .disabled(vm.isApplying)

            Button {
                Task { await vm.reject(reason: "Kept original plan") }
            } label: {
                if vm.isRejecting { ProgressView() }
                else {
                    Text("Keep original")
                        .font(Theme.sans(15))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .disabled(vm.isRejecting)
        }
    }
}
