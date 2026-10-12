import Foundation
import AVFoundation
import Combine
import UserNotifications

/// The Adhan recordings in the app. All have a free license (CC0, CC BY, or CC BY-SA), and
/// Settings shows the credit for each one. Each sound has two files in `Resources/Adhan`:
/// the full Adhan for the app (`adhan-<id>.m4a`) and a short clip for the notification
/// (`adhan-<id>-alert.caf`). iOS plays at most 30 seconds of a notification sound.
enum AdhanSound: String, CaseIterable, Identifiable {
    case serene, gentle, madinah, warm

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .serene: return "Serene"
        case .gentle: return "Gentle"
        case .madinah: return "Madinah"
        case .warm: return "Warm"
        }
    }

    var fullFileURL: URL? { Bundle.main.url(forResource: "adhan-\(rawValue)", withExtension: "m4a") }
    var alertSoundName: UNNotificationSoundName { UNNotificationSoundName("adhan-\(rawValue)-alert.caf") }

    struct Credit {
        let title: String
        let author: String
        let license: String
        let source: URL
    }

    /// The recordings come from Wikimedia Commons. The app shortens, fades, and normalizes them.
    var credit: Credit {
        switch self {
        case .serene:
            return Credit(title: "Beautiful adhan", author: "Adam-synagda", license: "CC0 1.0",
                          source: URL(string: "https://commons.wikimedia.org/wiki/File:Beautiful_adhan.ogg")!)
        case .gentle:
            return Credit(title: "The Adhan – Muslim Call to Prayer – Aaqib Azeez", author: "Atcovi",
                          license: "CC BY-SA 4.0",
                          source: URL(string: "https://commons.wikimedia.org/wiki/File:The_Adhan_-_Muslim_Call_to_Prayer_-_Aaqib_Azeez.mp3")!)
        case .madinah:
            return Credit(title: "Call to prayer from the Prophet's Mosque", author: "ejaz215 (Freesound)",
                          license: "CC BY 3.0",
                          source: URL(string: "https://commons.wikimedia.org/wiki/File:33937_ejaz215_call-to-prayer-from-the-prophet-s-mo.ogg")!)
        case .warm:
            return Credit(title: "Azan", author: "Andrewler", license: "CC BY-SA 4.0",
                          source: URL(string: "https://commons.wikimedia.org/wiki/File:Azan.ogg")!)
        }
    }
}

extension AppSettings {
    /// The selected Adhan. It lives here and not in `AppSettings`, because the widget target
    /// shares `AppSettings` but does not have the sounds.
    static var adhanSound: AdhanSound {
        AdhanSound(rawValue: UserDefaults.standard.string(forKey: Keys.adhanSound) ?? Defaults.adhanSound) ?? .serene
    }
}

/// Plays the full Adhan when a prayer's azan time arrives while the app runs, and plays the
/// preview in Settings. On iOS the app is suspended in the background, so there the scheduled
/// azan notification plays the short clip instead (see `NotificationManager`).
@MainActor
final class AdhanPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AdhanPlayer()

    /// The sound that plays now, or nil.
    @Published private(set) var playing: AdhanSound?

    private var player: AVAudioPlayer?
    /// The azan that played last ("Fajr@1760241600"), so one azan plays only once.
    private var lastAzanKey: String?
    /// Only an azan in the last minute plays. An app that opens later in the azan → iqama
    /// interval stays silent.
    private let lateLimit: TimeInterval = 60

    private override init() { super.init() }

    /// Called each second with the countdown state. `now` is the preview clock, so the time
    /// preview ("Azan in 5 s") plays the Adhan too.
    func observe(_ snapshot: CountdownSnapshot, now: Date) {
        guard case .waitingForIqama(let prayer, _) = snapshot.phase else {
            // Before the azan: forget the last azan, so a preview can play the same azan again.
            lastAzanKey = nil
            return
        }
        guard let azan = snapshot.todayPrayerTimes?.prayerTime(for: prayer) else { return }
        let key = "\(prayer.rawValue)@\(Int(azan.timeIntervalSince1970))"
        guard key != lastAzanKey else { return }
        lastAzanKey = key
        guard now.timeIntervalSince(azan) < lateLimit, AppSettings.adhanEnabled(for: prayer) else { return }
        play(AppSettings.adhanSound)
        #if os(macOS)
        // The banner follows the real time only, like the other notifications.
        if !PreviewClock.shared.isActive {
            let iqama = snapshot.phase.targetTime
            NotificationManager.shared.postAzanBanner(for: prayer, iqamaMinutes: Int(iqama.timeIntervalSince(azan) / 60))
        }
        #endif
    }

    func play(_ sound: AdhanSound) {
        stop()
        guard let url = sound.fullFileURL,
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        #if os(iOS)
        // `.playback` plays with the Ring/Silent switch on silent, as a call to prayer must.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        player.delegate = self
        guard player.play() else { return }
        self.player = player
        playing = sound
    }

    func stop() {
        player?.stop()
        player = nil
        finish()
    }

    private func finish() {
        playing = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.player = nil
            self.finish()
        }
    }
}
