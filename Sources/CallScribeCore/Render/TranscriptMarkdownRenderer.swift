import Foundation

/// Renders a merged transcript to Markdown. A separate pure stage so that
/// "apply inferred speaker names" can re-render without re-merging.
public enum TranscriptMarkdownRenderer {
    /// `names` maps display labels to real names ("Speaker 1" → "Misha").
    public static func render(_ transcript: Transcript, names: [String: String] = [:]) -> String {
        let lines = transcript.utterances.map { utterance in
            let label = names[utterance.speaker.label] ?? utterance.speaker.label
            return "**[\(timecode(utterance.start))] \(label):** \(utterance.text)"
        }
        return lines.joined(separator: "\n\n") + (lines.isEmpty ? "" : "\n")
    }

    static func timecode(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
