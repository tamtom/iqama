import Foundation
import AVFoundation
import Combine
import UserNotifications

/// The Adhan recordings in the app. Settings shows the source of each one. Each sound has two
/// files in `Resources/Adhan`: the full Adhan for the app (`adhan-<id>.m4a`) and a short clip
/// for the notification (`adhan-<id>-alert.caf`). iOS plays at most 30 seconds of a
/// notification sound. The app trims, fades, and normalizes the recordings.
enum AdhanSound: String, CaseIterable, Identifiable {
    case makkah, madinah, aqsa, jordan, amman, alafasy, qatami, nufais, zahrani, sobhy, serene, gentle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .makkah: return "Makkah"
        case .madinah: return "Madinah"
        case .aqsa: return "Al-Aqsa"
        case .jordan: return "Jordan"
        case .amman: return "Amman (many mosques)"
        case .alafasy: return "Mishary Alafasy"
        case .qatami: return "Nasser Al-Qatami"
        case .nufais: return "Ahmed Al-Nufais"
        case .zahrani: return "Mansour Al-Zahrani"
        case .sobhy: return "Islam Sobhy"
        case .serene: return "Serene"
        case .gentle: return "Gentle"
        }
    }

    var fullFileURL: URL? { Bundle.main.url(forResource: "adhan-\(rawValue)", withExtension: "m4a") }
    var alertSoundName: UNNotificationSoundName { UNNotificationSoundName("adhan-\(rawValue)-alert.caf") }

    struct Credit {
        let detail: String
        let source: URL
    }

    var credit: Credit {
        let muezzin = "https://github.com/DBChoco/Muezzin"
        let athany = "https://github.com/0xzer0x/athany"
        switch self {
        case .makkah: return Credit(detail: "Masjid al-Haram. File from Muezzin.", source: URL(string: muezzin)!)
        case .madinah: return Credit(detail: "Masjid an-Nabawi. File from Al-Azan.", source: URL(string: "https://github.com/meypod/al-azan")!)
        case .aqsa: return Credit(detail: "Masjid al-Aqsa. File from Muezzin.", source: URL(string: muezzin)!)
        case .jordan:
            return Credit(detail: "“Adhan 1 Jordan”, Simtech Productions. YouTube Music.",
                          source: URL(string: "https://music.youtube.com/watch?v=i0UnyIXogCU")!)
        case .amman:
            // Amman broadcasts one Adhan from all mosques at the same time. Six delayed copies
            // (0.2–2.6 s), each quieter, duller, and panned, plus an outdoor reverb, give the
            // echo of far mosques in the pauses.
            return Credit(detail: "The Jordan Adhan with an added echo of many far mosques.",
                          source: URL(string: "https://music.youtube.com/watch?v=i0UnyIXogCU")!)
        case .alafasy: return Credit(detail: "Mishary Rashid Alafasy. File from Athany.", source: URL(string: athany)!)
        case .qatami: return Credit(detail: "Nasser Al-Qatami. File from Athany.", source: URL(string: athany)!)
        case .nufais: return Credit(detail: "Ahmed Al-Nufais. File from Muezzin.", source: URL(string: muezzin)!)
        case .zahrani: return Credit(detail: "Mansour Al-Zahrani. File from Athany.", source: URL(string: athany)!)
        case .sobhy: return Credit(detail: "Islam Sobhy. File from Athany.", source: URL(string: athany)!)
        case .serene:
            return Credit(detail: "“Beautiful adhan” by Adam-synagda, CC0 1.0. Wikimedia Commons.",
                          source: URL(string: "https://commons.wikimedia.org/wiki/File:Beautiful_adhan.ogg")!)
        case .gentle:
            return Credit(detail: "“The Adhan – Aaqib Azeez” by Atcovi, CC BY-SA 4.0. Wikimedia Commons.",
                          source: URL(string: "https://commons.wikimedia.org/wiki/File:The_Adhan_-_Muslim_Call_to_Prayer_-_Aaqib_Azeez.mp3")!)
        }
    }
}

extension AppSettings {
    /// The selected Adhan. It lives here and not in `AppSettings`, because the widget target
    /// shares `AppSettings` but does not have the sounds.
    static var adhanSound: AdhanSound {
        AdhanSound(rawValue: UserDefaults.standard.string(forKey: Keys.adhanSound) ?? Defaults.adhanSound) ?? .makkah
    }
}

/// Plays the preview in Settings. On macOS it also plays the full Adhan at each azan time,
/// because the menu bar app runs all the time. On iOS only the azan notification plays the
/// Adhan, when the app is closed or in the background (see `NotificationManager`).
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
    /// preview ("Azan in 5 s") plays the Adhan too. iOS does nothing here: the open app stays
    /// silent at the azan time.
    func observe(_ snapshot: CountdownSnapshot, now: Date) {
        #if os(macOS)
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
