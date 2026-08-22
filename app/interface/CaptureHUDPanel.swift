import AppKit
import SwiftUI

/// The readout that follows a held shortcut without taking ownership of keyboard focus.
///
/// That focus rule is the heart of the interaction: the text destination must remain the
/// user's app, not Mumble. `.nonactivatingPanel` and the two `canBecome` overrides enforce it.
@MainActor
final class HUDPanel: NSPanel {
    init(controller: DictationController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = true

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        contentView = NSHostingView(rootView: HUDView(controller: controller))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Places the readout just above the Dock and centers it on the active display.
    /// An accessory app has no key window of its own, so fall back to the first display
    /// when `NSScreen.main` is unavailable.
    func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            Log.app.error("no screen available to position HUD")
            return
        }
        let visible = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.minY + 96
            )
        )
    }

    func present() {
        // Capture changes state more than once per hold. Do not restart the fade while the
        // same utterance is still visible.
        guard !isVisible || alphaValue < 1 else { return }

        reposition()
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // The panel is main-actor isolated, so finish the dismissal on that actor.
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
    }
}
