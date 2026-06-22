import SwiftUI

struct Card<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.lg)
            .background(Theme.surface)
            .clipShape(.rect(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(Theme.line2, lineWidth: 1)
            }
            // Two-layer warm shadow (e1): crisp contact + soft lift.
            .shadow(color: Theme.shadowInk.opacity(0.04), radius: 1, x: 0, y: 1)
            .shadow(color: Theme.shadowInk.opacity(0.16), radius: 18, x: 0, y: 12)
    }
}
