import AppKit
import SwiftUI

@main
struct MumbleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        if AppBootstrap.relaunchInstalledAppIfNeeded() {
            exit(0)
        }
    }

    var body: some Scene {
        // The workspace is opt-in; the menu bar is the app's natural home.
        Window("Mumble", id: "main") {
            MainWindow(controller: delegate.controller)
        }
        .defaultSize(width: 860, height: 620)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Reveal Dictionary File") {
                    NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
                }
            }
        }

        // Spell this out because Mumble's preferences model shares SwiftUI's name.
        SwiftUI.Settings {
            SettingsWindow(controller: delegate.controller)
        }

        // Keep the everyday control surface in the menu bar, even when no window is open.
        MenuBarExtra {
            MenuContent(controller: delegate.controller)
        } label: {
            Image(systemName: delegate.controller.state.isActive ? "waveform.circle.fill" : "waveform")
        }

        Window("Signal Lab", id: "comparison") {
            ComparisonWindow(controller: delegate.controller)
        }
        .defaultSize(width: 640, height: 560)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    private var hud: HUDPanel?
    private var stateObservation: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Mumble stays out of the Dock. Its HUD floats without interrupting the app the
        // user is currently writing in.
        NSApp.setActivationPolicy(.accessory)
        LaunchAtLogin.enableByDefaultIfNeeded()

        hud = HUDPanel(controller: controller)

        if !controller.activate() {
            Permissions.promptForAccessibility()
            // macOS offers no callback for this grant, so keep checking until the shortcut
            // monitor can attach itself.
            retryActivation()
        }

        // A cold local model can make the first hold feel broken. Warm it quietly after
        // launch, but only when the user has chosen it and its files already exist.
        let willUseParakeet = Settings.shared.compareMode || Settings.shared.engine == .parakeet
        if willUseParakeet, ParakeetModels.isInstalled {
            Task.detached(priority: .utility) {
                _ = try? await ParakeetModels.shared.manager()
            }
        }

        // Reopen the measurement view if the user left it visible last time.
        if UserDefaults.standard.bool(forKey: "comparisonWindowOpen") {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                Self.showComparisonWindow()
            }
        }

        observeState()
            Log.app.info("Mumble ready — hold \(Settings.shared.pushToTalkKey.displayName) to dictate")
    }

    /// Handles the two small URL hooks used by local automation: `mumble://clear` and
    /// `mumble://show`.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "mumble" {
            switch url.host {
            case "clear":
                RunLog.clear()
                RunStore.shared.reload()
            case "show":
                Self.showComparisonWindow()
            default:
                break
            }
        }
    }

    /// Brings the measurement view forward from AppKit-owned entry points.
    static func showComparisonWindow() {
        RunStore.shared.reload()
        if let existing = NSApp.windows.first(where: { $0.title == "Signal Lab" }) {
            existing.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        let isOpen = NSApp.windows.contains { $0.title == "Signal Lab" && $0.isVisible }
        UserDefaults.standard.set(isOpen, forKey: "comparisonWindowOpen")
        controller.deactivate()
    }

    /// Keeps the floating readout synchronized with capture state.
    private func observeState() {
        withObservationTracking {
            _ = controller.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.controller.state.isActive {
                    self.hud?.present()
                } else {
                    self.hud?.dismiss()
                }
                self.observeState()
            }
        }
    }

    private func retryActivation() {
        Task { @MainActor in
            while !Permissions.hasAccessibility {
                try? await Task.sleep(for: .seconds(1))
            }
            while !controller.activate() {
                Log.hotkey.error("Accessibility is present, but the hotkey tap is not available; retrying")
                try? await Task.sleep(for: .seconds(1))
            }
            Log.app.info("Accessibility granted — hotkey armed")
        }
    }
}

private struct MenuContent: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @Environment(\.openWindow) private var openWindow
    @State private var isPreloadingParakeet = false
    @State private var parakeetOnDisk = ParakeetModels.isInstalled
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private var parakeetStatus: String {
        if isPreloadingParakeet { return "Loading Parakeet models…" }
        // Read the filesystem-backed truth, not a stale copy held by this menu.
        return parakeetOnDisk ? "Parakeet models installed ✓" : "Prepare Parakeet models…"
    }

    private func preloadParakeet() {
        guard !isPreloadingParakeet else { return }
        isPreloadingParakeet = true
        Task {
            do {
                _ = try await ParakeetModels.shared.manager()
                parakeetOnDisk = ParakeetModels.isInstalled
            } catch {
                Log.speech.error("Parakeet preload failed: \(error.localizedDescription)")
            }
            isPreloadingParakeet = false
        }
    }

    var body: some View {
        Text("Hold \(settings.pushToTalkKey.displayName) to dictate")

        Divider()

        Picker("Push-to-talk key", selection: Binding(
            get: { settings.pushToTalkKey },
            set: { key in
                settings.pushToTalkKey = key
                controller.reloadHotkey()
            }
        )) {
            ForEach(PushToTalkKey.allCases, id: \.self) { key in
                Text(key.displayName).tag(key)
            }
        }

        Toggle("Compare mode", isOn: $settings.compareMode)

        if !settings.compareMode {
            Picker("Engine", selection: $settings.engine) {
                ForEach(SpeechEngineChoice.allCases, id: \.self) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
        }

        Toggle("Clean up text", isOn: $settings.cleanupEnabled)

        if settings.cleanupEnabled {
            Toggle("Smart cleanup (on-device AI)", isOn: $settings.smartCleanup)
                .disabled(!FoundationModelFormatter.isAvailable)
            if let reason = FoundationModelFormatter.unavailableReason {
                Text(reason).font(.caption)
            }
        }

        Toggle("Sound", isOn: $settings.soundEnabled)

        Toggle("Open at Login", isOn: Binding(
            get: { launchAtLogin },
            set: { enabled in
                LaunchAtLogin.setEnabled(enabled)
                launchAtLogin = LaunchAtLogin.isEnabled
            }
        ))

        Divider()

        Button("Open Mumble") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Open Signal Lab") {
            RunStore.shared.reload()
            openWindow(id: "comparison")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("d")

        // Model preparation is substantial, so make it an explicit menu action instead of
        // hiding that wait inside the first dictation.
        if settings.engine == .parakeet {
            Button(parakeetStatus) { preloadParakeet() }
                .disabled(isPreloadingParakeet || parakeetOnDisk)
        }

        if !Permissions.hasAccessibility {
            Button("Grant Accessibility…") { Permissions.openAccessibilitySettings() }
        }
        if !Permissions.hasMicrophone {
            Button("Grant Microphone…") { Permissions.openMicrophoneSettings() }
        }

        Button("Quit Mumble") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
