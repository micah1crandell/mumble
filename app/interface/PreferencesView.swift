import SwiftUI

/// The few choices that shape how Mumble listens, edits, and waits in the background.
struct SettingsWindow: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Metric.large) {
                heading
                preferenceSection("Shortcut", icon: "command") {
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
                    .pickerStyle(.segmented)
                    note("Hold this key from any app. Mumble releases the focus back to your current text field.")
                }

                preferenceSection("Recognition", icon: "waveform") {
                    Picker("Engine", selection: $settings.engine) {
                        ForEach(SpeechEngineChoice.allCases, id: \.self) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    note(settings.engine == .apple
                        ? "Apple's local recognizer shows words while you speak."
                        : "Parakeet runs locally and resolves the full take when you release.")
                    Toggle("Compare both engines", isOn: $settings.compareMode)
                }

                preferenceSection("Finishing", icon: "wand.and.stars") {
                    Toggle("Clean up transcripts", isOn: $settings.cleanupEnabled)
                    Toggle("Use smart cleanup", isOn: $settings.smartCleanup)
                        .disabled(!FoundationModelFormatter.isAvailable)
                    if let reason = FoundationModelFormatter.unavailableReason {
                        note(reason)
                    }
                    note("Corrections in your dictionary always run after recognition.")
                }

                preferenceSection("Background", icon: "menubar.arrow.up.rectangle") {
                    Toggle("Open at Login", isOn: Binding(
                        get: { launchAtLogin },
                        set: { enabled in
                            _ = LaunchAtLogin.setEnabled(enabled)
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    ))
                    Toggle("Sound cues", isOn: $settings.soundEnabled)
                    note("Mumble stays in the menu bar and does not need its main window open.")
                }
            }
            .padding(AppStyle.Metric.section)
        }
        .background(AppWindowBackground())
        .frame(width: 560, height: 610)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: AppStyle.Metric.small) {
            Text("Preferences")
                .font(AppStyle.Font.display)
                .foregroundStyle(AppStyle.Color.ink)
            Text("Tune the parts of Mumble that follow you through the day.")
                .font(AppStyle.Font.body)
                .foregroundStyle(AppStyle.Color.muted)
        }
    }

    private func preferenceSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        AppSurface {
            VStack(alignment: .leading, spacing: AppStyle.Metric.standard) {
                Label(title, systemImage: icon)
                    .font(AppStyle.Font.title)
                    .foregroundStyle(AppStyle.Color.ink)
                content()
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(AppStyle.Font.caption)
            .foregroundStyle(AppStyle.Color.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
