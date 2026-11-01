import SwiftData
import SwiftUI

@main
struct StridePlanApp: App {
    private let container: ModelContainer
    private let services: AppServices
    @State private var launcher = RunLauncher()

    init() {
        do {
            container = try ModelContainer(for: UserProfile.self, ActivePlan.self, ScheduledWorkout.self, RunRecord.self)
        } catch {
            fatalError("Could not open the data store: \(error)")
        }
        services = AppServices.live()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let screen = ScreenshotMode.requestedScreen {
                ScreenshotHost(screen: screen)
            } else {
                rootView
            }
            #else
            rootView
            #endif
        }
        .modelContainer(container)
    }

    private var rootView: some View {
        RootView()
            .environment(\.services, services)
            .environment(launcher)
            .tint(Theme.accent)
            .onOpenURL { url in
                // Garmin Connect returns here after the user picks a watch.
                services.garmin.handleOpenURL(url)
            }
    }
}

/// Presents the guided run flow from anywhere in the app.
@Observable
final class RunLauncher {
    var request: RunRequest?
    var manualLog: ManualLogRequest?

    func startRun(_ workout: WorkoutTemplate?, scheduled: ScheduledWorkout?) {
        request = RunRequest(template: workout, scheduled: scheduled)
    }

    func logManually(_ workout: WorkoutTemplate?, scheduled: ScheduledWorkout?) {
        manualLog = ManualLogRequest(template: workout, scheduled: scheduled)
    }
}

struct RunRequest: Identifiable {
    let id = UUID()
    /// nil = open-ended free run.
    var template: WorkoutTemplate?
    var scheduled: ScheduledWorkout?
}

struct ManualLogRequest: Identifiable {
    let id = UUID()
    var template: WorkoutTemplate?
    var scheduled: ScheduledWorkout?
}
