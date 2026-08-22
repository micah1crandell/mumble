import Foundation

/// One piece of language Mumble should recognize or rewrite.
///
/// Two kinds cover two different jobs:
///
/// - `.term` — a spelling the recognizer should know: "Mumble", "Morning Pages".
///   It guides recognition but does not rewrite text.
/// - `.correction` — a rule: when the recognizer emits X, write Y.
///   It guides recognition toward Y and fixes X after the take.
public struct DictionaryEntry: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case term
        case correction
    }

    public var id: UUID
    public var kind: Kind

    /// The preferred spelling. For a correction this is the text that gets written and the
    /// spelling the recognizer is nudged toward.
    public var write: String

    /// For corrections, the text Mumble expects to hear. Empty for terms.
    public var hear: String

    /// Disabled entries remain available for later, but have no effect on recognition or
    /// rewriting.
    public var isEnabled: Bool

    public init(id: UUID = UUID(), kind: Kind, write: String, hear: String = "", isEnabled: Bool = true) {
        self.id = id
        self.kind = kind
        self.write = write
        self.hear = hear
        self.isEnabled = isEnabled
    }

    public static func term(_ word: String) -> DictionaryEntry {
        DictionaryEntry(kind: .term, write: word)
    }

    public static func correction(hear: String, write: String) -> DictionaryEntry {
        DictionaryEntry(kind: .correction, write: write, hear: hear)
    }

    /// The line representation used by the editable lexicon file.
    public var fileLine: String {
        let body = kind == .correction ? "\(hear) -> \(write)" : write
        return isEnabled ? body : "# off: \(body)"
    }
}

/// A reason a rewrite rule may be broader than its author intended.
///
/// Shown while editing an entry. It never blocks because a broad rule can still be intentional;
/// the lexicon belongs to the user.
public struct DictionaryWarning: Identifiable, Sendable {
    public var id: String { message }
    public let message: String

    /// Common words that are risky as whole triggers. This catches obvious foot-guns without
    /// pretending to judge every language or context.
    private static let common: Set<String> = [
        "a", "about", "all", "also", "and", "any", "are", "as", "at", "back", "be", "because",
        "but", "by", "call", "can", "case", "check", "class", "close", "cloud", "code", "come",
        "could", "data", "day", "did", "do", "does", "down", "each", "even", "file", "find",
        "first", "for", "from", "get", "give", "go", "good", "great", "group", "had", "has",
        "have", "he", "her", "here", "him", "his", "how", "if", "in", "into", "is", "it",
        "its", "just", "key", "know", "like", "line", "list", "look", "make", "man", "many",
        "may", "me", "more", "most", "my", "need", "new", "no", "not", "now", "number", "of",
        "off", "on", "one", "only", "open", "or", "other", "our", "out", "over", "page",
        "part", "people", "point", "put", "read", "right", "run", "said", "same", "say",
        "see", "set", "she", "should", "show", "side", "so", "some", "state", "still", "such",
        "take", "team", "test", "than", "that", "the", "their", "them", "then", "there",
        "these", "they", "thing", "think", "this", "time", "to", "two", "type", "up", "us",
        "use", "user", "very", "want", "was", "way", "we", "well", "were", "what", "when",
        "where", "which", "who", "will", "with", "word", "work", "would", "year", "you",
        "your",
    ]

    /// - Returns: warnings for `entry`, or an empty list when it looks safe.
    public static func check(_ entry: DictionaryEntry) -> [DictionaryWarning] {
        // Only the correction side can rewrite text. A `.term` is recognition context only.
        guard entry.kind == .correction else { return [] }

        let trigger = entry.hear.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trigger.isEmpty else { return [] }

        var warnings: [DictionaryWarning] = []
        let words = trigger.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" })

        if words.count == 1, let only = words.first {
            if common.contains(String(only)) {
                warnings.append(DictionaryWarning(
                    message: "“\(trigger)” is an ordinary word. This will rewrite every use of it, "
                        + "not just the ones you mean. Consider a longer phrase."
                ))
            } else if only.count <= 3 {
                warnings.append(DictionaryWarning(
                    message: "“\(trigger)” is very short and will match often. Consider a longer phrase."
                ))
            }
        }

        if entry.write.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(trigger) == .orderedSame {
            warnings.append(DictionaryWarning(
                message: "This rewrites “\(trigger)” to itself, so it will never change anything."
            ))
        }

        return warnings
    }
}
