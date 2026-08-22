import SwiftUI

/// A local listening bench for comparing both engines against the same captured take.
struct ComparisonWindow: View {
    @Bindable var controller: DictationController
    @State private var store = RunStore.shared
    @State private var settings = Settings.shared
    @State private var confirmingClear = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.Metric.large) {
                header
                recordBar
                if store.runs.isEmpty {
                    EmptyPanel(
                        label: "No comparison takes yet",
                        detail: "Record a short phrase to see how Apple's and Mumble's local engine differ."
                    )
                } else {
                    ForEach(Array(store.comparisons.enumerated()), id: \.offset) { _, group in
                        ComparisonCard(runs: group)
                    }
                    ForEach(store.singles) { run in
                        SingleCard(run: run)
                    }
                }
            }
            .padding(AppStyle.Metric.section)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 620, minHeight: 450)
        .background(AppWindowBackground())
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: AppStyle.Metric.small) {
                Text("Signal Lab")
                    .font(AppStyle.Font.display)
                    .foregroundStyle(AppStyle.Color.ink)
                Text("Compare local recognition on the same take.")
                    .font(AppStyle.Font.body)
                    .foregroundStyle(AppStyle.Color.muted)
            }
            Spacer()
            if !store.runs.isEmpty {
                Button("Clear results") { confirmingClear = true }
                    .buttonStyle(.bordered)
                    .confirmationDialog("Clear every comparison result?", isPresented: $confirmingClear) {
                        Button("Clear Results", role: .destructive) { RunLog.clear() }
                        Button("Cancel", role: .cancel) {}
                    }
            }
        }
    }

    private var recordBar: some View {
        let isRecording = controller.state.isActive
        return AppSurface {
            VStack(alignment: .leading, spacing: AppStyle.Metric.standard) {
                HStack(spacing: AppStyle.Metric.standard) {
                    AppActionButton(
                        title: isRecording ? "Stop" : "Record comparison",
                        systemImage: isRecording ? "stop.fill" : "waveform.and.mic",
                        prominent: true
                    ) {
                        if isRecording { controller.stopButtonRecording() }
                        else { controller.startButtonRecording() }
                    }
                    Spacer()
                    Text(isRecording ? "CAPTURING" : "READY")
                        .font(AppStyle.Font.caption)
                        .tracking(0.8)
                        .foregroundStyle(isRecording ? AppStyle.Color.coral : AppStyle.Color.teal)
                }
                Text(statusLine(isRecording: isRecording))
                    .font(AppStyle.Font.body)
                    .foregroundStyle(AppStyle.Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statusLine(isRecording: Bool) -> String {
        if isRecording { return "Speak naturally, then stop to process this take." }
        if !controller.transcript.isEmpty { return controller.transcript }
        return "Both engines receive the same captured audio. Results stay here and are never injected."
    }
}

private struct ComparisonCard: View {
    let runs: [DictationRun]

    private var ranked: [DictationRun] { runs.sorted { $0.processSeconds < $1.processSeconds } }

    private var verdict: (String, SwiftUI.Color) {
        let normalized = Set(runs.map { $0.text.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ") })
        return normalized.count == 1 ? ("same words", AppStyle.Color.teal) : ("words differ", AppStyle.Color.coral)
    }

    private var margin: String? {
        guard let best = ranked.first, let slowest = ranked.last, runs.count > 1 else { return nil }
        let delta = slowest.processSeconds - best.processSeconds
        guard delta > 0.005 else { return "nearly tied" }
        return String(format: "%@ finished %.2fs sooner", best.engine, delta)
    }

    var body: some View {
        AppSurface {
            VStack(alignment: .leading, spacing: AppStyle.Metric.standard) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        AppLabel(text: runs.first?.date.formatted(date: .abbreviated, time: .shortened) ?? "Take")
                        Text("\(runs.first?.audioSeconds ?? 0, format: .number.precision(.fractionLength(1))) seconds captured")
                            .font(AppStyle.Font.body)
                            .foregroundStyle(AppStyle.Color.ink)
                    }
                    Spacer()
                    Text(verdict.0)
                        .font(AppStyle.Font.caption)
                        .foregroundStyle(verdict.1)
                }
                if let margin {
                    Label(margin, systemImage: "timer")
                        .font(AppStyle.Font.caption)
                        .foregroundStyle(AppStyle.Color.gold)
                } else if runs.count == 1 {
                    Label("Waiting for the second engine", systemImage: "hourglass")
                        .font(AppStyle.Font.caption)
                        .foregroundStyle(AppStyle.Color.muted)
                }
                Divider().overlay(AppStyle.Color.line)
                ForEach(ranked) { run in EngineRow(run: run, isWinner: run.id == ranked.first?.id) }
                if let group = runs.first?.group {
                    HStack {
                        Spacer()
                        Button("Delete take", role: .destructive) { RunLog.deleteGroup(group) }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}

private struct EngineRow: View {
    let run: DictationRun
    let isWinner: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.Metric.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(run.engine)
                    .font(AppStyle.Font.bodyStrong)
                    .foregroundStyle(AppStyle.Color.ink)
                if isWinner {
                    Text("fastest")
                        .font(AppStyle.Font.caption)
                        .foregroundStyle(AppStyle.Color.teal)
                }
                Spacer()
                Text("\(run.processSeconds, format: .number.precision(.fractionLength(2)))s")
                    .font(AppStyle.Font.mono)
                    .foregroundStyle(isWinner ? AppStyle.Color.teal : AppStyle.Color.muted)
            }
            Text("\(run.realtimeFactor, format: .number.precision(.fractionLength(0)))x realtime · \(run.characters) characters")
                .font(AppStyle.Font.caption)
                .foregroundStyle(AppStyle.Color.muted)
            Text(run.text.isEmpty ? "(nothing recognized)" : run.text)
                .font(AppStyle.Font.body)
                .foregroundStyle(run.text.isEmpty ? AppStyle.Color.muted : AppStyle.Color.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppStyle.Metric.standard)
        .background(AppStyle.Color.surfaceMuted, in: .rect(cornerRadius: AppStyle.Metric.smallRadius))
    }
}

private struct SingleCard: View {
    let run: DictationRun

    var body: some View {
        AppSurface {
            VStack(alignment: .leading, spacing: AppStyle.Metric.small) {
                HStack {
                    Text(run.engine).font(AppStyle.Font.bodyStrong).foregroundStyle(AppStyle.Color.ink)
                    Spacer()
                    Text("\(run.processSeconds, format: .number.precision(.fractionLength(2)))s")
                        .font(AppStyle.Font.mono)
                        .foregroundStyle(AppStyle.Color.muted)
                }
                Text(run.text).font(AppStyle.Font.body).foregroundStyle(AppStyle.Color.ink).textSelection(.enabled)
            }
        }
    }
}
