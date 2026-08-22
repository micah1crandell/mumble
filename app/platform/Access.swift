import AVFoundation
import AppKit
import ApplicationServices
import Foundation

/// Mumble needs two macOS grants:
/// - **Microphone** — to hear a held shortcut.
/// - **Accessibility** — to notice the shortcut and return text to another app.
///
/// Accessibility is ultimately a System Settings decision. TCC also binds that decision to
/// the signed app identity, which is why local packaging uses a stable signature.
@MainActor
enum Permissions {
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    static var hasMicrophone: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Ask macOS to surface the Accessibility permission panel when needed.
    @discardableResult
    static func promptForAccessibility() -> Bool {
        // Use the documented key directly; the imported global is treated as shared mutable
        // state by Swift 6's concurrency checker.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}
