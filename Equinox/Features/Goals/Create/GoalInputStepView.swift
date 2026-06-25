import SwiftUI
import UniformTypeIdentifiers

/// Step 1 — Goal input, styled to match the design (serif large input, custom fields).
struct GoalInputStepView: View {
    @ObservedObject var viewModel: CreateGoalFlowViewModel
    @State private var showingImporter = false
    @FocusState private var focusedField: Field?

    private enum Field { case title, tag, sourceText }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Goal field — serif large, accent underline ──
                VStack(alignment: .leading, spacing: 8) {
                    Text("What are you working toward?")
                        .font(Theme.mono(10.5, weight: .semibold))
                        .foregroundStyle(focusedField == .title ? Theme.accentDeep : Theme.inkSoft)
                        .kerning(1.4)
                        .textCase(.uppercase)

                    TextField(
                        "",
                        text: $viewModel.title,
                        prompt: Text("Name your goal")
                            .foregroundStyle(Theme.inkSoft.opacity(0.82)),
                        axis: .vertical
                    )
                        .font(Theme.TextStyle.display)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1...4)
                        .focused($focusedField, equals: .title)
                        .accessibilityLabel("Goal title")

                    // accent gradient underline
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent, Theme.accentSoft, Theme.accentSoft.opacity(0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 2)
                        .frame(maxWidth: viewModel.title.isEmpty ? 80 : .infinity, alignment: .leading)
                        .animation(.easeOut(duration: 0.3), value: viewModel.title.isEmpty)
                        .clipShape(.rect(cornerRadius: 2))
                }
                .padding(.top, 8)

                // ── Tag ──
                styledField(
                    label: "Tag (optional)",
                    placeholder: "e.g. Organic Chemistry",
                    text: $viewModel.tag,
                    field: .tag
                )
                .padding(.top, 28)

                // ── Deadline ──
                VStack(alignment: .leading, spacing: 10) {
                    Text("Deadline")
                        .font(Theme.mono(10.5, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .kerning(1.4)
                        .textCase(.uppercase)

                    Toggle(isOn: $viewModel.hasDeadline) {
                        Text("Use deadline")
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .tint(Theme.accent)

                    if viewModel.hasDeadline {
                        DatePicker(
                            "Deadline",
                            selection: $viewModel.deadline,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .font(Theme.sans(14))
                        .tint(Theme.accent)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.top, 28)
                .animation(.easeOut(duration: 0.25), value: viewModel.hasDeadline)

                // ── Material attachment ──
                VStack(alignment: .leading, spacing: 10) {
                    Text("Material")
                        .font(Theme.mono(10.5, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .kerning(1.4)
                        .textCase(.uppercase)

                    if let material = viewModel.uploadedMaterial {
                        HStack(spacing: 12) {
                            Image(systemName: material.type == "pdf" ? "doc.fill" : "photo.fill")
                                .foregroundStyle(Theme.accent)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(material.name)
                                    .font(Theme.sans(14, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Text(ByteCountFormatter.string(
                                    fromByteCount: Int64(material.sizeBytes),
                                    countStyle: .file
                                ))
                                .font(Theme.mono(11))
                                .foregroundStyle(Theme.muted)
                                if material.extractionStatus == "failed", let detail = material.extractionError {
                                    Text(detail)
                                        .font(Theme.sans(11))
                                        .foregroundStyle(Theme.accent)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else if material.extractionStatus == "ready" {
                                    Label("Text ready for planning", systemImage: "checkmark.circle.fill")
                                        .font(Theme.sans(11))
                                        .foregroundStyle(Theme.prioLow)
                                }
                            }

                            Spacer()

                            Button(role: .destructive) {
                                Task { await viewModel.removeMaterial() }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(Theme.muted)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove material")
                        }
                        .padding(14)
                        .background(Theme.bgWarm)
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1)
                        }
                    } else {
                        Button {
                            showingImporter = true
                        } label: {
                            Label(
                                viewModel.isUploadingMaterial ? "Uploading…" : "Attach syllabus or notes",
                                systemImage: "paperclip"
                            )
                            .font(Theme.sans(14, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                        .background(Theme.bgWarm)
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1)
                        }
                        .disabled(viewModel.isUploadingMaterial)
                    }

                    Text("Text PDFs are parsed securely by Equinox. For scanned files, paste any goal context or notes below.")
                        .font(Theme.sans(11.5))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 28)

                // ── Goal and notes ──
                VStack(alignment: .leading, spacing: 10) {
                    Text("Goal and notes (optional)")
                        .font(Theme.mono(10.5, weight: .semibold))
                        .foregroundStyle(focusedField == .sourceText ? Theme.accentDeep : Theme.muted)
                        .kerning(1.4)
                        .textCase(.uppercase)

                    TextEditor(text: $viewModel.sourceText)
                        .font(Theme.sans(14))
                        .foregroundStyle(Theme.ink)
                        .focused($focusedField, equals: .sourceText)
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                        .padding(14)
                        .background(Theme.surface)
                        .clipShape(.rect(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    focusedField == .sourceText ? Theme.accent : Theme.line,
                                    lineWidth: focusedField == .sourceText ? 1.5 : 1
                                )
                        }
                        .shadow(
                            color: focusedField == .sourceText ? Theme.accentWash : .clear,
                            radius: 6, x: 0, y: 0
                        )
                        .animation(.easeOut(duration: 0.15), value: focusedField == .sourceText)
                        .accessibilityLabel("Goal and notes")

                    Text("Paste an outline, syllabus, scanned PDF text, or notes so the plan can use the actual material.")
                        .font(Theme.sans(11.5))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 28)

                // ── Error ──
                if let error = viewModel.errorMessage {
                    InlineErrorView(message: error)
                        .padding(.top, 20)
                }

                // ── CTA ──
                PrimaryButton("Draft my plan", systemImage: "sparkles", isLoading: viewModel.isUploadingMaterial) {
                    Task { await viewModel.start() }
                }
                .disabled(viewModel.trimmedTitle.isEmpty || viewModel.isUploadingMaterial)
                .opacity(viewModel.trimmedTitle.isEmpty ? 0.5 : 1)
                .accessibilityHint("Generates a study plan from your goal")
                .padding(.top, 32)
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
        }
        .background(Theme.bg)
        .scrollDismissesKeyboard(.interactively)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.pdf, .png, .jpeg, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await viewModel.attachMaterial(at: url) }
            }
        }
    }

    // MARK: Reusable focused-ring text field

    private func styledField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Theme.mono(10.5, weight: .semibold))
                .foregroundStyle(focusedField == field ? Theme.accentDeep : Theme.muted)
                .kerning(1.4)
                .textCase(.uppercase)

            TextField(placeholder, text: text)
                .font(Theme.sans(14.5))
                .foregroundStyle(Theme.ink)
                .focused($focusedField, equals: field)
                .padding(.horizontal, 15)
                .padding(.vertical, 14)
                .background(Theme.surface)
                .clipShape(.rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            focusedField == field ? Theme.accent : Theme.line,
                            lineWidth: focusedField == field ? 1.5 : 1
                        )
                }
                .shadow(
                    color: focusedField == field ? Theme.accentWash : .clear,
                    radius: 6, x: 0, y: 0
                )
                .animation(.easeOut(duration: 0.15), value: focusedField == field)
        }
    }
}
