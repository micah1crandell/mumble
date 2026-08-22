import AVFoundation
import FluidAudio
import Foundation

/// The downloaded local Parakeet path, hosted by FluidAudio and CoreML.
///
/// **Batch, not streaming.** Mumble gathers the hold and resolves it on release. That keeps
/// this path simple and fast for push-to-talk, at the cost of no live words in the HUD.
actor ParakeetEngine: TranscriptionEngine {
    private var samples: [Float] = []
    private var continuation: AsyncThrowingStream<TranscriptionChunk, Error>.Continuation?

    /// Parakeet's native 16 kHz mono float32 format.
    private let converter = AudioConverter()

    func preferredInputFormat() async -> AVAudioFormat? {
        // MicStream supplies the model's native 16 kHz mono format.
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
    }

    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> {
        samples.removeAll(keepingCapacity: true)

        let (stream, continuation) = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()
        self.continuation = continuation

        // Finish the first model load before capture begins, not after release when the
        // delay would feel like a lost utterance.
        _ = try await ParakeetModels.shared.manager()

        return stream
    }

    func feed(_ chunk: AudioChunk) async {
        let buffer = chunk.buffer
        guard buffer.frameLength > 0 else { return }

        // Use FluidAudio's converter rather than a local approximation. Its sample-array
        // API assumes the expected rate and will not warn if it receives the wrong one.
        // This matters in comparison mode, where the capture format is dictated by
        // Apple's analyzer, and `bestAvailableAudioFormat` may legitimately return 8 kHz
        // as well as 16 kHz. `resampleBuffer` normalizes whatever arrives to the 16 kHz
        // mono float32 the model expects, and its Int16→Float path is bit-identical to
        // dividing by 32768, so nothing is lost versus doing it by hand.
        do {
            samples.append(contentsOf: try converter.resampleBuffer(buffer))
        } catch {
            Log.speech.error("Parakeet: audio conversion failed — \(error.localizedDescription)")
        }
    }

    func finish() async {
        defer {
            continuation?.finish()
            continuation = nil
            samples.removeAll(keepingCapacity: true)
        }

        // Parakeet's encoder needs a minimum window; a stray tap of the key isn't speech.
        // Logged rather than silent — an unexpected drop to zero here is how the
        // format bug above disguised itself as a fast, empty result.
        guard samples.count >= 1_600 else {
            Log.speech.info("Parakeet: skipped — only \(self.samples.count) samples captured")
            return
        }

        do {
            let manager = try await ParakeetModels.shared.manager()
            var decoderState = try TdtDecoderState()
            let started = Date()
            let result = try await manager.transcribe(samples, decoderState: &decoderState)
            let elapsed = Date().timeIntervalSince(started)
            let audioSeconds = Double(samples.count) / 16_000

            Log.speech.info("""
                Parakeet: \(audioSeconds, format: .fixed(precision: 1))s audio in \
                \(elapsed, format: .fixed(precision: 2))s (\(audioSeconds / max(elapsed, 0.0001), format: .fixed(precision: 0))× realtime)
                """)

            continuation?.yield(
                TranscriptionChunk(
                    text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    isFinal: true
                )
            )
        } catch {
            Log.speech.error("Parakeet failed: \(error.localizedDescription)")
            continuation?.finish(throwing: error)
            continuation = nil
        }
    }

}

/// Process-wide cache for the local recognition models.
///
/// Loading is expensive — ~470 MB prepared on first use, then a few seconds from
/// disk per process — and the models are immutable once loaded, so every dictation shares
/// one instance rather than paying that per utterance. Its own actor because `static var`
/// on `ParakeetEngine` would be unprotected global mutable state under Swift 6.
actor ParakeetModels {
    static let shared = ParakeetModels()

    /// Whether the models are already on disk, checked without loading them.
    ///
    /// `nonisolated` and filesystem-based on purpose: the menu needs this synchronously
    /// while drawing, and an in-memory "have I loaded yet" flag would wrongly report
    /// "not installed" on every fresh launch.
    nonisolated static var isInstalled: Bool {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let encoder = support
            .appendingPathComponent("FluidAudio/Models/parakeet-tdt-0.6b-v3/Encoder.mlmodelc")
        return FileManager.default.fileExists(atPath: encoder.path)
    }

    private var loaded: AsrManager?
    private var loadTask: Task<AsrManager, Error>?

    var isLoaded: Bool { loaded != nil }

    /// Loads once; concurrent callers await the same task rather than racing to prepare.
    func manager() async throws -> AsrManager {
        if let loaded { return loaded }
        if let loadTask { return try await loadTask.value }

        let task = Task<AsrManager, Error> {
            // Built as a value first: os.Logger requires a literal interpolation, so a
            // ternary can't be passed directly as the argument.
            let stage = Self.isInstalled
                ? "loading models from disk"
                : "preparing models (~470 MB, one time)"
            Log.speech.info("Parakeet: \(stage, privacy: .public)")
            let started = Date()
            let models = try await AsrModels.downloadAndLoad(version: .v3, encoderPrecision: .int8)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            Log.speech.info("Parakeet: ready in \(Date().timeIntervalSince(started), format: .fixed(precision: 1))s")
            return manager
        }
        loadTask = task

        do {
            let manager = try await task.value
            loaded = manager
            return manager
        } catch {
            // Don't cache a failed load — a transient preparation error shouldn't wedge the
            // engine for the rest of the session.
            loadTask = nil
            throw error
        }
    }
}
