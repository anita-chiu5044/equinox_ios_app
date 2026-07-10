import SwiftUI

extension View {
    @ViewBuilder
    func platformInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformNavigationBarHidden(_ hidden: Bool = true) -> some View {
        #if os(iOS)
        navigationBarHidden(hidden)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformHideNavigationBarToolbar() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformWordsAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.words)
        #else
        self
        #endif
    }
}
