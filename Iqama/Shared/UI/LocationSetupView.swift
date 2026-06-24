import SwiftUI
import CoreLocation

/// First-run location flow: ask permission → show what was detected → let the user confirm it or
/// pick a location manually. Shown until `locationConfirmed` is set; the user can always change it
/// later in Settings. The system permission prompt is only triggered when the user taps
/// "Use my location" here, so they're never surprised by it on launch.
struct LocationSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var location = LocationManager.shared

    @AppStorage(AppSettings.Keys.locationConfirmed, store: AppSettings.shared)
    private var confirmed = false
    @AppStorage(AppSettings.Keys.locationMode, store: AppSettings.shared)
    private var mode = AppSettings.Defaults.locationMode
    @AppStorage(AppSettings.Keys.resolvedIsUAE, store: AppSettings.shared)
    private var isUAE = true
    @AppStorage(AppSettings.Keys.selectedEmirate, store: AppSettings.shared)
    private var emirateSlug = AppSettings.Defaults.selectedEmirate
    @AppStorage(AppSettings.Keys.selectedCountryISO, store: AppSettings.shared)
    private var countryISO = "GB"
    @AppStorage(AppSettings.Keys.selectedCity, store: AppSettings.shared)
    private var city = ""

    @State private var useManual = false

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.tint)
                Text("Set your location")
                    .font(.title2.weight(.semibold))
                Text("Iqama shows accurate prayer times for where you are — official Awqaf data inside the UAE, the Aladhan API elsewhere.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            autoCard
            manualCard

            HStack {
                Button("Skip") { confirm() }
                    .help("Use the automatic / default location")
                Spacer()
                Button("Confirm") { confirm() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 460)
        #endif
        .interactiveDismissDisabled(true)
    }

    // MARK: - Auto

    private var autoCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if location.authorizationStatus.grantsLocation {
                    if location.isResolving {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Finding your location…").foregroundStyle(.secondary)
                        }
                    } else {
                        Label(location.statusMessage ?? "Located", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button("Update location") { location.beginResolve() }
                } else if location.authorizationStatus == .denied || location.authorizationStatus == .restricted {
                    Label("Location access is off", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Turn it on to auto-detect your location, or choose it manually below.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Location Settings…") { Self.openLocationSettings() }
                } else {
                    Text("Detect your nearest emirate (in the UAE) or your city automatically.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Use my location") { location.beginResolve() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Automatic", systemImage: "location.fill")
        }
    }

    // MARK: - Manual

    private var manualCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Choose manually", isOn: $useManual.animation())
                if useManual {
                    Picker("Region", selection: $isUAE) {
                        Text("United Arab Emirates").tag(true)
                        Text("Another country").tag(false)
                    }
                    if isUAE {
                        Picker("Emirate", selection: $emirateSlug) {
                            ForEach(Emirate.allCases) { Text($0.nameEn).tag($0.slug) }
                        }
                    } else {
                        Picker("Country", selection: $countryISO) {
                            ForEach(Countries.list, id: \.iso) { Text($0.name).tag($0.iso) }
                        }
                        TextField("City", text: $city)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Manual", systemImage: "hand.tap.fill")
        }
    }

    // MARK: - Confirm

    private func confirm() {
        mode = useManual ? AppSettings.LocationMode.manual.rawValue
                         : AppSettings.LocationMode.auto.rawValue
        confirmed = true
        LocationManager.shared.applyChange()
        if !useManual { LocationManager.shared.resolveIfAuto() }
        dismiss()
    }

    /// Open the system Location settings (macOS Privacy pane; iOS app settings page).
    static func openLocationSettings() {
        PlatformSupport.openLocationSettings()
    }
}
