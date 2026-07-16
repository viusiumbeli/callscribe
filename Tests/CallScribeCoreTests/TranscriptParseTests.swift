import Foundation
import Testing
@testable import CallScribeCore

@Suite struct TranscriptParseTests {
    @Test func parsesTurnsWithTimecodesLabelsAndText() {
        let md = """
        **[00:00:00] Me:** Привет, как дела?

        **[01:02:03] Anna:** Хорошо, спасибо за звонок.
        """
        let turns = TranscriptParse.parse(md)
        #expect(turns.count == 2)

        #expect(turns[0].start == 0)
        #expect(turns[0].label == "Me")
        #expect(turns[0].text == "Привет, как дела?")

        #expect(turns[1].start == 3723)   // 1h 2m 3s
        #expect(turns[1].label == "Anna")
        #expect(turns[1].text == "Хорошо, спасибо за звонок.")
    }

    @Test func preservesRenamedLabels() {
        let turns = TranscriptParse.parse("**[00:00:05] Speaker 1:** Hi there")
        #expect(turns.count == 1)
        #expect(turns[0].label == "Speaker 1")
        #expect(turns[0].start == 5)
    }

    @Test func emptyTranscriptYieldsNoTurns() {
        #expect(TranscriptParse.parse("").isEmpty)
        #expect(TranscriptParse.parse("\n\n   \n").isEmpty)
    }

    @Test func skipsNonMatchingBlocks() {
        let md = """
        Some stray note without a header.

        **[00:00:10] Me:** Real line.
        """
        let turns = TranscriptParse.parse(md)
        #expect(turns.count == 1)
        #expect(turns[0].text == "Real line.")
    }
}
