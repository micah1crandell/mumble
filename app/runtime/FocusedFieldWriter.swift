import AppKit
import ApplicationServices
import Foundation

/// Returns finished text to the field that had focus before Mumble appeared.
///
/// Try direct Accessibility insertion first, then use a temporary pasteboard and ⌘V for
/// apps whose Accessibility layer reports success without actually changing their field.
///
/// A successful AX call is not proof that text landed. Some apps acknowledge the write and
/// silently discard it, so direct insertion is trusted only when the caret visibly moves.
///
/// The non-activating HUD is what makes this possible: the user's field remains focused
/// while Mumble listens.
@MainActor
enum TextInjector {
    static func insert(_ text: String) {
        guard !text.isEmpty else { return }

        switch insertViaAccessibility(text) {
        case .inserted:
            Log.inject.info("inserted via AX (\(text.count) chars)")
        case .unverified(let reason):
            Log.inject.info("AX insert not verified (\(reason, privacy: .public)) — pasting")
            insertViaPasteboard(text)
        }
    }

    private enum AXOutcome {
        case inserted
        case unverified(String)
    }

    // MARK: - Direct insert, verified

    private static func insertViaAccessibility(_ text: String) -> AXOutcome {
        let systemWide = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success, let focused else {
            return .unverified("no focused element")
        }

        let element = unsafeDowncast(focused as AnyObject, to: AXUIElement.self)

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        ) == .success, settable.boolValue else {
            return .unverified("selected text not settable")
        }

        // Without a readable caret there is no proof of insertion, so use the fallback.
        guard let before = selectedRange(of: element) else {
            return .unverified("no readable selection range")
        }

        guard AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success else {
            return .unverified("set attribute failed")
        }

        guard let after = selectedRange(of: element) else {
            return .unverified("selection range unreadable after write")
        }

        // Check movement, not an exact character count. Target apps may normalize newlines
        // or autocorrect, and a fallback after a successful write would duplicate the text.
        let unchanged = after.location == before.location && after.length == before.length
        guard !unchanged else {
            return .unverified("selection unmoved at \(before.location)")
        }

        return .inserted
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success, let value else { return nil }

        let axValue = unsafeDowncast(value as AnyObject, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    // MARK: - Pasteboard fallback

    private static func insertViaPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data] in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { copy[type] = data }
            }
            return copy
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        Task { @MainActor in
            // Let the target app observe the new pasteboard before sending ⌘V.
            try? await Task.sleep(for: .milliseconds(40))
            postCommandV()
            Log.inject.info("pasted (\(text.count) chars)")

            // Restore the user's pasteboard after the target has had time to consume it.
            try? await Task.sleep(for: .milliseconds(500))
            restore(saved, to: pasteboard)
        }
    }

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .privateState) else { return }
        let vKey: CGKeyCode = 9 // kVK_ANSI_V

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }

        // Set the command flag explicitly; the held trigger key may still be down.
        down.flags = .maskCommand
        up.flags = .maskCommand

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static func restore(
        _ saved: [[NSPasteboard.PasteboardType: Data]]?,
        to pasteboard: NSPasteboard
    ) {
        guard let saved, !saved.isEmpty else { return }
        pasteboard.clearContents()
        let items = saved.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
