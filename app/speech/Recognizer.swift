/// The small contract every Mumble recognizer must honor.
import AVFoundation
import Foundation

/// One owned audio buffer moving from the realtime path to a recognizer.
///
/// `AVAudioPCMBuffer` is not `Sendable`, and AVAudioEngine recycles tap buffers immediately.
/// The unchecked conformance is valid only because `MicStream` creates a fresh buffer for
/// every chunk and never touches it again after handoff.
struct AudioChunk: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

/// A replacement snapshot of the words heard so far.
///
/// `text` is the full current text, not a delta. Streaming recognizers may revise earlier
/// words, so consumers replace the previous snapshot.
struct TranscriptionChunk: Sendable {
    let text: String
    /// `true` once the recognizer has no more text to revise.
    let isFinal: Bool
}

/// A recognizer that consumes ordered audio and emits replacement text.
///
/// The system recognizer is the light default; local Parakeet is the alternate path. Keeping
/// both behind this contract lets the rest of Mumble stay unaware of model details.
protocol TranscriptionEngine: Actor {
    /// Audio format the recognizer wants. `MicStream` converts captured audio to it.
    func preferredInputFormat() async -> AVAudioFormat?

    /// Prepare the recognizer and open a session. Emits snapshots until `finish()`.
    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error>

    /// Feed one captured buffer, already in `preferredInputFormat()`.
    func feed(_ chunk: AudioChunk) async

    /// Close the session and flush its final snapshot.
    func finish() async
}

enum TranscriptionError: LocalizedError {
    case localeUnsupported(Locale)
    case modelInstallFailed(String)
    case noAudioFormat
    case notRunning

    var errorDescription: String? {
        switch self {
        case .localeUnsupported(let locale):
            return "Dictation isn't available for \(locale.identifier) on this Mac."
        case .modelInstallFailed(let detail):
            return "Couldn't install the speech model: \(detail)"
        case .noAudioFormat:
            return "No compatible audio format available for the speech engine."
        case .notRunning:
            return "The transcription engine isn't running."
        }
    }
}
