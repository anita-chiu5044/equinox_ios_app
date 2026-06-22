import SwiftUI

/// Captures the two feedback signals needed for continual learning before a
/// completed session is sent to the backend.
struct CompletionFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: SessionDTO
    let onSubmit: (Int, Int) async -> Void

    @State private var actualMinutes: Int
    @State private var familiarity = 3
    @State private var isSubmitting = false

    init(session: SessionDTO, onSubmit: @escaping (Int, Int) async -> Void) {
        self.session = session
        self.onSubmit = onSubmit
        _actualMinutes = State(initialValue: session.minutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Actual time") {
                    Stepper("\(actualMinutes) minutes", value: $actualMinutes, in: 5...360, step: 5)
                }
                Section("How familiar do you feel?") {
                    Picker("Familiarity", selection: $familiarity) {
                        Text("1 · No real grasp").tag(1)
                        Text("2 · Recognize it").tag(2)
                        Text("3 · Can work through it").tag(3)
                        Text("4 · I could teach it").tag(4)
                    }
                    .pickerStyle(.inline)
                }
                Section("Why we ask") {
                    Text("Equinox uses your real pace and familiarity to make future plans more realistic.")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.muted)
                }
            }
            .navigationTitle("Session feedback")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSubmitting = true
                        Task {
                            await onSubmit(actualMinutes, familiarity)
                            isSubmitting = false
                            dismiss()
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }
}
