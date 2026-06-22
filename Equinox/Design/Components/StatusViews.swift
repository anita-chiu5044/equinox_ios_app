import SwiftUI

struct InlineErrorView: View {
    let message: String
    var onRetry: (() -> Void)?

    init(message: String, onRetry: (() -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(Theme.sans(13))
                .foregroundStyle(Theme.prioHigh)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let onRetry {
                Button("Retry", action: onRetry)
                    .font(Theme.sans(13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(12)
        .background(Theme.surface2)
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

/// Shown when rendering from the local cache without connectivity.
struct OfflineBanner: View {
    var body: some View {
        Label("Offline — showing saved data. Changes will sync when you're back online.", systemImage: "wifi.slash")
            .font(Theme.sans(12, weight: .semibold))
            .foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.surface2)
            .clipShape(.rect(cornerRadius: 8))
            .accessibilityLabel("Offline. Showing saved data. Changes will sync when you're back online.")
    }
}

/// Consistent loading state used across screens.
struct LoadingStateView: View {
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(title)
                .font(Theme.sans(14))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
