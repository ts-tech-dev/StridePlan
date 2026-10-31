import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                if profile.hasCompletedOnboarding {
                    MainTabView(profile: profile)
                } else {
                    OnboardingFlow(profile: profile)
                }
            } else {
                ProgressView()
                    .task { ensureProfile() }
            }
        }
        .animation(.default, value: profiles.first?.hasCompletedOnboarding)
    }

    private func ensureProfile() {
        guard profiles.isEmpty else { return }
        let units: UnitSystem = Locale.current.measurementSystem == .metric ? .metric : .imperial
        context.insert(UserProfile(units: units))
        try? context.save()
    }
}

enum AppTab: Hashable {
    case today, plan, catalog, history, settings
}

struct MainTabView: View {
    @Bindable var profile: UserProfile
    @Environment(RunLauncher.self) private var launcher
    @Environment(\.services) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<ActivePlan> { $0.statusRaw == "active" }) private var activePlans: [ActivePlan]
    @State private var selection: AppTab

    init(profile: UserProfile, initialTab: AppTab = .today) {
        self.profile = profile
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        @Bindable var launcher = launcher
        TabView(selection: $selection) {
            TodayView(profile: profile, selectedTab: $selection)
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)
            ScheduleView(profile: profile, selectedTab: $selection)
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(AppTab.plan)
            CatalogView(profile: profile)
                .tabItem { Label("Plans", systemImage: "square.grid.2x2") }
                .tag(AppTab.catalog)
            HistoryView(profile: profile)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)
            SettingsView(profile: profile)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .fullScreenCover(item: $launcher.request) { request in
            RunFlowView(request: request, profile: profile)
        }
        .sheet(item: $launcher.manualLog) { request in
            ManualRunView(request: request, profile: profile)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            for plan in activePlans { PlanManager.refreshStatuses(plan) }
            Task {
                let plan = activePlans.first
                await PlanManager.refreshReminders(plan: plan, template: plan.flatMap { services.plans.plan(id: $0.planID) },
                                                   profile: profile, notifications: services.notifications)
            }
        }
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}
