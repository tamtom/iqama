#if os(macOS)
import AppKit
import SwiftUI
import Combine

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        setupStatusItem()
        setupPopover()
        observeCountdownUpdates()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            updateButtonTitle(with: "Loading...")
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 520)
        popover.behavior = .transient
        // Vibrant dark chrome so the wallpaper blur behind it tints toward
        // our dark celestial palette instead of fighting it.
        popover.appearance = NSAppearance(named: .vibrantDark)
        popover.contentViewController = NSHostingController(
            rootView: StatusBarMenuView()
        )
    }

    private func observeCountdownUpdates() {
        Task { @MainActor in
            CountdownManager.shared.$currentState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] snapshot in
                    self?.updateStatusBarDisplay(with: snapshot)
                }
                .store(in: &cancellables)
        }
    }

    private func updateStatusBarDisplay(with snapshot: CountdownSnapshot?) {
        updateButtonTitle(with: snapshot?.statusBarText ?? "Prayer")
    }

    // The countdown publishes every second, but the menu-bar text is
    // minute-resolution — skip the AppKit work unless it actually changed so a
    // backgrounded menu-bar app isn't rebuilding its button title 60×/minute.
    private var lastTitle: String?
    private lazy var templateImage: NSImage? = {
        let image = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: "Prayer")
        image?.isTemplate = true
        return image
    }()

    private func updateButtonTitle(with title: String) {
        guard title != lastTitle, let button = statusItem.button else { return }
        lastTitle = title
        button.image = templateImage
        button.imagePosition = .imageLeading
        button.title = " \(title)"
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
}
#endif
