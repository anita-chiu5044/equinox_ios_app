import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    init() {
        // Tab bar: warm paper background, accent tint for active items
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.bg)
        appearance.shadowColor = UIColor(Theme.line)

        let normal = appearance.stackedLayoutAppearance.normal
        normal.iconColor = UIColor(Theme.faint)
        normal.titleTextAttributes = [.foregroundColor: UIColor(Theme.muted)]

        let selected = appearance.stackedLayoutAppearance.selected
        selected.iconColor = UIColor(Theme.accent)
        selected.titleTextAttributes = [.foregroundColor: UIColor(Theme.accent)]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView {
                selectedTab = 1
            }
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }
                .tag(0)

            PlansView()
                .tabItem {
                    Label("Plans", systemImage: "list.bullet.clipboard")
                }
                .tag(1)

            InsightsView()
                .tabItem {
                    Label("Insights", systemImage: "chart.bar")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(3)
        }
        .tint(Theme.accent)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
