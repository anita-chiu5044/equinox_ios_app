import SwiftUI

/// Step 4 — show where sessions landed in the week, then confirm.
struct SchedulePreviewStepView: View {
    @ObservedObject var viewModel: CreateGoalFlowViewModel
    let onDone: () -> Void

    private static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error = viewModel.errorMessage {
                    InlineErrorView(message: error)
                }

                if let preview = viewModel.schedulePreview {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SCHEDULE PREVIEW")
                            .font(Theme.mono(11, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                        Text("Week of \(preview.weekStart)")
                            .font(Theme.serif(26))
                            .foregroundStyle(Theme.ink)
                    }

                    // Week calendar grid
                    weekGrid(preview: preview)

                    if preview.placed.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.system(size: 36))
                                .foregroundStyle(Theme.faint)
                            Text("All sessions are already scheduled")
                                .font(Theme.serif(18))
                                .foregroundStyle(Theme.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else {
                        // Day-by-day detail
                        VStack(spacing: 12) {
                            ForEach(0..<7, id: \.self) { day in
                                daySection(day, preview: preview)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Placing sessions in your calendar…")
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }
            }
            .padding(20)
            .padding(.bottom, 110)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(
                "Confirm schedule",
                systemImage: "checkmark.circle.fill",
                isLoading: viewModel.isWorking
            ) {
                Task {
                    if await viewModel.confirmSchedule() {
                        onDone()
                    }
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: Week calendar grid (7 columns, dots per session)

    private func weekGrid(preview: SchedulePreviewDTO) -> some View {
        VStack(spacing: 6) {
            // Day header row
            HStack(spacing: 0) {
                ForEach(Array(Self.dayNames.enumerated()), id: \.offset) { idx, name in
                    Text(name)
                        .font(Theme.mono(10, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                }
            }

            // Dots row (session count indicators)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { day in
                    let placedCount = preview.placed.filter { $0.day == day }.count
                    let hasGhosts   = !preview.ghosts.filter { $0.day == day }.isEmpty

                    VStack(spacing: 4) {
                        // Session dots (accent, max 4 shown)
                        HStack(spacing: 3) {
                            ForEach(0..<min(placedCount, 4), id: \.self) { _ in
                                Circle()
                                    .fill(Theme.accent)
                                    .frame(width: 6, height: 6)
                            }
                            if placedCount > 4 {
                                Text("+")
                                    .font(Theme.mono(8))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .frame(height: 10)

                        // Ghost indicator (busy slot)
                        if hasGhosts {
                            Rectangle()
                                .fill(Theme.faint.opacity(0.5))
                                .frame(height: 3)
                                .clipShape(.capsule)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        placedCount > 0
                            ? Theme.accentWash.opacity(0.7)
                            : Theme.surface.opacity(0.4)
                    )
                    .clipShape(.rect(cornerRadius: 8))
                    .padding(2)
                }
            }

            // Summary
            let total = preview.placed.count
            let days  = (0..<7).filter { day in !preview.placed.filter { $0.day == day }.isEmpty }.count
            Text("\(total) sessions across \(days) days")
                .font(Theme.sans(12))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.line2, lineWidth: 1)
        )
    }

    // MARK: Per-day detail section

    @ViewBuilder
    private func daySection(_ day: Int, preview: SchedulePreviewDTO) -> some View {
        let ghosts = preview.ghosts.filter { $0.day == day }
        let placed = preview.placed.filter { $0.day == day }

        if !ghosts.isEmpty || !placed.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(Self.dayNames[min(max(day, 0), 6)])
                    .font(Theme.serif(17, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                ForEach(ghosts) { ghost in
                    HStack {
                        Text(ghost.label)
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Text("\(ghost.start)–\(ghost.end)")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.faint)
                    }
                    .padding(10)
                    .background(Theme.surface.opacity(0.6))
                    .clipShape(.rect(cornerRadius: 8))
                    .accessibilityLabel("Busy: \(ghost.label), \(ghost.start) to \(ghost.end)")
                }

                ForEach(placed) { item in
                    HStack {
                        Text(item.emoji ?? "📖")
                            .accessibilityHidden(true)
                        Text(item.label)
                            .font(Theme.sans(13, weight: .semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text("\(item.start)–\(item.end)")
                            .font(Theme.mono(11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(10)
                    .background(Theme.accent)
                    .clipShape(.rect(cornerRadius: 8))
                    .accessibilityLabel("Study session: \(item.label), \(item.start) to \(item.end)")
                    if let reason = item.personalizationReason {
                        Label(reason, systemImage: "person.crop.circle.badge.checkmark")
                            .font(Theme.sans(11))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }
}
