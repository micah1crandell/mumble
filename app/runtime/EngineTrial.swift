import AVFoundation
import Foundation

/// One recognizer's result from a Signal Lab pass.
struct ComparisonResult: Sendable {
    let engine: String
    let text: String
    let seconds: Double
}

/// Replays one captured take through each recognizer so the comparison has one fixed input.
///
/// Normal Mumble capture may stream with Apple, but the lab feeds both engines the same
/// finished buffer. That is the only fair way to compare their numbers.
enum EngineComparison {
    /// - Parameter onResult: called after each recognizer finishes so the UI can fill in
    ///   progressively.
    static func run(
        chunks: [AudioChunk],
        onResult: @MainActor (ComparisonResult) -> Void = { _ in }
    ) async -> [ComparisonResult] {
        var results: [ComparisonResult] = []
        // Run in sequence. A simultaneous ANE/CPU race would measure contention, not the
        // recognizers themselves.
        for (name, engine) in [
            ("Apple", AppleSpeechEngine() as any TranscriptionEngine),
            ("Parakeet", ParakeetEngine() as any TranscriptionEngine),
        ] {
            let result = await measure(name: name, engine: engine, chunks: chunks)
            results.append(result)
            await onResult(result)
        }
        return results
    }

    private static func measure(
        name: String,
        engine: any TranscriptionEngine,
        chunks: [AudioChunk]
    ) async -> ComparisonResult {
        do {
            let stream = try await engine.start()

            // Exclude model preparation from the timed pass. Cold-start cost belongs to
            // setup, not to the recognizer's per-take throughput.
            let started = Date()

            // Start draining before finish; a final snapshot may arrive during that call.
            let collector = Task { () -> String in
                var latest = ""
                for try await chunk in stream { latest = chunk.text }
                return latest
            }

            for chunk in chunks {
                await engine.feed(chunk)
            }
            await engine.finish()

            // Preserve failures as failures. Empty output is a valid result and must not
            // hide an engine that actually broke.
            let text: String
            do {
                text = try await collector.value
            } catch {
                Log.speech.error("\(name, privacy: .public) stream failed: \(error.localizedDescription)")
                text = "⚠️ \(error.localizedDescription)"
            }

            return ComparisonResult(
                engine: name,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                seconds: Date().timeIntervalSince(started)
            )
        } catch {
            Log.speech.error("\(name, privacy: .public) comparison failed: \(error.localizedDescription)")
            await engine.finish()
            return ComparisonResult(engine: name, text: "⚠️ \(error.localizedDescription)", seconds: 0)
        }
    }
}
