#if os(iOS)
import BackgroundTasks
import UIKit

/// Asks iOS to wake the app shortly after the next iqama, so it can end the Live Activity that
/// went stale and schedule the next windows. iOS decides when the task really runs (often
/// minutes late, sometimes not at all), so this is best effort; the app also reconciles every
/// time it comes to the foreground.
@MainActor
enum BackgroundRefresh {
    static let taskID = "com.itdeveapps.iqama.refresh"

    /// Call before `didFinishLaunching` returns.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: .main) { task in
            MainActor.assumeIsolated { handle(task) }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { schedule() }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { refreshNow() }
        }
    }

    private static func refreshNow() {
        LiveActivityController.shared.reconcile()
        NotificationManager.shared.scheduleUpcoming(force: true)
    }

    private static func handle(_ task: BGTask) {
        refreshNow()
        schedule()
        task.setTaskCompleted(success: true)
    }

    private static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = LiveActivityController.shared.nextEndDate ?? Date().addingTimeInterval(3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
#endif
