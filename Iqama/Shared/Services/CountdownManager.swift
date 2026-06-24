import Foundation
import Combine

@MainActor
class CountdownManager: ObservableObject {
    static let shared = CountdownManager()

    @Published private(set) var currentState: CountdownSnapshot?
    @Published private(set) var error: Error?

    private var timer: Timer?
    private let prayerService = PrayerTimesService.shared

    private init() {
        startTimer()
    }

    // MARK: - Timer Management

    func startTimer() {
        stopTimer()

        // Update immediately
        updateState()

        // Update every second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateState()
            }
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - State Calculation

    private func updateState() {
        do {
            let now = Date()
            let newState = try calculateCurrentPhase(at: now)
            currentState = newState
            error = nil

            // Pre-iqama reminder + "did you pray?" nag loop
            NotificationManager.shared.tick(snapshot: newState)

            #if os(iOS)
            // Keep the Lock Screen / Dynamic Island countdown in sync (no-op if disabled).
            LiveActivityController.shared.sync(with: newState)
            #endif
        } catch {
            self.error = error
            currentState = nil
            #if os(iOS)
            LiveActivityController.shared.end()
            #endif
        }
    }

    func calculateCurrentPhase(at now: Date) throws -> CountdownSnapshot {
        guard let nextPrayerInfo = try prayerService.getNextPrayerInfo(from: now) else {
            throw PrayerTimesError.noPrayerTimesAvailable
        }

        let (prayer, azanTime, iqamaTime, dailyTimes) = nextPrayerInfo
        let settings = try prayerService.getAzanSettings(for: now)

        let phase: CountdownPhase
        let timeRemaining: TimeInterval

        if now < azanTime {
            // Waiting for Azan
            phase = .waitingForAzan(prayer: prayer, azanTime: azanTime)
            timeRemaining = azanTime.timeIntervalSince(now)
        } else if now < iqamaTime {
            // Azan has happened, waiting for Iqama
            phase = .waitingForIqama(prayer: prayer, iqamaTime: iqamaTime)
            timeRemaining = iqamaTime.timeIntervalSince(now)
        } else {
            // Should not reach here as getNextPrayerInfo handles this
            // But just in case, calculate next prayer
            return try calculateNextAfterIqama(currentPrayer: prayer, at: now)
        }

        return CountdownSnapshot(
            phase: phase,
            timeRemaining: max(0, timeRemaining),
            todayPrayerTimes: dailyTimes,
            azanSettings: settings
        )
    }

    private func calculateNextAfterIqama(currentPrayer: Prayer, at now: Date) throws -> CountdownSnapshot {
        let nextPrayer = currentPrayer.next
        let calendar = Calendar.current

        // If wrapping to Fajr, we need tomorrow's data
        let searchDate: Date
        if nextPrayer == .fajr {
            searchDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        } else {
            searchDate = now
        }

        guard let dailyTimes = try prayerService.getPrayerTimes(for: searchDate),
              let azanTime = dailyTimes.prayerTime(for: nextPrayer) else {
            throw PrayerTimesError.noPrayerTimesAvailable
        }

        let settings = try prayerService.getAzanSettings(for: searchDate)
        let phase = CountdownPhase.waitingForAzan(prayer: nextPrayer, azanTime: azanTime)
        let timeRemaining = azanTime.timeIntervalSince(now)

        return CountdownSnapshot(
            phase: phase,
            timeRemaining: max(0, timeRemaining),
            todayPrayerTimes: dailyTimes,
            azanSettings: settings
        )
    }

    // MARK: - Widget Support

    func generateTimelineEntries(from startDate: Date, count: Int = 20) throws -> [(date: Date, snapshot: CountdownSnapshot)] {
        var entries: [(date: Date, snapshot: CountdownSnapshot)] = []
        var currentDate = startDate

        for _ in 0..<count {
            do {
                let snapshot = try calculateCurrentPhase(at: currentDate)
                entries.append((currentDate, snapshot))

                // Move to next significant time (target time + 1 second)
                let nextDate = snapshot.phase.targetTime.addingTimeInterval(1)
                if nextDate > currentDate {
                    currentDate = nextDate
                } else {
                    // Safety: move forward by at least 1 minute
                    currentDate = currentDate.addingTimeInterval(60)
                }
            } catch {
                break
            }
        }

        return entries
    }

    // MARK: - Manual Refresh

    func refresh() {
        updateState()
    }
}
