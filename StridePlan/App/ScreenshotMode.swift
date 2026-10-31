#if DEBUG
import SwiftData
import SwiftUI

/// Debug-only: launch with `-screen <name>` to open a screen directly with demo data.
/// Used by `.github/workflows/screenshots.yml` to capture App Store–style screenshots.
enum ScreenshotMode {
    enum Screen: String, CaseIterable {
        case onboarding, today, plan, catalog, planDetail, setup, workoutDetail, running, summary, history, settings
    }

    static var requestedScreen: Screen? {
        UserDefaults.standard.string(forKey: "screen").flatMap(Screen.init(rawValue:))
    }
}

struct ScreenshotHost: View {
    let screen: ScreenshotMode.Screen

    var body: some View {
        content
            .modelContainer(PreviewData.container)
            .environment(\.services, .preview)
            .environment(RunLauncher())
            .tint(Theme.accent)
    }

    @ViewBuilder
    private var content: some View {
        let profile = PreviewData.profile
        switch screen {
        case .onboarding:
            OnboardingFlow(profile: UserProfile())
        case .today:
            MainTabView(profile: profile, initialTab: .today)
        case .plan:
            MainTabView(profile: profile, initialTab: .plan)
        case .catalog:
            MainTabView(profile: profile, initialTab: .catalog)
        case .history:
            MainTabView(profile: profile, initialTab: .history)
        case .settings:
            MainTabView(profile: profile, initialTab: .settings)
        case .planDetail:
            NavigationStack {
                PlanDetailView(plan: PreviewData.template, profile: profile)
            }
        case .setup:
            PlanSetupView(plan: PreviewData.template, profile: profile, existingPlan: nil)
        case .workoutDetail:
            if let plan = PreviewData.plan, let workout = Self.showcaseWorkout(in: plan) {
                NavigationStack {
                    WorkoutDetailView(scheduled: workout, plan: plan, template: PreviewData.template, profile: profile)
                }
            }
        case .running:
            ScreenshotRunView(profile: profile)
        case .summary:
            NavigationStack {
                RunSummaryView(run: Self.showcaseRun, profile: profile, isNewRun: true)
            }
        }
    }

    /// The next upcoming quality session (more interesting than an easy run).
    private static func showcaseWorkout(in plan: ActivePlan) -> ScheduledWorkout? {
        let upcoming = plan.sortedWorkouts.filter { $0.status == .upcoming }
        return upcoming.first { PreviewData.template.workout(id: $0.templateWorkoutID)?.type.isQuality == true } ?? upcoming.first
    }

    /// Most recent completed run that has step results, so the compliance section shows.
    private static var showcaseRun: RunRecord {
        let runs = (try? PreviewData.context.fetch(FetchDescriptor<RunRecord>(sortBy: [SortDescriptor(\.startDate, order: .reverse)]))) ?? []
        return runs.first { $0.stepResults.count > 3 } ?? PreviewData.run
    }
}

/// A live run driven by the bundled GPX replay.
private struct ScreenshotRunView: View {
    let profile: UserProfile
    @State private var session: RunSession?

    var body: some View {
        Group {
            if let session {
                RunningView(session: session) { _ in }
            }
        }
        .onAppear {
            guard session == nil else { return }
            let workout = PreviewData.template.schedule.flatMap(\.workouts).first { $0.type == .intervals }
            let session = RunSession(workout: workout, zones: profile.paceZones, units: profile.units,
                                     voiceSettings: profile.voiceSettings,
                                     location: GPXReplayLocationService(speedMultiplier: 1),
                                     voice: MockVoiceCoach(), haptics: SilentHaptics(), liveActivity: MockLiveActivityService())
            self.session = session
            session.begin(countdown: 0)
        }
    }
}
#endif
