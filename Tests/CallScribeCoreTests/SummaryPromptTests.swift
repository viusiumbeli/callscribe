import Testing
@testable import CallScribeCore

@Suite struct SummaryPromptParserTests {
    @Test func extractsSpeakerNamesAndStripsBlock() {
        let response = """
        ## Summary
        A quick sync.

        ```json
        {"speakers": {"Speaker 1": "Misha", "Speaker 2": "Anna"}}
        ```
        """
        let result = SummaryPrompt.parse(response)
        #expect(result.speakerNames == ["Speaker 1": "Misha", "Speaker 2": "Anna"])
        #expect(!result.markdown.contains("```"))
        #expect(result.markdown.contains("## Summary"))
    }

    @Test func missingBlockYieldsEmptyMap() {
        let response = "## Summary\nJust a summary, no names."
        let result = SummaryPrompt.parse(response)
        #expect(result.speakerNames.isEmpty)
        #expect(result.markdown == response)
    }

    @Test func malformedJSONYieldsEmptyMapButKeepsMarkdown() {
        let response = """
        ## Summary
        Text.

        ```json
        {"speakers": {"Speaker 1": }}
        ```
        """
        let result = SummaryPrompt.parse(response)
        #expect(result.speakerNames.isEmpty)
    }

    @Test func blockSurroundedByProseIsHandled() {
        let response = """
        Here is the summary you asked for.

        ## Summary
        Content.

        ```json
        {"speakers": {"Speaker 1": "Ivan"}}
        ```

        Let me know if you need anything else.
        """
        let result = SummaryPrompt.parse(response)
        #expect(result.speakerNames == ["Speaker 1": "Ivan"])
        #expect(result.markdown.contains("Content."))
    }

    @Test func extractsTitleAlongsideSpeakers() {
        let response = """
        ## Summary
        A quick sync.

        ```json
        {"title": "Launch planning sync", "speakers": {"Speaker 1": "Misha"}}
        ```
        """
        let result = SummaryPrompt.parse(response)
        #expect(result.title == "Launch planning sync")
        #expect(result.speakerNames == ["Speaker 1": "Misha"])
        #expect(!result.markdown.contains("```"))
    }

    @Test func handlesMultiLineJSONBlock() {
        let response = """
        ## Summary
        Body.

        ```json
        {
          "title": "Budget review",
          "speakers": {
            "Speaker 1": "Anna"
          }
        }
        ```
        """
        let result = SummaryPrompt.parse(response)
        #expect(result.title == "Budget review")
        #expect(result.speakerNames == ["Speaker 1": "Anna"])
    }

    @Test func titleAbsentWhenNoBlock() {
        let result = SummaryPrompt.parse("## Summary\nNo block here.")
        #expect(result.title == nil)
    }

    @Test func promptEmbedsTranscript() {
        let prompt = SummaryPrompt.build(transcript: "**[00:00:00] Me:** privet")
        #expect(prompt.contains("privet"))
        #expect(prompt.contains("## My tasks"))
    }
}
