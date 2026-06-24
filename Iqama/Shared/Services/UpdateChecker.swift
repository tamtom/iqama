#if os(macOS)
import Foundation
import Combine

// Lightweight update checker. Polls the GitHub Releases API on launch and once
// per day; if the latest published release is newer than the running build, it
// publishes an `availableUpdate` that the UI surfaces as a banner. There is no
// in-app installer — the banner links to the release page where the user
// downloads the new DMG (Option B: no third-party framework).
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct UpdateInfo: Equatable {
        let version: String        // e.g. "1.1.0"
        let htmlURL: URL           // release page (fallback if no DMG asset)
        let dmgURL: URL?           // direct .dmg download for in-app install
        let notes: String          // release body (may be empty)
    }

    @Published private(set) var availableUpdate: UpdateInfo?

    private let owner = "tamtom"
    // Repo was renamed dubai-iqama → iqama. New builds poll the new URL directly; already-shipped
    // builds poll the old URL and rely on GitHub's permanent redirect (do not re-create a
    // `dubai-iqama` repo, or that redirect breaks).
    private let repo = "iqama"
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private var timer: Timer?

    private init() {}

    // Call once at launch. Fires an immediate check, then every 24h.
    func start() {
        Task { await self.check() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { await self?.check() }
        }
    }

    func check() async {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Iqama", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else { return }
            if release.draft || release.prerelease { return }

            let latest = Self.normalize(release.tagName)
            let current = Self.normalize(Self.currentVersion)

            if Self.isVersion(latest, newerThan: current),
               let html = URL(string: release.htmlURL) {
                let dmg = release.assets
                    .first { $0.name.lowercased().hasSuffix(".dmg") }
                    .flatMap { URL(string: $0.browserDownloadURL) }
                self.availableUpdate = UpdateInfo(
                    version: latest,
                    htmlURL: html,
                    dmgURL: dmg,
                    notes: release.body ?? ""
                )
            } else {
                self.availableUpdate = nil
            }
        } catch {
            // Offline / rate-limited / transient — leave state unchanged.
        }
    }

    // MARK: - Version helpers

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    // Strip a leading "v" and any non-version suffix.
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    // Compare dotted numeric versions component by component. Missing
    // components are treated as 0 ("1.1" == "1.1.0").
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(pa.count, pb.count)
        for i in 0..<n {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body, draft, prerelease, assets
    }
}
#endif
