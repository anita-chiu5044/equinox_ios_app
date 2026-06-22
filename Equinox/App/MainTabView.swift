import SwiftUI

struct MainTabView: View {
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
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }

            PlansView()
                .tabItem {
                    Label("Plans", systemImage: "list.bullet.clipboard")
                }

            InsightsView()
                .tabItem {
                    Label("Insights", systemImage: "chart.bar")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(Theme.accent)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}
