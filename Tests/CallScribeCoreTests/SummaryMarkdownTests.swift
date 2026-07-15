import Testing
@testable import CallScribeCore

@Suite struct SummaryMarkdownTests {
    let sample = """
    ## Summary
    A quick sync about the launch.

    ## Agreements
    - Ship on Friday.
    - Anna writes the notes.

    ## My tasks
    - [ ] Send the recap
    - [x] Book the room
    """

    @Test func parsesSectionsInOrder() {
        let sections = SummaryMarkdown.parse(sample)
        #expect(sections.map(\.title) == ["Summary", "Agreements", "My tasks"])
    }

    @Test func summaryIsAParagraph() {
        let sections = SummaryMarkdown.parse(sample)
        #expect(sections[0].blocks == [.paragraph("A quick sync about the launch.")])
    }

    @Test func agreementsAreBullets() {
        let sections = SummaryMarkdown.parse(sample)
        #expect(sections[1].blocks == [.bullets(["Ship on Friday.", "Anna writes the notes."])])
    }

    @Test func tasksCarryDoneStateAndIndex() {
        let sections = SummaryMarkdown.parse(sample)
        guard case .tasks(let tasks) = sections[2].blocks.first else {
            Issue.record("expected tasks block"); return
        }
        #expect(tasks == [
            .init(text: "Send the recap", done: false, index: 0),
            .init(text: "Book the room", done: true, index: 1),
        ])
    }

    @Test func taskIndicesAreGlobalAcrossSections() {
        let md = """
        ## A
        - [ ] one
        ## B
        - [ ] two
        """
        let sections = SummaryMarkdown.parse(md)
        guard case .tasks(let a) = sections[0].blocks.first,
              case .tasks(let b) = sections[1].blocks.first else {
            Issue.record("expected task blocks"); return
        }
        #expect(a[0].index == 0)
        #expect(b[0].index == 1)
    }

    @Test func toggleFlipsTheAddressedTask() {
        let after = SummaryMarkdown.toggleTask(sample, index: 0)
        #expect(after.contains("- [x] Send the recap"))
        #expect(after.contains("- [x] Book the room"))   // unchanged
    }

    @Test func toggleUnchecksAlready() {
        let after = SummaryMarkdown.toggleTask(sample, index: 1)
        #expect(after.contains("- [ ] Book the room"))
    }

    @Test func toggleRoundTrips() {
        let once = SummaryMarkdown.toggleTask(sample, index: 0)
        let twice = SummaryMarkdown.toggleTask(once, index: 0)
        #expect(twice.contains("- [ ] Send the recap"))
    }

    @Test func italicPlaceholderIsParsedAsParagraph() {
        let md = "## My tasks\n_No action items._"
        let sections = SummaryMarkdown.parse(md)
        #expect(sections[0].blocks == [.paragraph("_No action items._")])
    }

    @Test func contentBeforeFirstHeadingBecomesUntitledSection() {
        let sections = SummaryMarkdown.parse("Loose intro.\n\n## Summary\nBody.")
        #expect(sections[0].title == "")
        #expect(sections[0].blocks == [.paragraph("Loose intro.")])
        #expect(sections[1].title == "Summary")
    }
}
