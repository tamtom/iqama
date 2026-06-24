import Foundation
import Combine
import CoreLocation
import WidgetKit

/// Auto-detects the user's location (main app only) and writes the resolved place into settings so
/// the provider routes to Awqaf (UAE) or Aladhan (elsewhere). Manual mode skips all of this — the
/// user's explicit choice in Settings wins. Denied/failed resolution falls back to whatever is
/// already stored (default Dubai), so the app is never empty.
@MainActor
final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isResolving = false
    @Published private(set) var statusMessage: String?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Resolve on launch / when the user switches to auto. No-op in manual mode. On first run we
    /// do NOT trigger the system permission prompt here — the setup sheet does, so the user
    /// controls when it appears. We only refresh silently if permission is already granted.
    func resolveIfAuto() {
        guard AppSettings.locationMode == .auto else { return }
        if manager.authorizationStatus.grantsLocation { beginResolve() }
    }

    func beginResolve() {
        isResolving = true
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()      // delegate will request location on grant
        } else if status.grantsLocation {
            manager.requestLocation()
        } else if status == .denied || status == .restricted {
            isResolving = false
            statusMessage = "Location off — using \(ResolvedLocation.current().city ?? "Dubai")"
        } else {
            isResolving = false
        }
    }

    // MARK: - Applying a resolved location

    private func handle(latitude lat: Double, longitude lon: Double) async {
        defer { isResolving = false }

        var countryISO: String?
        var city: String?
        var tz: String?
        if let placemark = try? await geocoder.reverseGeocodeLocation(
            CLLocation(latitude: lat, longitude: lon)).first {
            countryISO = placemark.isoCountryCode
            city = placemark.locality ?? placemark.administrativeArea
            tz = placemark.timeZone?.identifier
        }

        if countryISO?.uppercased() == "AE" || Self.isWithinUAE(lat: lat, lon: lon) {
            let emirate = Emirate.nearest(toLatitude: lat, longitude: lon)
            store(uaeEmirate: emirate)
            statusMessage = "\(emirate.nameEn) · auto"
        } else {
            store(country: countryISO, city: city, lat: lat, lon: lon, tz: tz)
            statusMessage = "\(city ?? countryISO ?? "Location") · auto"
        }
        applyChange()
    }

    private func store(uaeEmirate emirate: Emirate) {
        let d = AppSettings.shared
        d.set(true, forKey: AppSettings.Keys.resolvedIsUAE)
        d.set(emirate.slug, forKey: AppSettings.Keys.selectedEmirate)
    }

    private func store(country iso: String?, city: String?, lat: Double, lon: Double, tz: String?) {
        let d = AppSettings.shared
        d.set(false, forKey: AppSettings.Keys.resolvedIsUAE)
        d.set(iso, forKey: AppSettings.Keys.selectedCountryISO)
        d.set(city, forKey: AppSettings.Keys.selectedCity)
        d.set(lat, forKey: AppSettings.Keys.selectedLatitude)
        d.set(lon, forKey: AppSettings.Keys.selectedLongitude)
        d.set(tz, forKey: AppSettings.Keys.selectedTimeZone)
    }

    /// Push the new source through the app + widget.
    func applyChange() {
        PrayerTimesService.shared.refreshProvider()
        CountdownManager.shared.refresh()
        AladhanSync.shared.syncIfNeeded()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Rough UAE bounding box, a backstop when reverse-geocoding yields no country code.
    private static func isWithinUAE(lat: Double, lon: Double) -> Bool {
        lat >= 22.5 && lat <= 26.5 && lon >= 51.0 && lon <= 56.5
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = self.manager.authorizationStatus
            let status = self.manager.authorizationStatus
            if status.grantsLocation {
                if AppSettings.locationMode == .auto { self.manager.requestLocation() }
            } else if status == .denied || status == .restricted {
                self.isResolving = false
                self.statusMessage = "Location access denied"
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let lat = loc.coordinate.latitude, lon = loc.coordinate.longitude
        Task { @MainActor in await self.handle(latitude: lat, longitude: lon) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isResolving = false
            self.statusMessage = "Couldn't determine location"
        }
    }
}

extension CLAuthorizationStatus {
    /// Whether the app may read location: "always", or — on iOS — "while in use".
    /// `.authorizedWhenInUse` doesn't exist on macOS; `.authorized` is the macOS equivalent.
    var grantsLocation: Bool {
        #if os(macOS)
        return self == .authorized || self == .authorizedAlways
        #else
        return self == .authorizedWhenInUse || self == .authorizedAlways
        #endif
    }
}
