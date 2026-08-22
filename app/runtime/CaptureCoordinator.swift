import MumbleDictionary
import AVFoundation
import AppKit
import Foundation
import Observation

/// Selects the recognizer for each new hold. Keeping this outside the main-actor controller
/// lets the selected factory cross into the capture task safely.
@Sendable
func engineForCurrentSetting() -> any TranscriptionEngine {
    // The controller calls this from its main-actor capture start.
    MainActor.assumeIsolated {
        switch Settings.shared.engine {
        case .apple: AppleSpeechEngine()
        case .parakeet: ParakeetEngine()
        }
    }
}

@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle
        case starting
        case listening
        case finishing
        case error(String)

        var isActive: Bool {
            switch self {
            case .starting, .listening, .finishing: true
            case .idle, .error: false
            }
        }
    }

    private(set) var state: State = .idle
    /// Current replacement text for the floating readout.
    private(set) var transcript = ""
    /// Smoothed microphone level for the waveform.
    private(set) var level: Float = 0

    private let hotkey = HotkeyMonitor()
    private let capture = AudioCapture()
    private let makeEngine: @Sendable () -> any TranscriptionEngine

    /// Test hook for deterministic text finishing.
    private let formatter: (any TextFormatter)?

    /// Chosen at hold time so a menu change applies immediately.
    private var activeFormatter: any TextFormatter {
        if let formatter { return formatter }
        return Settings.shared.smartCleanup
            ? FoundationModelFormatter()
            : RuleBasedFormatter()
    }

    private var engine: (any TranscriptionEngine)?
    private var consumeTask: Task<Void, Never>?
    /// Captured chunks retained for the measurement pass, when enabled.
    private var feedTask: Task<[AudioChunk], Never>?
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?

    /// Timestamps used for hold duration and release latency.
    private var holdStarted: Date?
    private var releasedAt: Date?
    private var engineName = ""

    /// Comparison-only replay buffer shared by every recognizer.
    private var recorded: [AudioChunk] = []
    private var isComparing = false

    init(
        formatter: (any TextFormatter)? = nil,
        makeEngine: @escaping @Sendable () -> any TranscriptionEngine = engineForCurrentSetting
    ) {
        self.formatter = formatter
        self.makeEngine = makeEngine
    }

    // MARK: - Connection to macOS

    /// - Returns: `false` when macOS has not allowed the shortcut tap.
    @discardableResult
    func activate() -> Bool {
        hotkey.key = Settings.shared.pushToTalkKey
        hotkey.onPress = { [weak self] in self?.beginDictation() }
        hotkey.onRelease = { [weak self] in self?.endDictation() }
        return hotkey.start()
    }

    func deactivate() {
        hotkey.stop()
        cancelDictation()
    }

    /// Reconnects the shortcut monitor after its key changes.
    @discardableResult
    func reloadHotkey() -> Bool {
        hotkey.stop()
        return activate()
    }

    // MARK: - Manual capture

    /// Starts the same capture path from the native Record button.
    func startButtonRecording() {
        guard case .idle = state else { return }
        beginDictation()
    }

    func stopButtonRecording() {
        endDictation()
    }

    // MARK: - Hold lifecycle

    private func beginDictation() {
        guard case .idle = state else { return }
        state = .starting
        transcript = ""
        holdStarted = Date()
        isComparing = Settings.shared.compareMode
        recorded.removeAll(keepingCapacity: true)
        engineName = isComparing ? "Comparing…" : Settings.shared.engine.displayName

        Task { @MainActor in
            do {
                guard await Permissions.requestMicrophone() else {
                    fail("Microphone access is off. Enable it in System Settings ▸ Privacy & Security ▸ Microphone.")
                    return
                }

                let engine = makeEngine()
                self.engine = engine

                let chunks = try await engine.start()

                // Comparison must use the system recognizer's format, not an arbitrary one.
                //
                // SpeechAnalyzer requires signed 16-bit samples. The local model can adapt,
                // so the stricter system path chooses the shared format for both.
                let formatOwner: any TranscriptionEngine = isComparing ? AppleSpeechEngine() : engine
                guard let format = await formatOwner.preferredInputFormat() else {
                    throw TranscriptionError.noAudioFormat
                }

                // One draining stream preserves capture order. One task per buffer would not.
                let (audioStream, audioContinuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingNewest(64)
                )
                self.audioContinuation = audioContinuation

                // Build the replay buffer inside that same ordered drain so comparison gets
                // the exact take, in the exact order, rather than a shuffled approximation.
                let comparing = isComparing
                self.feedTask = Task.detached(priority: .userInitiated) {
                    var recording: [AudioChunk] = []
                    for await chunk in audioStream {
                        if comparing { recording.append(chunk) }
                        await engine.feed(chunk)
                    }
                    return recording
                }

                try capture.start(
                    outputFormat: format,
                    onBuffer: { chunk in
                        audioContinuation.yield(chunk)
                    },
                    onLevel: { [weak self] level in
                        Task { @MainActor in self?.updateLevel(level) }
                    }
                )

                // The user can release while permissions, models, or audio are starting.
                guard case .starting = self.state else {
                    await self.teardown()
                    return
                }

                self.state = .listening
                if Settings.shared.soundEnabled { NSSound(named: "Tink")?.play() }

                self.consumeTask = Task { @MainActor in
                    do {
                        for try await chunk in chunks {
                            self.transcript = chunk.text
                        }
                    } catch {
                        self.fail(error.localizedDescription)
                    }
                }
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func endDictation() {
        // Keep the finishing state exclusive. A second press during model work must not
        // replay or insert the same take twice.
        guard state.isActive, state != .finishing else { return }
        state = .finishing
        capture.stop()
        level = 0
        releasedAt = Date()

        Task { @MainActor in
            // Close the stream only after every captured chunk is queued, or the tail is lost.
            audioContinuation?.finish()
            audioContinuation = nil
            recorded = await feedTask?.value ?? []
            feedTask = nil

            await engine?.finish()
            await consumeTask?.value
            consumeTask = nil
            engine = nil

            if isComparing {
                await runComparison()
                return
            }

            let raw = transcript
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                state = .idle
                transcript = ""
                return
            }

            let cleaned = Settings.shared.cleanupEnabled
                ? await activeFormatter.format(raw)
                : raw

            // Lexicon replacement is the final, deterministic pass and always runs. Model
            // biasing can suggest a word; this pass guarantees the user's chosen spelling.
            let (output, corrections) = DictionaryStore.shared.corrector.apply(to: cleaned)
            if !corrections.isEmpty {
                Log.speech.info("dictionary · \(corrections.count, privacy: .public) correction(s) applied")
            }

            recordRun(text: output, corrections: corrections)
            TextInjector.insert(output)
            if Settings.shared.soundEnabled { NSSound(named: "Pop")?.play() }

            state = .idle
            transcript = ""
        }
    }

    private func cancelDictation() {
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        consumeTask?.cancel()
        consumeTask = nil

        let engine = self.engine
        self.engine = nil
        Task { await engine?.finish() }

        state = .idle
        transcript = ""
        level = 0
    }

    private func teardown() async {
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
            _ = await feedTask?.value
        feedTask = nil
        await engine?.finish()
        engine = nil
        consumeTask?.cancel()
        consumeTask = nil
        state = .idle
    }

    // MARK: - Finishing work

    private func retainForComparison(_ chunk: AudioChunk) {
        guard isComparing else { return }
        recorded.append(chunk)
    }

    /// Replays one take through both recognizers and files the results as one comparison.
    /// Comparison is read-only by design; it never writes into the focused app.
    private func runComparison() async {
        let chunks = recorded
        recorded.removeAll(keepingCapacity: false)

        guard !chunks.isEmpty, let holdStarted, let releasedAt else {
            state = .idle
            transcript = ""
            return
        }

        transcript = "Running both engines…"

        let group = UUID().uuidString
        let held = releasedAt.timeIntervalSince(holdStarted)

        // File each result as it arrives so the comparison view can fill progressively.
        let results = await EngineComparison.run(chunks: chunks) { result in
            RunLog.record(
                DictationRun(
                    date: releasedAt,
                    engine: result.engine,
                    audioSeconds: held,
                    processSeconds: result.seconds,
                    text: result.text,
                    group: group
                )
            )
        }

        for result in results {
            Log.speech.info("""
                compare · \(result.engine, privacy: .public): \
                \(result.seconds, format: .fixed(precision: 2))s — \
                \(result.text, privacy: .public)
                """)
        }

        self.holdStarted = nil
        self.releasedAt = nil
        isComparing = false
        state = .idle
        transcript = ""

        if Settings.shared.soundEnabled { NSSound(named: "Glass")?.play() }
    }

    /// Saves a finished take and records the delay after release.
    private func recordRun(text: String, corrections: [AppliedCorrection] = []) {
        guard let holdStarted, let releasedAt else { return }
        RunLog.record(
            DictationRun(
                date: releasedAt,
                engine: engineName,
                audioSeconds: releasedAt.timeIntervalSince(holdStarted),
                processSeconds: Date().timeIntervalSince(releasedAt),
                text: text,
                corrections: corrections.isEmpty ? nil : corrections
            )
        )
        self.holdStarted = nil
        self.releasedAt = nil
    }

    /// Smooth the meter so it follows speech instead of the audio callback cadence.
    private func updateLevel(_ new: Float) {
        level += (new - level) * 0.35
    }

    private func fail(_ message: String) {
        Log.app.error("\(message)")
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        engine = nil
        consumeTask?.cancel()
        consumeTask = nil
        state = .error(message)
        level = 0

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if case .error = state { state = .idle }
        }
    }
}
