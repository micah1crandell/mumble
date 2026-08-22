import AppKit
import SwiftUI

/// Mumble's optional desk: a place to revisit words and tune the local lexicon.
struct MainWindow: View {
    @Bindable var controller: DictationController
    @State private var section: Section = .history

    enum Section: String, CaseIterable, Identifiable {
        case history
        case dictionary

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var icon: String { self == .history ? "text.line.first.and.arrowtriangle.forward" : "character.book.closed" }
    }

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceRail(section: $section, controller: controller)
            Rectangle()
                .fill(AppStyle.Color.line)
                .frame(width: AppStyle.Metric.border)
            content
        }
        .background(AppWindowBackground())
        .frame(minWidth: 820, minHeight: 560)
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: AppStyle.Metric.large) {
            switch section {
            case .history:
                HistoryView(controller: controller)
            case .dictionary:
                DictionaryPanel()
            }
        }
        .padding(AppStyle.Metric.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WorkspaceRail: View {
    @Binding var section: MainWindow.Section
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Metric.large) {
            VStack(alignment: .leading, spacing: AppStyle.Metric.small) {
                Text("mumble")
                    .font(AppStyle.Font.display)
                    .foregroundStyle(AppStyle.Color.ink)
                Text("VOICE, MADE USEFUL")
                    .font(AppStyle.Font.caption)
                    .tracking(1.2)
                    .foregroundStyle(AppStyle.Color.teal)
            }

            Divider().overlay(AppStyle.Color.line)

            VStack(alignment: .leading, spacing: AppStyle.Metric.small) {
                AppLabel(text: "Workspace")
                ForEach(MainWindow.Section.allCases) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) { section = item }
                    } label: {
                        Label(item.title, systemImage: item.icon)
                            .font(AppStyle.Font.bodyStrong)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppStyle.Metric.standard)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(section == item ? AppStyle.Color.ink : AppStyle.Color.muted)
                    .background(section == item ? AppStyle.Color.surfaceMuted : .clear,
                                in: .rect(cornerRadius: AppStyle.Metric.smallRadius))
                }
            }

            Spacer()

            AppSurface(padding: AppStyle.Metric.standard) {
                VStack(alignment: .leading, spacing: AppStyle.Metric.small) {
                    HStack(spacing: AppStyle.Metric.small) {
                        Circle()
                            .fill(controller.state.isActive ? AppStyle.Color.coral : AppStyle.Color.teal)
                            .frame(width: 7, height: 7)
                        Text(controller.state.isActive ? "Listening" : "Ready")
                            .font(AppStyle.Font.bodyStrong)
                            .foregroundStyle(AppStyle.Color.ink)
                    }
                    Text("Hold \(settings.pushToTalkKey.displayName) anywhere")
                        .font(AppStyle.Font.caption)
                        .foregroundStyle(AppStyle.Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(AppStyle.Metric.large)
        .frame(width: 215)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct HistoryView: View {
    @Bindable var controller: DictationController
    @State private var store = RunStore.shared
    @State private var query = ""
    @State private var confirmingClear = false
    @State private var elapsed: TimeInterval = 0
    @State private var startedAt: Date?

    private var runs: [DictationRun] {
        let phrase = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ordered = store.runs.reversed()
        guard !phrase.isEmpty else { return Array(ordered) }
        return ordered.filter {
            $0.text.localizedStandardContains(phrase) || $0.engine.localizedStandardContains(phrase)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Metric.large) {
            header
            captureStrip
            if !Permissions.hasAccessibility { permissionNotice }
            AppSurface(padding: 0) {
                VStack(spacing: 0) {
                    SearchField(text: $query, placeholder: "Find a transcript")
                    if runs.isEmpty {
                        EmptyPanel(
                            label: store.runs.isEmpty ? "Your words will appear here" : "Nothing matched",
                            detail: store.runs.isEmpty
                                ? "Hold the push-to-talk key and speak into any app."
                                : "Try another word or clear the search."
                        )
                        .frame(minHeight: 250)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: AppStyle.Metric.small) {
                                ForEach(runs) { run in
                                    TranscriptRow(run: run) {
                                        withAnimation(.easeInOut(duration: 0.16)) { RunLog.delete(run) }
                                    }
                                }
                            }
                            .padding(AppStyle.Metric.standard)
                        }
                        .frame(minHeight: 270)
                    }
                    historyFooter
                }
            }
        }
        .onChange(of: controller.state.isActive) { _, active in
            startedAt = active ? Date() : nil
            if !active { elapsed = 0 }
        }
        .task(id: startedAt) {
            guard let startedAt else { return }
            while !Task.isCancelled {
                elapsed = Date().timeIntervalSince(startedAt)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: AppStyle.Metric.small) {
                Text("History")
                    .font(AppStyle.Font.display)
                    .foregroundStyle(AppStyle.Color.ink)
                Text("A quiet record of everything Mumble has delivered.")
                    .font(AppStyle.Font.body)
                    .foregroundStyle(AppStyle.Color.muted)
            }
            Spacer()
            Text("\(store.runs.count) TAKE\(store.runs.count == 1 ? "" : "S")")
                .font(AppStyle.Font.caption)
                .tracking(0.7)
                .foregroundStyle(AppStyle.Color.muted)
        }
    }

    private var captureStrip: some View {
        HStack(spacing: AppStyle.Metric.large) {
            AppActionButton(
                title: controller.state.isActive ? "Stop" : "Record",
                systemImage: controller.state.isActive ? "stop.fill" : "mic.fill",
                prominent: true
            ) {
                if controller.state.isActive {
                    controller.stopButtonRecording()
                } else {
                    controller.startButtonRecording()
                }
            }

            VStack(alignment: .leading, spacing: AppStyle.Metric.small) {
                AppLabel(text: controller.state.isActive ? "Live capture" : "Ready when you are",
                         color: controller.state.isActive ? AppStyle.Color.coral : AppStyle.Color.muted)
                Text(controller.state.isActive ? "Listening for a clean handoff" : "The global shortcut works from any app")
                    .font(AppStyle.Font.body)
                    .foregroundStyle(AppStyle.Color.ink)
            }
            Spacer()
            Text(String(format: "%02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60))
                .font(AppStyle.Font.mono)
                .foregroundStyle(AppStyle.Color.ink)
                .padding(.horizontal, AppStyle.Metric.standard)
                .padding(.vertical, 9)
                .background(AppStyle.Color.surfaceMuted, in: .rect(cornerRadius: AppStyle.Metric.smallRadius))
        }
        .padding(AppStyle.Metric.standard)
        .background(AppStyle.Color.surface, in: .rect(cornerRadius: AppStyle.Metric.radius))
        .overlay { RoundedRectangle(cornerRadius: AppStyle.Metric.radius).strokeBorder(AppStyle.Color.line) }
    }

    private var permissionNotice: some View {
        HStack(spacing: AppStyle.Metric.standard) {
            Image(systemName: "lock.open")
                .foregroundStyle(AppStyle.Color.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Shortcut access is off")
                    .font(AppStyle.Font.bodyStrong)
                    .foregroundStyle(AppStyle.Color.ink)
                Text("Allow Mumble in System Settings to listen outside this window.")
                    .font(AppStyle.Font.caption)
                    .foregroundStyle(AppStyle.Color.muted)
            }
            Spacer()
            Button("Open Settings") { Permissions.openAccessibilitySettings() }
                .buttonStyle(.bordered)
        }
        .padding(AppStyle.Metric.standard)
        .background(AppStyle.Color.surface, in: .rect(cornerRadius: AppStyle.Metric.smallRadius))
        .overlay { RoundedRectangle(cornerRadius: AppStyle.Metric.smallRadius).strokeBorder(AppStyle.Color.gold.opacity(0.45)) }
    }

    private var historyFooter: some View {
        HStack {
            Text("Stored locally on this Mac")
                .font(AppStyle.Font.caption)
                .foregroundStyle(AppStyle.Color.muted)
            Spacer()
            if !store.runs.isEmpty {
                Button("Clear history") { confirmingClear = true }
                    .buttonStyle(.plain)
                    .font(AppStyle.Font.caption)
                    .foregroundStyle(AppStyle.Color.coral)
                    .confirmationDialog("Clear every saved transcript?", isPresented: $confirmingClear) {
                        Button("Clear History", role: .destructive) { RunLog.clear() }
                        Button("Cancel", role: .cancel) {}
                    }
            }
        }
        .padding(.horizontal, AppStyle.Metric.standard)
        .padding(.vertical, AppStyle.Metric.standard)
        .background(AppStyle.Color.surfaceMuted)
    }
}

private struct TranscriptRow: View {
    let run: DictationRun
    let onDelete: () -> Void
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Metric.standard) {
            HStack(alignment: .firstTextBaseline) {
                Text(run.engine)
                    .font(AppStyle.Font.bodyStrong)
                    .foregroundStyle(AppStyle.Color.ink)
                Text(run.date, style: .relative)
                    .font(AppStyle.Font.caption)
                    .foregroundStyle(AppStyle.Color.muted)
                Spacer()
                Text(String(format: "%.2fs", run.processSeconds))
                    .font(AppStyle.Font.mono)
                    .foregroundStyle(AppStyle.Color.muted)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(run.text, forType: .string)
                    didCopy = true
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "square.on.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(didCopy ? AppStyle.Color.teal : AppStyle.Color.muted)
                .help("Copy transcript")
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppStyle.Color.muted)
                    .help("Delete transcript")
            }

            Text(run.text.isEmpty ? "(nothing heard)" : run.text)
                .font(AppStyle.Font.body)
                .foregroundStyle(run.text.isEmpty ? AppStyle.Color.muted : AppStyle.Color.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let corrections = run.corrections, !corrections.isEmpty {
                HStack(spacing: AppStyle.Metric.small) {
                    Image(systemName: "wand.and.stars")
                    Text("\(corrections.count) dictionary change\(corrections.count == 1 ? "" : "s")")
                }
                .font(AppStyle.Font.caption)
                .foregroundStyle(AppStyle.Color.gold)
            }
        }
        .padding(AppStyle.Metric.standard)
        .background(AppStyle.Color.surfaceMuted, in: .rect(cornerRadius: AppStyle.Metric.smallRadius))
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: AppStyle.Metric.standard) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppStyle.Color.muted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(AppStyle.Font.body)
                .foregroundStyle(AppStyle.Color.ink)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppStyle.Color.muted)
            }
        }
        .padding(AppStyle.Metric.standard)
        .background(AppStyle.Color.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(AppStyle.Color.line).frame(height: 1) }
    }
}

struct EmptyPanel: View {
    let label: String
    let detail: String

    var body: some View {
        VStack(spacing: AppStyle.Metric.small) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(AppStyle.Color.teal)
            Text(label)
                .font(AppStyle.Font.title)
                .foregroundStyle(AppStyle.Color.ink)
            Text(detail)
                .font(AppStyle.Font.body)
                .foregroundStyle(AppStyle.Color.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppStyle.Metric.section)
    }
}
