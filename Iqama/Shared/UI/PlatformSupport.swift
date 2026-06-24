import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Thin cross-platform shims so the shared SwiftUI views can open URLs and the
/// system Settings without each call site branching on AppKit vs UIKit.
enum PlatformSupport {
    /// Open a URL in the system handler (browser, Settings deep link, …).
    static func open(_ url: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }

    /// Jump to this app's notification settings (macOS System Settings → Notifications
    /// for Iqama; iOS Settings → Iqama).
    static func openAppNotificationSettings() {
        #if os(macOS)
        let pane = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: bundleID.isEmpty ? pane : "\(pane)?id=\(bundleID)") { open(url) }
        #elseif os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { open(url) }
        #endif
    }

    /// Jump to Location settings (macOS Privacy pane; iOS app settings page).
    static func openLocationSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            open(url)
        }
        #elseif os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { open(url) }
        #endif
    }

    /// "App returned to the foreground" notification — used to re-poll permission state
    /// after the user comes back from the system Settings app.
    static var didBecomeActiveNotification: Notification.Name {
        #if os(macOS)
        return NSApplication.didBecomeActiveNotification
        #else
        return UIApplication.didBecomeActiveNotification
        #endif
    }
}

extension Color {
    /// A faint system fill used as a backdrop for the "fake settings row" preview.
    static var platformQuaternaryFill: Color {
        #if canImport(AppKit)
        return Color(nsColor: .quaternarySystemFill)
        #elseif canImport(UIKit)
        return Color(uiColor: .quaternarySystemFill)
        #else
        return Color.gray.opacity(0.2)
        #endif
    }
}
