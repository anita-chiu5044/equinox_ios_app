import SwiftUI

/// Bottom sheet for an adaptive suggestion (design: "Equinox Suggestion
/// Sheet"). Shows why, which sessions are affected, and the three choices —
/// suggest, never auto-apply.
struct SuggestionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let suggestion: SuggestionDTO
    let onPreview: (SuggestionOptionDTO) async -> SuggestionPreviewDTO?
    let onApply: (SuggestionOptionDTO, String?) async -> Bool

    @State private var respondingKey: String?
    @State private var selectedOption: SuggestionOptionDTO?
    @State private var preview: SuggestionPreviewDTO?
    @State private var rejectionReason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule()
                .fill(Theme.faint)
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Label("Suggestion", systemImage: "sparkles")
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .textCase(.uppercase)

                Text(suggestion.reason)
                    .font(Theme.serif(22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !suggestion.contextSessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Affected today")
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .textCase(.uppercase)

                    ForEach(suggestion.contextSessions) { session in
                        HStack(spacing: 10) {
                            if let time = session.time {
                                Text(time)
                                    .font(Theme.mono(12, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title)
                                    .font(Theme.sans(14, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                if let tag = session.tag {
                                    Text(tag)
                                        .font(Theme.mono(10))
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Theme.surface2)
                        .clipShape(.rect(cornerRadius: 10))
                    }
                }
            }

            if let preview, let option = selectedOption {
                previewView(preview, option: option)
            } else {
                VStack(spacing: 10) {
                    ForEach(suggestion.options) { option in
                        optionButton(option)
                    }
                }
            }

            Text("Your plan never changes without your say-so.")
                .font(Theme.sans(12))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private func optionButton(_ option: SuggestionOptionDTO) -> some View {
        let isPrimary = option.key == suggestion.options.first?.key
        let isResponding = respondingKey == option.key

        return Button {
            respondingKey = option.key
            Task {
                preview = await onPreview(option)
                selectedOption = preview == nil ? nil : option
                respondingKey = nil
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(option.label)
                        .font(Theme.sans(15, weight: .semibold))
                    Spacer()
                    if isResponding {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                if let detail = option.detail {
                    Text(detail)
                        .font(Theme.sans(12))
                        .foregroundStyle(isPrimary ? .white.opacity(0.85) : Theme.muted)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isPrimary ? .white : Theme.ink)
        .background(isPrimary ? Theme.accent : Theme.surface2)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isPrimary ? .clear : Theme.faint, lineWidth: 1)
        )
        .disabled(respondingKey != nil)
        .accessibilityLabel("\(option.label). \(option.detail ?? "")")
    }

    private func previewView(_ preview: SuggestionPreviewDTO, option: SuggestionOptionDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(preview.feasible ? "Review proposed changes" : "This adjustment cannot be applied")
                .font(Theme.sans(16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            if let reason = preview.reason {
                Text(reason).font(Theme.sans(13)).foregroundStyle(Theme.muted)
            }
            ForEach(preview.changes, id: \.self) { change in
                Label(change, systemImage: "arrow.right.circle")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.inkSoft)
            }
            if !preview.affectedSessions.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Time impact")
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .textCase(.uppercase)
                    Text("\(preview.totalMinutesBefore) min → \(preview.totalMinutesAfter) min")
                        .font(Theme.sans(14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    ForEach(preview.affectedSessions) { impact in
                        Text("\(impact.title): \(timeText(impact.before)) → \(timeText(impact.after))")
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .padding(12)
                .background(Theme.surface2)
                .clipShape(.rect(cornerRadius: 10))
            }
            if option.key == "keep" {
                TextField("Why keep the plan? (optional)", text: $rejectionReason, axis: .vertical)
                    .font(Theme.sans(13))
                    .textFieldStyle(.roundedBorder)
            }
            if preview.feasible {
                PrimaryButton("Apply changes", systemImage: "checkmark.circle.fill", isLoading: respondingKey == option.key) {
                    respondingKey = option.key
                    Task {
                        let reason = rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines)
                        if await onApply(option, reason.isEmpty ? nil : reason) { dismiss() }
                        respondingKey = nil
                    }
                }
            }
            Button("Back") {
                self.preview = nil
                selectedOption = nil
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
        }
    }

    private func timeText(_ timing: SuggestionTimingDTO) -> String {
        let start = timing.start?.split(separator: "T").last.map(String.init) ?? "Unscheduled"
        let end = timing.end?.split(separator: "T").last.map(String.init) ?? "—"
        return "\(start)–\(end) (\(timing.minutes) min)"
    }
}
