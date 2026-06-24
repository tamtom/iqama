#if os(macOS)
import Foundation
import AppKit
import Combine

// In-app updater: downloads the release DMG, verifies it's our notarized,
// Developer-ID-signed build, swaps the running .app bundle, and relaunches —
// the same flow Sparkle automates, implemented directly. Requires the app to
// be NON-sandboxed (it writes to /Applications and spawns a helper); the
// widget extension stays sandboxed.
@MainActor
final class UpdateInstaller: ObservableObject {
    static let shared = UpdateInstaller()

    enum Phase: Equatable {
        case idle
        case downloading(Double)   // 0...1
        case verifying
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    // Only accept builds signed by our own Developer ID team.
    private let expectedTeamID = "W5THJP5XXD"

    private init() {}

    var isWorking: Bool {
        switch phase {
        case .idle, .failed: return false
        default: return true
        }
    }

    func install(_ update: UpdateChecker.UpdateInfo) {
        guard !isWorking else { return }
        guard let dmgURL = update.dmgURL else {
            // No direct asset — fall back to opening the release page.
            NSWorkspace.shared.open(update.htmlURL)
            return
        }
        Task { await run(dmgURL: dmgURL) }
    }

    private func run(dmgURL: URL) async {
        do {
            phase = .downloading(0)
            let dmgPath = try await download(dmgURL)

            phase = .verifying
            let mountPoint = try mountDMG(dmgPath)
            defer { try? detachDMG(mountPoint) }

            let appInDMG = try locateApp(in: mountPoint)
            try verify(appInDMG)

            // Stage a copy outside the DMG so we can unmount before swapping.
            let staged = try stageCopy(of: appInDMG)
            try? detachDMG(mountPoint)

            phase = .installing
            try swapAndRelaunch(newApp: staged)
            // swapAndRelaunch terminates the app on success; we won't return.
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Download (with progress)

    private func download(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("Dubai-Iqama", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120

        // Fetch the whole asset in one request. We deliberately do NOT use
        // `URLSession.bytes` + `for await byte`: that yields a single UInt8 per
        // iteration, and because this type is @MainActor every byte became an
        // await hop back to the main thread — ~1.3M of them for a 1.3 MB DMG, so
        // a sub-second download took *minutes* with the network barely involved.
        // `data(for:)` does the transfer off-actor and resumes us once. The DMG
        // is ~1.3 MB, so holding it in memory briefly is fine.
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Err("Download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
        phase = .downloading(1.0)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("DubaiIqamaUpdate-\(UUID().uuidString).dmg")
        try data.write(to: tmp)
        return tmp
    }

    // MARK: - DMG handling

    private func mountDMG(_ dmg: URL) throws -> URL {
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("DubaiIqamaMount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let r = run("/usr/bin/hdiutil", [
            "attach", dmg.path,
            "-nobrowse", "-noautoopen", "-readonly",
            "-mountpoint", mountPoint.path,
        ])
        guard r.status == 0 else { throw Err("Couldn't mount the update image.") }
        return mountPoint
    }

    private func detachDMG(_ mountPoint: URL) throws {
        _ = run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
    }

    private func locateApp(in mountPoint: URL) throws -> URL {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: mountPoint, includingPropertiesForKeys: nil)) ?? []
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw Err("No app found inside the update image.")
        }
        return app
    }

    // MARK: - Security verification

    private func verify(_ app: URL) throws {
        // 1) Code signature is valid and intact.
        let cs = run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        guard cs.status == 0 else { throw Err("The update isn't properly signed.") }

        // 2) Gatekeeper accepts it (i.e. it is notarized).
        let gk = run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
        guard gk.status == 0 else { throw Err("The update isn't notarized by Apple.") }

        // 3) Team identifier matches ours — refuse anything else.
        let info = run("/usr/bin/codesign", ["-dv", "--verbose=4", app.path])
        let combined = info.out + info.err
        guard combined.contains("TeamIdentifier=\(expectedTeamID)") else {
            throw Err("The update was signed by an unexpected developer.")
        }
    }

    private func stageCopy(of app: URL) throws -> URL {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("DubaiIqamaStaged-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let appCopy = dest.appendingPathComponent(app.lastPathComponent)
        try FileManager.default.copyItem(at: app, to: appCopy)
        return appCopy
    }

    // MARK: - Swap & relaunch

    private func swapAndRelaunch(newApp: URL) throws {
        let target = Bundle.main.bundleURL                 // e.g. /Applications/Dubai iqama.app
        let pid = ProcessInfo.processInfo.processIdentifier

        // Helper script: wait for us to quit, swap the bundle atomically,
        // clear quarantine (already notarized), relaunch. Falls back to an
        // admin prompt only if a plain copy is denied.
        let script = """
        #!/bin/sh
        APP_PID="\(pid)"
        NEW_APP="\(newApp.path)"
        TARGET="\(target.path)"

        while kill -0 "$APP_PID" 2>/dev/null; do sleep 0.2; done

        swap() {
            rm -rf "$TARGET.old" 2>/dev/null
            cp -R "$NEW_APP" "$TARGET.new" || return 1
            mv "$TARGET" "$TARGET.old" 2>/dev/null
            mv "$TARGET.new" "$TARGET" || { mv "$TARGET.old" "$TARGET" 2>/dev/null; return 1; }
            rm -rf "$TARGET.old" 2>/dev/null
            xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
            return 0
        }

        if ! swap; then
            osascript -e "do shell script \\"rm -rf '$TARGET'; cp -R '$NEW_APP' '$TARGET'; xattr -dr com.apple.quarantine '$TARGET'\\" with administrator privileges" || exit 1
        fi

        open "$TARGET"
        rm -rf "$(dirname "$NEW_APP")"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DubaiIqamaInstall-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        // Launch detached via nohup so it survives our termination.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        task.arguments = ["/bin/sh", scriptURL.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()

        // Give the helper a beat to start, then quit so it can swap us.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Process helper

    @discardableResult
    private func run(_ launchPath: String, _ args: [String]) -> (status: Int32, out: String, err: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do { try task.run() } catch { return (-1, "", "\(error)") }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus,
                String(data: outData, encoding: .utf8) ?? "",
                String(data: errData, encoding: .utf8) ?? "")
    }

    private struct Err: LocalizedError {
        let msg: String
        init(_ m: String) { msg = m }
        var errorDescription: String? { msg }
    }
}
#endif
