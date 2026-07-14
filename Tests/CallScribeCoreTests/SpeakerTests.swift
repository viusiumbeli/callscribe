import Testing
@testable import CallScribeCore

@Test func speakerLabels() {
    #expect(Speaker.me.label == "Me")
    #expect(Speaker.remote(2).label == "Speaker 2")
    #expect(Speaker.participant.label == "Participant")
}
