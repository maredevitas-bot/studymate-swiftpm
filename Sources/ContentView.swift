import SwiftUI

struct ContentView: View {
    @AppStorage("isOnboardingComplete") private var isOnboardingComplete = false

    var body: some View {
        if isOnboardingComplete {
            TabView {
                SubjectsTabView()
                    .tabItem { Label("과목", systemImage: "books.vertical") }
                PlannerTabView()
                    .tabItem { Label("플래너", systemImage: "calendar") }
                AnalyticsTabView()
                    .tabItem { Label("분석", systemImage: "chart.bar") }
                SettingsTabView()
                    .tabItem { Label("설정", systemImage: "gearshape") }
            }
        } else {
            NavigationStack {
                OnboardingView(isOnboardingComplete: $isOnboardingComplete)
            }
        }
    }
}
