import AppKit
import Carbon.HIToolbox
import Foundation

/// Which physical modifier keeps Mumble listening.
enum PushToTalkKey: String, CaseIterable, Sendable {
    case rightOption
    case fn
    case rightCommand

    var keyCode: Int64 {
        switch self {
        case .rightOption: Int64(kVK_RightOption)   // 61
        case .fn: Int64(kVK_Function)               // 63
        case .rightCommand: Int64(kVK_RightCommand) // 54
        }
    }

    /// Device-specific bit for this physical key.
    ///
    /// The public Option mask combines both sides. Using it would make a left Option key
    /// hide a right Option release, leaving capture open forever.
    ///
    /// These raw IOKit masks preserve the left/right distinction that public CGEvent flags
    /// intentionally flatten.
    var flag: CGEventFlags {
        switch self {
        case .rightOption: CGEventFlags(rawValue: 0x40)   // NX_DEVICERALTKEYMASK
        case .rightCommand: CGEventFlags(rawValue: 0x100) // NX_DEVICERCMDKEYMASK
        case .fn: .maskSecondaryFn                        // no left/right variant exists
        }
    }

    var displayName: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .fn: "fn"
        case .rightCommand: "Right ⌘"
        }
    }

    /// Fn has other macOS meanings, including navigation and the emoji picker, so its event
    /// continues through the system even when it is the configured trigger.
    var shouldConsumeEvent: Bool { self != .fn }
}

/// Watches one held modifier with a low-level `CGEventTap`.
///
/// The lower-level tap is necessary because higher-level monitors lose the Fn and
/// left/right details. macOS gates it behind Accessibility permission.
@MainActor
final class HotkeyMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false

    var key: PushToTalkKey = .rightOption
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    /// - Returns: `false` when macOS refuses the tap, usually before Accessibility is granted.
    @discardableResult
    func start() -> Bool {
        stop()

        let mask = (1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                // Extract plain values before crossing into actor-isolated code. The tap is
                // attached to the main run loop, so this callback is genuinely main-thread work.
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let consume = MainActor.assumeIsolated {
                    monitor.handle(type: type, keyCode: keyCode, flags: flags)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("tapCreate failed — Accessibility permission missing?")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Log.hotkey.info("listening for \(self.key.displayName)")
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isPressed = false
    }

    // MARK: - Event callback

    /// - Returns: `true` when the trigger event belongs to Mumble rather than the foreground app.
    private func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        // macOS disables a tap after a slow or interrupted callback; arm it again here.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        guard type == .flagsChanged, keyCode == key.keyCode else { return false }

        let nowPressed = flags.contains(key.flag)
        guard nowPressed != isPressed else { return false }
        isPressed = nowPressed

        if nowPressed { onPress?() } else { onRelease?() }

        return key.shouldConsumeEvent
    }
}
