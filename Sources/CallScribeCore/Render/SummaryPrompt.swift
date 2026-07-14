import Foundation

/// Prompt template for the summarizer and a tolerant parser for its response.
public enum SummaryPrompt {
    public static func build(transcript: String) -> String {
        """
        You are given a transcript of a call. Speakers are labeled "Me" and \
        "Speaker 1", "Speaker 2", etc. Produce a concise Markdown summary in the \
        same language as the transcript, with these sections:

        ## Summary
        A short paragraph of what the call was about.

        ## Agreements
        Bullet list of decisions and agreements reached.

        ## My tasks
        A checklist (`- [ ]`) of concrete action items assigned to "Me".

        If you can infer any speaker's real name from context (e.g. someone is \
        addressed as "Misha"), append a fenced JSON block mapping labels to \
        names. Include ONLY confidently inferred names; omit the block entirely \
        if none. Example:

        ```json
        {"speakers": {"Speaker 1": "Misha", "Speaker 2": "Anna"}}
        ```

        Transcript:
        ---
        \(transcript)
        ---
        """
    }

    /// Extract the fenced `{"speakers": {...}}` block, tolerating surrounding
    /// prose, a missing block, or malformed JSON (→ empty map). The block is
    /// stripped from the returned Markdown so it doesn't show in summary.md.
    public static func parse(_ response: String) -> SummaryResult {
        guard let range = response.range(of: #"```json\s*\{.*?\}\s*```"#,
                                          options: [.regularExpression, .caseInsensitive]) else {
            return SummaryResult(markdown: response.trimmingCharacters(in: .whitespacesAndNewlines),
                                 speakerNames: [:])
        }

        let names = parseSpeakerNames(String(response[range]))
        var markdown = response
        markdown.removeSubrange(range)
        return SummaryResult(
            markdown: markdown.trimmingCharacters(in: .whitespacesAndNewlines),
            speakerNames: names
        )
    }

    private static func parseSpeakerNames(_ fenced: String) -> [String: String] {
        let json = fenced
            .replacingOccurrences(of: "```json", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let speakers = root["speakers"] as? [String: Any] else {
            return [:]
        }
        return speakers.compactMapValues { $0 as? String }
    }
}
