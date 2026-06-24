#if os(macOS)
import SwiftUI
import AppKit

// Bridges to NSVisualEffectView with `behindWindow` blending so the macOS
// desktop wallpaper (and anything else behind the window) shows through and
// gets the system blur. Pair with WindowTransparencyConfigurator to make the
// NSWindow itself non-opaque — without that, the window stays solid.
struct WindowBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// Reaches up the AppKit window hierarchy on first appear and makes the host
// NSWindow non-opaque, transparent-titlebar, full-size-content. This is what
// lets the underlying WindowBackdrop view actually show the desktop.
struct WindowTransparencyConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
