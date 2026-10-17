import SwiftUI
import StoreKit

/// A shifted clock for the main screen, so a tester can see any prayer state without waiting.
/// Only TestFlight and Debug builds offer it; App Store builds never show the controls.
/// While a preview runs, the app does not schedule notifications or update the Live Activity,
/// because those must follow the real time.
@MainActor @Observable
final class PreviewClock {
    static let shared = PreviewClock()

    private(set) var offset: TimeInterval = 0
    private(set) var isAvailable = false

    var isActive: Bool { offset != 0 }
    var now: Date { Date().addingTimeInterval(offset) }

    private init() {}

    /// TestFlight builds report the `sandbox` environment; App Store builds report `production`.
    func checkAvailability() async {
        #if DEBUG
        isAvailable = true
        // `-previewClock HH:mm` starts the preview at that time of today, for recordings.
        if let clock = UserDefaults.standard.string(forKey: "previewClock") {
            let parts = clock.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2,
               let date = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: .now) {
                jump(to: date)
            }
        }
        #elseif os(macOS)
        // A Mac build has no TestFlight. Turn the tools on with
        // `defaults write com.tamimi.shared.Dubai-iqama showTestTools -bool YES`.
        isAvailable = UserDefaults.standard.bool(forKey: AppSettings.Keys.showTestTools)
        #else
        if case .verified(let transaction)? = try? await AppTransaction.shared {
            isAvailable = transaction.environment == .sandbox
        }
        #endif
    }

    func jump(to date: Date) {
        offset = date.timeIntervalSinceNow
        CountdownManager.shared.refresh()
    }

    func reset() {
        offset = 0
        CountdownManager.shared.refresh()
    }
}

/// The controls for the preview clock: any date and time, or a jump to 5 seconds before a
/// prayer's azan or iqama, so the transition and its celebration play live.
struct TimePreviewPanel: View {
    var close: () -> Void

    @State private var prayer: Prayer = .fajr
    private let clock = PreviewClock.shared
    private let lead: TimeInterval = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Time preview", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close time preview")
            }

            // Redrawn each minute, so the shown time moves on with the preview clock.
            TimelineView(.everyMinute) { _ in
                DatePicker("Time",
                           selection: Binding(get: { clock.now }, set: { clock.jump(to: $0) }),
                           displayedComponents: [.date, .hourAndMinute])
                    .font(.system(size: 14))
            }

            Picker("Prayer", selection: $prayer) {
                ForEach(Prayer.orderedPrayers, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Button("Azan in 5 s") { jump(toIqama: false) }
                Button("Iqama in 5 s") { jump(toIqama: true) }
                Spacer(minLength: 0)
                Button("Live") { clock.reset() }
                    .disabled(!clock.isActive)
            }
            .buttonStyle(.bordered)
            .font(.system(size: 13, weight: .medium))

            Text("Notifications and the Live Activity pause during a preview. They return with Live.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .onAppear {
            if let current = CountdownManager.shared.currentState?.phase.prayer { prayer = current }
        }
    }

    /// Jumps to just before the selected prayer on the previewed day.
    private func jump(toIqama: Bool) {
        let service = PrayerTimesService.shared
        let day = clock.now
        guard let times = try? service.getPrayerTimes(for: day),
              let azan = times.prayerTime(for: prayer) else { return }
        var target = azan
        if toIqama, let settings = try? service.getAzanSettings(for: day) {
            let minutes = settings.iqamaMinutes(for: prayer, isFriday: times.isFriday)
            target = azan.addingTimeInterval(TimeInterval(minutes * 60))
        }
        clock.jump(to: target.addingTimeInterval(-lead))
    }
}
