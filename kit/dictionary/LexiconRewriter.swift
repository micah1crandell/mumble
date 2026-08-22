import Foundation

/// One rewrite that fired, kept so history can show what the lexicon changed.
public struct AppliedCorrection: Codable, Hashable, Sendable {
    /// The text as the engine produced it.
    public let from: String
    /// What it was rewritten to.
    public let to: String
    /// How many times it fired in this transcript.
    public let count: Int
}

/// Applies the lexicon's correction pairs to finished recognition text.
///
/// Recognition biasing is only a suggestion. Anything that must be exact belongs in this
/// deterministic post-processing pass.
///
/// Three rules keep rewriting predictable:
///
/// **Longest match first.** A phrase wins before a shorter rule can consume part of it.
///
/// **Whole matches only.** Letter and digit fences keep a phrase from biting into a larger word.
///
/// **Glued words still match.** Phrase gaps accept spaces, hyphens, or no separator because
/// recognizers are inconsistent about how they join words.
public struct DictionaryCorrector: Sendable {
    private let rules: [Rule]

    private struct Rule: Sendable {
        let regex: NSRegularExpression
        let replacement: String
        let trigger: String
    }

    public init(entries: [DictionaryEntry]) {
        // Longest trigger first. Once a phrase claims its span, a shorter overlapping rule
        // never gets a chance to undo it.
        let corrections = entries
            .filter { $0.isEnabled && $0.kind == .correction }
            .filter { !$0.hear.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.hear.count > $1.hear.count }

        rules = corrections.compactMap { entry in
            guard let regex = Self.makeRegex(for: entry.hear) else { return nil }
            return Rule(
                regex: regex,
                replacement: NSRegularExpression.escapedTemplate(for: entry.write),
                trigger: entry.hear
            )
        }
    }

    public var isEmpty: Bool { rules.isEmpty }

    /// Applies every enabled rewrite rule in precedence order.
    ///
    /// - Returns: rewritten text plus one record for each rule that fired.
    public func apply(to text: String) -> (text: String, applied: [AppliedCorrection]) {
        guard !rules.isEmpty, !text.isEmpty else { return (text, []) }

        // Normalize both sides first. macOS can provide decomposed accents, and composed and
        // decomposed spellings must compare as the same user-visible text.
        var result = text.precomposedStringWithCanonicalMapping
        var applied: [AppliedCorrection] = []

        for rule in rules {
            let range = NSRange(result.startIndex..., in: result)
            let matches = rule.regex.numberOfMatches(in: result, range: range)
            guard matches > 0 else { continue }

            // Keep the recognizer's actual text in the record; case and spacing may differ
            // from the normalized rule that matched it.
            let firstMatch = rule.regex.firstMatch(in: result, range: range)
            let heard = firstMatch
                .flatMap { Range($0.range, in: result) }
                .map { String(result[$0]) } ?? rule.trigger

            result = rule.regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: rule.replacement
            )

            applied.append(AppliedCorrection(
                from: heard,
                to: rule.replacement.replacingOccurrences(of: "\\", with: ""),
                count: matches
            ))
        }

        return (result, applied)
    }

    /// Builds one tolerant, fenced pattern from a trigger phrase.
    ///
    /// Phrase parts accept zero or more spaces or hyphens, covering joined, dashed, and spaced
    /// recognition output.
    ///
    /// Letter and digit lookarounds are stricter than `\b`, preventing a rule from matching
    /// inside a longer word or before an apostrophe.
    private static func makeRegex(for trigger: String) -> NSRegularExpression? {
        // Match the normalization used by `apply(to:)`, regardless of how text entered Mumble.
        let parts = trigger
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "\t" })
            .map { NSRegularExpression.escapedPattern(for: String($0)) }

        guard !parts.isEmpty else { return nil }

        let body = parts.joined(separator: "[\\s\\-]*")
        let pattern = "(?<![\\p{L}\\p{N}])\(body)(?![\\p{L}\\p{N}])"

        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}

// MARK: - Recognition hints

public extension DictionaryCorrector {
    /// Preferred spellings to offer the recognizer as context before capture.
    ///
    /// Keep the hint list short. Too much context can make a model invent vocabulary during
    /// quiet audio, which is worse than correcting a single misspelling afterward.
    public static let biasLimit = 40

    /// - Returns: term spellings and correction outputs, newest useful entries first and
    ///   capped at `biasLimit`.
    public static func biasPhrases(from entries: [DictionaryEntry]) -> [String] {
        var seen = Set<String>()
        var phrases: [String] = []

        for entry in entries where entry.isEnabled {
            let phrase = entry.write.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty, seen.insert(phrase.lowercased()).inserted else { continue }
            phrases.append(phrase)
            if phrases.count == biasLimit { break }
        }

        return phrases
    }
}
