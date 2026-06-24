//
//  Dubai_iqamaApp.swift
//  Dubai iqama
//
//  Created by Omar Altamimi on 21/01/2026.
//

import SwiftUI
import WidgetKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@main
struct Dubai_iqamaApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    #elseif os(iOS)
    @UIApplicationDelegateAdaptor(IOSAppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 480, height: 860)

        Settings {
            SettingsView()
        }
        #else
        WindowGroup {
            ContentView()
        }
        #endif
    }
}

/// Startup work shared by both platforms: notification permission, preload the current
/// month so the first paint isn't blank, resolve the location, fetch non-UAE data, and
/// refresh widget timelines.
@MainActor
enum AppBootstrap {
    static func performCommonStartup() {
        NotificationManager.shared.requestPermission()

        let currentMonth = Calendar.current.component(.month, from: Date())
        PrayerTimesService.shared.preloadMonth(currentMonth)

        LocationManager.shared.resolveIfAuto()
        AladhanSync.shared.syncIfNeeded()

        // Force the widget extension to refresh timelines with the latest design / data.
        WidgetCenter.shared.reloadAllTimelines()
    }
}

#if os(macOS)
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One-time migration of the on-disk name (Dubai iqama.app -> Iqama.app). If it relocates,
        // the app quits and relaunches from the new path, so skip the rest of startup.
        if AppRelocator.migrateIfNeeded() { return }

        // Initialize status bar (macOS-only — no menu bar on iOS).
        statusBarController = StatusBarController()

        AppBootstrap.performCommonStartup()

        // Check GitHub for a newer release now and once per day (macOS distributes outside the
        // App Store; on iOS the App Store handles updates).
        UpdateChecker.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup if needed
    }
}
#elseif os(iOS)
final class IOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AppBootstrap.performCommonStartup()
        return true
    }
}
#endif
