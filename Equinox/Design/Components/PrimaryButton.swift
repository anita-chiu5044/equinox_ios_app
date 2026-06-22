import SwiftUI

struct PrimaryButton: View {
    let title: String
    let systemImage: String?
    let isLoading: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(Theme.sans(15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Theme.accent)
        .clipShape(.rect(cornerRadius: 14))
        .shadow(color: Theme.accentRing, radius: 11, x: 0, y: 5)
        .disabled(isLoading)
        .opacity(isLoading ? 0.75 : 1)
    }
}
