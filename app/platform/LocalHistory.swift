import MumbleDictionary
import Foundation
import Observation

/// One finished Mumble take, kept locally for later review.
struct DictationRun: Codable, Sendable, Identifiable {
    /// Stable identity, so deletion never has to guess from transcript text.
    ///
    /// Older local records may not have an id. Give those records one when read instead of
    /// rejecting an otherwise useful line, then persist it during the next rewrite.
    var id: UUID = UUID()

    let date: Date
    let engine: String
    /// How long the user kept the shortcut down.
    let audioSeconds: Double
    /// Release to finished text: the delay the user actually experiences.
    let processSeconds: Double
    let text: String
    /// Shared by every recognizer that saw this take, allowing one comparison card instead
    /// of several unrelated history rows.
    var group: String?

    /// Lexicon rules that changed this transcript, so history can show the finishing work.
    ///
    /// Optional for older records created before lexicon changes were tracked.
    var corrections: [AppliedCorrection]?

    var realtimeFactor: Double { audioSeconds / max(processSeconds, 0.0001) }
    var characters: Int { text.count }

    init(
        id: UUID = UUID(),
        date: Date,
        engine: String,
        audioSeconds: Double,
        processSeconds: Double,
        text: String,
        group: String? = nil,
        corrections: [AppliedCorrection]? = nil
    ) {
        self.id = id
        self.date = date
        self.engine = engine
        self.audioSeconds = audioSeconds
        self.processSeconds = processSeconds
        self.text = text
        self.group = group
        self.corrections = corrections
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        engine = try container.decode(String.self, forKey: .engine)
        audioSeconds = try container.decode(Double.self, forKey: .audioSeconds)
        processSeconds = try container.decode(Double.self, forKey: .processSeconds)
        text = try container.decode(String.self, forKey: .text)
        group = try container.decodeIfPresent(String.self, forKey: .group)
        corrections = try container.decodeIfPresent([AppliedCorrection].self, forKey: .corrections)
    }
}

/// Main-actor view model for the history screen.
@MainActor
@Observable
final class RunStore {
    static let shared = RunStore()

    private(set) var runs: [DictationRun] = []

    private init() { reload() }

    func reload() {
        runs = RunLog.load()
    }

    var comparisons: [[DictationRun]] {
        Dictionary(grouping: runs.filter { $0.group != nil }, by: { $0.group! })
            .values
            .sorted { ($0.first?.date ?? .distantPast) > ($1.first?.date ?? .distantPast) }
    }

    var singles: [DictationRun] {
        runs.filter { $0.group == nil }.reversed()
    }
}

/// Persists finished takes as JSONL in application support. The native views read it
/// directly; there is no web dashboard in the loop.
@MainActor
enum RunLog {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mumble", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var runsURL: URL { directory.appendingPathComponent("runs.jsonl") }

    static func record(_ run: DictationRun) {
        append(run)
        RunStore.shared.reload()
    }

    static func record(_ runs: [DictationRun]) {
        runs.forEach(append)
        RunStore.shared.reload()
    }

    private static func append(_ run: DictationRun) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(run) else { return }
        line.append(0x0A) // newline

        if let handle = try? FileHandle(forWritingTo: runsURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: runsURL)
        }
    }

    static func load() -> [DictationRun] {
        guard let data = try? Data(contentsOf: runsURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(DictationRun.self, from: Data(line))
        }
    }

    /// Deletes one take.
    static func delete(_ run: DictationRun) {
        delete(ids: [run.id])
    }

    /// Deletes every result from one comparison take.
    static func deleteGroup(_ group: String) {
        rewrite(load().filter { $0.group != group })
    }

    static func delete(ids: Set<UUID>) {
        rewrite(load().filter { !ids.contains($0.id) })
    }

    static func clear() {
        try? FileManager.default.removeItem(at: runsURL)
        RunStore.shared.reload()
    }

    /// Rewrites the ledger after a deletion and persists ids assigned to older records.
    private static func rewrite(_ runs: [DictationRun]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let body = runs.compactMap { run -> String? in
            guard let data = try? encoder.encode(run) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")

        // Atomic replacement keeps a failed write from erasing unrelated history.
        try? (body.isEmpty ? "" : body + "\n")
            .write(to: runsURL, atomically: true, encoding: .utf8)

        RunStore.shared.reload()
    }
}
