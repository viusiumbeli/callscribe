import Foundation

/// Parses a rendered transcript back into structured turns — the inverse of
/// `TranscriptMarkdownRenderer`. The UI uses this to lay out per-speaker bubbles
/// with clickable timecodes; keeping it pure (Foundation only) makes it testable.
public enum TranscriptParse {
    public struct Turn: Equatable, Sendable {
        public let start: TimeInterval   // seconds, from [HH:MM:SS]
        public let label: String         // as shown (may be a renamed name)
        public let text: String

        public init(start: TimeInterval, label: String, text: String) {
            self.start = start
            self.label = label
            self.text = text
        }
    }

    /// Each utterance is `**[HH:MM:SS] Label:** text`, separated by blank lines.
    public static func parse(_ markdown: String) -> [Turn] {
        let header = /^\*\*\[(\d{1,2}):(\d{2}):(\d{2})\]\s+(.+?):\*\*\s*(.*)$/
            .dotMatchesNewlines()
        var turns: [Turn] = []
        for block in markdown.components(separatedBy: "\n\n") {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let m = trimmed.firstMatch(of: header) else { continue }
            let h = Int(m.1) ?? 0, min = Int(m.2) ?? 0, sec = Int(m.3) ?? 0
            turns.append(Turn(
                start: TimeInterval(h * 3600 + min * 60 + sec),
                label: String(m.4),
                text: String(m.5).trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        return turns
    }
}
