import SwiftUI
import UserNotifications

/// Onboarding for Prayer Check-in: explains the "did you pray?" loop, surfaces the notification
/// permission + alert-style state, and lets the user choose which prayers get follow-ups.
/// Auto-presented once (after location setup) and reachable any time from the home CTA.
struct CheckInSetupView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettings.Keys.checkInOnboarded) private var onboarded = false
    @AppStorage(AppSettings.Keys.notificationsEnabled)
    private var notificationsEnabled = AppSettings.Defaults.notificationsEnabled
    @AppStorage(AppSettings.Keys.nagFajr) private var nagFajr = AppSettings.Defaults.nagFajr
    @AppStorage(AppSettings.Keys.nagZuhr) private var nagZuhr = AppSettings.Defaults.nagZuhr
    @AppStorage(AppSettings.Keys.nagAsr) private var nagAsr = AppSettings.Defaults.nagAsr
    @AppStorage(AppSettings.Keys.nagMaghrib) private var nagMaghrib = AppSettings.Defaults.nagMaghrib
    @AppStorage(AppSettings.Keys.nagIsha) private var nagIsha = AppSettings.Defaults.nagIsha
    @AppStorage(AppSettings.Keys.nagIntervalMinutes)
    private var nagInterval = AppSettings.Defaults.nagIntervalMinutes

    @State private var authStatus: UNAuthorizationStatus?
    @State private var alertStyle: UNAlertStyle?

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.tint)
                Text("Prayer Check-in")
                    .font(.title2.weight(.semibold))
                Text("Iqama holds you to your prayers — it keeps asking “Did you pray?” until you confirm.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            howItWorksCard
            notificationsCard
            prayersCard

            HStack {
                Button("Not now") {
                    onboarded = true
                    dismiss()
                }
                Spacer()
                Button("Done") { confirm() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 470)
        #endif
        .onAppear { refreshNotificationStatus() }
        // Coming back from System Settings → re-check permission/style.
        .onReceive(NotificationCenter.default.publisher(for: PlatformSupport.didBecomeActiveNotification)) { _ in
            refreshNotificationStatus()
        }
    }

    // MARK: - How it works

    private var howItWorksCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                step("bell.badge.fill", "Before iqama",
                     "The reminder asks you to commit: “Wallah, going to pray now” — or remind you later.")
                step("questionmark.bubble.fill", "After iqama",
                     "Didn't commit? It checks in — “Did you pray?” — and keeps asking every \(nagInterval) minutes.")
                step("checkmark.seal.fill", "Confirm",
                     "Answer “Yes, Wallah” and it stops. The check-in ends when the next prayer comes in.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("How it works", systemImage: "sparkles")
        }
    }

    private func step(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Notifications

    private var notificationsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                switch authStatus {
                case .authorized, .provisional:
                    if alertStyle == .alert {
                        Label("Notifications are on and stay until answered", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Notifications disappear after a few seconds", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("The system can't let apps change this themselves. One quick switch — set the alert/banner style to “Persistent” so check-ins stay on screen until you answer:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        alertStyleGuide
                        Button("Open Iqama's Notification Settings…") { Self.openNotificationSettings() }
                            .buttonStyle(.borderedProminent)
                    }
                    if !notificationsEnabled {
                        Text("Iqama reminders are currently switched off — Done turns them back on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .denied:
                    Label("Notifications are off", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Check-in can't reach you without notifications. Allow them for Iqama, then pick the “Persistent” alert style so they stay until answered.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Iqama's Notification Settings…") { Self.openNotificationSettings() }
                case .none:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking permission…").foregroundStyle(.secondary)
                    }
                default:  // .notDetermined
                    Text("Allow notifications so Iqama can remind you and check in after each prayer.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Enable notifications") {
                        NotificationManager.shared.requestPermission { _ in refreshNotificationStatus() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Notifications", systemImage: "bell.badge.fill")
        }
    }

    /// A small replica of the System Settings row the user needs to change, with the
    /// target option highlighted — so they instantly recognize it on the real screen.
    private var alertStyleGuide: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Text("Alert Style")
                    .font(.callout)
                Spacer()
                fakeRadio("Temporary", selected: false)
                fakeRadio("Persistent", selected: true)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.platformQuaternaryFill)
            )
            Label("choose this", systemImage: "arrow.up")
                .font(.caption2)
                .foregroundStyle(Color.accentColor)
                .padding(.trailing, 14)
        }
    }

    private func fakeRadio(_ label: String, selected: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: selected ? "inset.filled.circle" : "circle")
                .font(.system(size: 11))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            Text(label)
                .font(.caption)
        }
    }

    // MARK: - Prayers

    private var prayersCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
                          alignment: .leading, spacing: 8) {
                    Toggle("Fajr", isOn: $nagFajr)
                    Toggle("Dhuhr", isOn: $nagZuhr)
                    Toggle("Asr", isOn: $nagAsr)
                    Toggle("Maghrib", isOn: $nagMaghrib)
                    Toggle("Isha", isOn: $nagIsha)
                }
                Divider()
                Picker("Ask every", selection: $nagInterval) {
                    ForEach(AppSettings.nagIntervalChoices, id: \.self) { m in
                        Text("\(m) minutes").tag(m)
                    }
                }
                Text("Prayers without check-in keep the normal one-off reminder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Check in for", systemImage: "list.bullet.circle.fill")
        }
    }

    // MARK: - Actions

    private func confirm() {
        onboarded = true
        // Check-in rides on the reminders pipeline — turn the master switch on if anything's enabled.
        if nagFajr || nagZuhr || nagAsr || nagMaghrib || nagIsha {
            notificationsEnabled = true
        }
        if authStatus == .notDetermined {
            NotificationManager.shared.requestPermission()
        }
        dismiss()
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                authStatus = settings.authorizationStatus
                alertStyle = settings.alertStyle
            }
        }
    }

    /// Open this app's notification settings (macOS System Settings → Notifications for Iqama;
    /// iOS Settings → Iqama).
    static func openNotificationSettings() {
        PlatformSupport.openAppNotificationSettings()
    }
}
