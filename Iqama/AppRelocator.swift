#if os(macOS)
import AppKit

/// One-time self-migration of the on-disk app filename. Older builds shipped as
/// `Dubai iqama.app`; the product is now `Iqama.app`. New installs are already correct, but an
/// existing install that auto-updates keeps its old filename (the updater swaps the bundle in
/// place). On first launch of the new build we detect the legacy name, relocate the bundle to
/// `/Applications/Iqama.app`, remove the old folder, and relaunch — then it's a no-op forever.
///
/// The bundle identifier is unchanged, so this never affects update eligibility or user data.
enum AppRelocator {
    /// Returns true if it kicked off a relocation (the app is about to quit + relaunch).
    @discardableResult
    static func migrateIfNeeded() -> Bool {
        let url = Bundle.main.bundleURL

        // Only migrate the legacy-named bundle installed in /Applications. Dev builds
        // (DerivedData) and already-correct installs are left alone.
        guard url.lastPathComponent == "Dubai iqama.app",
              url.deletingLastPathComponent().path == "/Applications" else { return false }

        let target = URL(fileURLWithPath: "/Applications/Iqama.app")
        // Don't clobber an existing Iqama.app (e.g. a separate fresh install).
        guard !FileManager.default.fileExists(atPath: target.path) else { return false }

        return relocate(from: url, to: target)
    }

    private static func relocate(from old: URL, to new: URL) -> Bool {
        let pid = ProcessInfo.processInfo.processIdentifier
        // Wait for this process to quit, move the bundle, clear quarantine, relaunch. Falls back
        // to an admin prompt only if /Applications isn't writable without it.
        let script = """
        #!/bin/sh
        APP_PID="\(pid)"
        OLD="\(old.path)"
        NEW="\(new.path)"
        while kill -0 "$APP_PID" 2>/dev/null; do sleep 0.2; done
        if mv "$OLD" "$NEW" 2>/dev/null; then
            xattr -dr com.apple.quarantine "$NEW" 2>/dev/null
            open "$NEW"
        else
            osascript -e "do shell script \\"mv '$OLD' '$NEW'; xattr -dr com.apple.quarantine '$NEW'\\" with administrator privileges" && open "$NEW" || open "$OLD"
        fi
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("IqamaRelocate-\(UUID().uuidString).sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            task.arguments = ["/bin/sh", scriptURL.path]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try task.run()
        } catch {
            return false
        }

        // Quit so the helper can move us, then it relaunches the renamed bundle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        return true
    }
}
#endif
