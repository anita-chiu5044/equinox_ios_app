import SwiftUI
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: SettingsDTO?
    @Published var connections: ConnectionsDTO?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api: APIClient

    init(api: APIClient? = nil) {
        self.api = api ?? .shared
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let settings = api.settings()
            async let connections = api.connections()
            self.settings = try await settings
            self.connections = try await connections
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateSettings(
        suggestionsEnabled: Bool? = nil,
        dailyCheckinEnabled: Bool? = nil,
        suggestionMode: String? = nil,
        showCalendarEventTitles: Bool? = nil
    ) async {
        do {
            settings = try await api.updateSettings(
                SettingsUpdateRequest(
                    suggestionsEnabled: suggestionsEnabled,
                    dailyCheckinEnabled: dailyCheckinEnabled,
                    suggestionMode: suggestionMode,
                    showCalendarEventTitles: showCalendarEventTitles
                )
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setGoogleCalendarConnected(_ connected: Bool) async {
        do {
            if connected {
                if GoogleOAuthService.isConfigured {
                    let auth = try await GoogleOAuthService.shared.authorizeCalendar()
                    _ = try await api.connectGoogleCalendar(
                        GoogleCalendarConnectRequest(
                            code: auth.code,
                            codeVerifier: auth.codeVerifier,
                            redirectURI: auth.redirectURI
                        )
                    )
                } else {
                    _ = try await api.connectGoogleCalendar()
                }
            } else {
                try await api.disconnectGoogleCalendar()
            }
            connections = try await api.connections()
            errorMessage = nil
        } catch GoogleOAuthService.OAuthError.cancelled {
            connections = try? await api.connections()
        } catch {
            errorMessage = error.localizedDescription
            connections = try? await api.connections()
        }
    }
}

// MARK: - Main view

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = SettingsViewModel()

    @AppStorage("productiveStart") private var productiveStart: Int = 9
    @AppStorage("productiveEnd") private var productiveEnd: Int = 17
    @AppStorage("growthCompanionEnabled") private var growthCompanionEnabled = true
    @AppStorage("growthReduceMotion") private var growthReduceMotion = false

    @State private var showDeleteAlert = false
    @State private var showStorageInfo = false
    @State private var assertivenessIndex: Int = 1
    @State private var seededSleep = false
    @State private var calendarConnectionUpdating = false
    @State private var showingNameEditor = false
    @State private var draftName = ""
    @State private var savingName = false

    private let assertivenessModes = ["gentle", "balanced", "assertive"]
    private let assertivenessDescriptions = [
        "Gentle — Equinox nudges softly. You decide everything.",
        "Balanced — Smart defaults, easy overrides.",
        "Assertive — Equinox leads; you confirm the big moves.",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SETTINGS")
                            .font(Theme.mono(11, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                        Text("You & your rhythm")
                            .font(Theme.serif(33, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(.top, 8)

                    if let error = viewModel.errorMessage {
                        InlineErrorView(message: error)
                    }

                    // Profile
                    SettingsGroup(title: "PROFILE") {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Theme.accentWash)
                                    .frame(width: 52, height: 52)
                                    .overlay {
                                        Circle()
                                            .strokeBorder(Theme.accentRing, lineWidth: 1)
                                    }
                                Text(String(appState.user?.name?.prefix(1) ?? "?"))
                                    .font(Theme.serif(22, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(appState.user?.name ?? "—")
                                    .font(Theme.sans(16.5, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                                Text(appState.user?.email ?? "—")
                                    .font(Theme.sans(13))
                                    .foregroundStyle(Theme.muted)
                            }

                            Spacer()

                            Button("Edit") {
                                draftName = appState.user?.name ?? ""
                                showingNameEditor = true
                            }
                                .font(Theme.sans(14, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(Theme.accentWash)
                                .cornerRadius(10)
                        }
                        .padding(.vertical, 4)
                    }

                    // Rhythm
                    SettingsGroup(title: "RHYTHM", footer: "Equinox uses these windows to schedule focus blocks and protect your rest.") {
                        SettingsRow(
                            label: "Productive hours",
                            value: productiveRangeLabel
                        )
                        Divider().padding(.leading, 16)
                        SettingsRow(
                            label: "Time zone",
                            value: TimeZone.current.identifier
                        )
                        Divider().padding(.leading, 16)
                        SettingsRow(
                            label: "Days I usually rest",
                            value: "Sat, Sun"
                        )
                    }

                    // Connections
                    SettingsGroup(title: "CONNECTIONS") {
                        // Google Calendar
                        let gcConnected = viewModel.connections?.googleCalendar.connected ?? false
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: "4285F4").opacity(0.12))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: "calendar")
                                        .foregroundStyle(Color(hex: "4285F4"))
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Google Calendar")
                                    .font(Theme.sans(15, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                Text("Sync events and free/busy blocks")
                                    .font(Theme.sans(12))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Button {
                                updateGoogleCalendarConnection(!gcConnected)
                            } label: {
                                Text(calendarConnectionUpdating ? "Updating" : (gcConnected ? "Connected" : "Disconnected"))
                                    .font(Theme.mono(11, weight: .semibold))
                                    .foregroundStyle(gcConnected ? Theme.prioLow : Theme.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(gcConnected ? Theme.prioLow.opacity(0.12) : Theme.bgWarm)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(calendarConnectionUpdating)
                            .accessibilityLabel(gcConnected ? "Disconnect Google Calendar" : "Connect Google Calendar")
                        }
                        .padding(.vertical, 6)

                        if gcConnected {
                            Divider().padding(.leading, 16)
                            Toggle(isOn: Binding(
                                get: { viewModel.settings?.showCalendarEventTitles ?? false },
                                set: { value in
                                    Task { await viewModel.updateSettings(showCalendarEventTitles: value) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Show calendar event names")
                                        .font(Theme.sans(14))
                                        .foregroundStyle(Theme.ink)
                                    Text("Display Google event titles in schedule previews")
                                        .font(Theme.sans(12))
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            .tint(Theme.accent)
                            .padding(.vertical, 6)
                        }

                        Divider().padding(.leading, 16)

                        // Apple Health
                        let healthConnected = viewModel.connections?.health.connected ?? false
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red.opacity(0.10))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: "heart.fill")
                                        .foregroundStyle(Color.red.opacity(0.75))
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Apple Health")
                                    .font(Theme.sans(15, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                Text("Sleep, steps, and workout data")
                                    .font(Theme.sans(12))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(healthConnected ? "Connected" : "Connect")
                                .font(Theme.sans(13, weight: .semibold))
                                .foregroundStyle(healthConnected ? Theme.prioLow : Theme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(healthConnected ? Theme.prioLow.opacity(0.12) : Theme.accentWash)
                                .cornerRadius(10)
                        }
                        .padding(.vertical, 6)
                    }

                    // AI preferences
                    if let settings = viewModel.settings {
                        SettingsGroup(title: "AI PREFERENCES") {
                            // Suggestions toggle
                            Toggle(isOn: Binding(
                                get: { viewModel.settings?.suggestionsEnabled ?? settings.suggestionsEnabled },
                                set: { value in Task { await viewModel.updateSettings(suggestionsEnabled: value) } }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Suggestions enabled")
                                        .font(Theme.sans(15))
                                        .foregroundStyle(Theme.ink)
                                    Text("Equinox will propose schedule adjustments")
                                        .font(Theme.sans(12))
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            .tint(Theme.accent)
                            .padding(.vertical, 4)

                            Divider().padding(.leading, 16)

                            // Daily check-in toggle
                            Toggle(isOn: Binding(
                                get: { viewModel.settings?.dailyCheckinEnabled ?? settings.dailyCheckinEnabled },
                                set: { value in Task { await viewModel.updateSettings(dailyCheckinEnabled: value) } }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Daily check-in")
                                        .font(Theme.sans(15))
                                        .foregroundStyle(Theme.ink)
                                    Text("Rate your energy each morning")
                                        .font(Theme.sans(12))
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            .tint(Theme.accent)
                            .padding(.vertical, 4)

                            Divider().padding(.leading, 16)

                            // Assertiveness custom slider
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Assertiveness")
                                    .font(Theme.sans(15))
                                    .foregroundStyle(Theme.ink)

                                GeometryReader { geo in
                                    let dotCount = 3
                                    let spacing = geo.size.width / CGFloat(dotCount - 1)
                                    ZStack(alignment: .leading) {
                                        // Track background
                                        Capsule()
                                            .fill(Theme.bgWarm)
                                            .frame(height: 4)
                                        // Filled track
                                        Capsule()
                                            .fill(Theme.accent)
                                            .frame(width: spacing * CGFloat(assertivenessIndex) + 8, height: 4)
                                        // Dots
                                        HStack(spacing: 0) {
                                            ForEach(0..<dotCount, id: \.self) { i in
                                                let selected = i == assertivenessIndex
                                                ZStack {
                                                    if selected {
                                                        Circle()
                                                            .fill(Theme.accentWash)
                                                            .frame(width: 26, height: 26)
                                                    }
                                                    Circle()
                                                        .fill(i <= assertivenessIndex ? Theme.accent : Theme.faint)
                                                        .frame(width: selected ? 14 : 10, height: selected ? 14 : 10)
                                                        .shadow(color: selected ? Theme.accentRing : .clear, radius: 4)
                                                }
                                                .frame(width: 26, height: 26)
                                                .onTapGesture {
                                                    assertivenessIndex = i
                                                    Task {
                                                        await viewModel.updateSettings(suggestionMode: assertivenessModes[i])
                                                    }
                                                }
                                                if i < dotCount - 1 {
                                                    Spacer()
                                                }
                                            }
                                        }
                                    }
                                }
                                .frame(height: 26)

                                HStack(spacing: 0) {
                                    ForEach(["Gentle", "Balanced", "Assertive"], id: \.self) { label in
                                        Text(label)
                                            .font(Theme.mono(10))
                                            .foregroundStyle(Theme.muted)
                                        if label != "Assertive" { Spacer() }
                                    }
                                }

                                Text(assertivenessDescriptions[assertivenessIndex])
                                    .font(Theme.serif(13).italic())
                                    .foregroundStyle(Theme.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 8)
                        }
                        .onAppear {
                            assertivenessIndex = assertivenessModes.firstIndex(of: settings.suggestionMode) ?? 1
                        }
                    }

                    SettingsGroup(title: "GROWTH COMPANION", footer: "Orb only responds to learning actions. Rest, delays, and low-energy days never subtract progress.") {
                        Toggle(isOn: $growthCompanionEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Growth companion")
                                    .font(Theme.sans(15))
                                    .foregroundStyle(Theme.ink)
                                Text("Show Orb and glow progress on Today")
                                    .font(Theme.sans(12))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .tint(Theme.accent)
                        .padding(.vertical, 4)

                        Divider().padding(.leading, 16)

                        Toggle(isOn: $growthReduceMotion) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reduce motion")
                                    .font(Theme.sans(15))
                                    .foregroundStyle(Theme.ink)
                                Text("Reduce hatching and stardust animations")
                                    .font(Theme.sans(12))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        .tint(Theme.accent)
                        .padding(.vertical, 4)
                    }

                    // Data & privacy
                    SettingsGroup(title: "DATA & PRIVACY") {
                        Button {
                            withAnimation { showStorageInfo.toggle() }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("What Equinox stores")
                                        .font(Theme.sans(15))
                                        .foregroundStyle(Theme.ink)
                                    Spacer()
                                    Image(systemName: showStorageInfo ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.faint)
                                }
                                if showStorageInfo {
                                    Text("Equinox stores your task schedules, energy check-ins, learning profile, and calendar events. No content is sold or used to train external models. All data is encrypted at rest and in transit.")
                                        .font(Theme.sans(13))
                                        .foregroundStyle(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.top, 4)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Divider().padding(.leading, 16)

                        SettingsRow(label: "Export my data", action: {})

                        Divider().padding(.leading, 16)

                        SettingsRow(label: "Delete account", danger: true) {
                            showDeleteAlert = true
                        }
                    }

                    // Sign out
                    Button {
                        appState.signOut()
                    } label: {
                        Text("Sign Out")
                            .font(Theme.sans(15, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Theme.line, lineWidth: 1)
                            )
                            .cornerRadius(14)
                    }

                    // Version
                    Text("Equinox \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 8)

                    #if DEBUG
                    SettingsGroup(title: "DEVELOPER") {
                        Button(seededSleep ? "Sample health data added" : "Seed HealthKit sample data") {
                            Task {
                                seededSleep = await HealthKitService.shared.seedSampleSleepData()
                            }
                        }
                        .disabled(seededSleep)
                        .font(Theme.sans(14))
                        .foregroundStyle(seededSleep ? Theme.muted : Theme.accent)
                        .padding(.vertical, 6)
                    }
                    #endif
                }
                .padding(20)
            }
            .background(Theme.bg)
            .platformNavigationBarHidden(true)
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
            .alert("Delete account?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    Task { await appState.deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete your account and all data. This action cannot be undone.")
            }
            .sheet(isPresented: $showingNameEditor) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Display name")
                            .font(Theme.serif(28, weight: .semibold))
                            .foregroundStyle(Theme.ink)

                        TextField("Your name", text: $draftName)
                            .font(Theme.sans(16))
                            .platformWordsAutocapitalization()
                            .padding(14)
                            .background(Theme.surface)
                            .clipShape(.rect(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Theme.line, lineWidth: 1)
                            }

                        Text("This is shown in greetings and progress cards.")
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.muted)

                        Spacer()

                        PrimaryButton("Save name", systemImage: "checkmark", isLoading: savingName) {
                            Task {
                                savingName = true
                                let success = await appState.updateDisplayName(draftName)
                                savingName = false
                                if success {
                                    showingNameEditor = false
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(Theme.bg)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showingNameEditor = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private var productiveRangeLabel: String {
        func fmt(_ hour: Int) -> String {
            let suffix = hour < 12 ? "am" : "pm"
            let h = hour <= 12 ? hour : hour - 12
            return "\(h):00\(suffix)"
        }
        return "\(fmt(productiveStart)) – \(fmt(productiveEnd))"
    }

    private func updateGoogleCalendarConnection(_ connected: Bool) {
        guard !calendarConnectionUpdating else { return }

        Task {
            calendarConnectionUpdating = true
            await viewModel.setGoogleCalendarConnected(connected)
            calendarConnectionUpdating = false
        }
    }
}

// MARK: - Helper Views

private struct SettingsGroup<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Theme.mono(10, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(Theme.Space.lg)
            .background(Theme.surface)
            .cornerRadius(Theme.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(Theme.line2, lineWidth: 1)
            )
            // Two-layer warm shadow, matching Card.
            .shadow(color: Theme.shadowInk.opacity(0.04), radius: 1, x: 0, y: 1)
            .shadow(color: Theme.shadowInk.opacity(0.16), radius: 18, x: 0, y: 12)

            if let footer {
                Text(footer)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 6)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct SettingsRow: View {
    let label: String
    var sub: String? = nil
    var value: String? = nil
    var danger: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(Theme.sans(15))
                        .foregroundStyle(danger ? Color.red.opacity(0.75) : Theme.ink)
                    if let sub {
                        Text(sub)
                            .font(Theme.sans(12))
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                if let value {
                    Text(value)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                        .padding(.leading, 4)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
