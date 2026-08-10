import Foundation
import Testing
@testable import CallScribeCore

/// Feed inputs in order and collect what each one produced.
private func run(
    _ gesture: inout DictationGesture,
    _ inputs: [DictationGesture.Input]
) -> [DictationGesture.Action] {
    inputs.map { gesture.handle($0) }
}

@Test func aShortPressDoesNothing() {
    var gesture = DictationGesture()
    let actions = run(&gesture, [
        .rightShiftDown(at: 0, otherModifiers: false),
        .tick(at: 0.1),
        .rightShiftUp(at: 0.12),
    ])
    #expect(actions == [.none, .none, .none])
    #expect(!gesture.isRecording)
    #expect(!gesture.isPending)
}

@Test func holdingPastTheThresholdRecordsAndReleasingFinishes() {
    var gesture = DictationGesture()
    #expect(gesture.handle(.rightShiftDown(at: 0, otherModifiers: false)) == .none)
    #expect(gesture.isPending)

    // Still short of the threshold.
    #expect(gesture.handle(.tick(at: 0.2)) == .none)
    #expect(!gesture.isRecording)

    #expect(gesture.handle(.tick(at: 0.4)) == .beginRecording)
    #expect(gesture.isRecording)

    // Further ticks while recording are inert until the cap.
    #expect(gesture.handle(.tick(at: 3)) == .none)
    #expect(gesture.handle(.rightShiftUp(at: 4)) == .finishRecording)
    #expect(!gesture.isRecording)
    #expect(!gesture.isPending)
}

/// The case that makes Right Shift usable at all: shift-typing a capital must
/// not produce a dictation, however slowly it's typed.
@Test func typingACapitalNeverRecords() {
    var gesture = DictationGesture()
    let actions = run(&gesture, [
        .rightShiftDown(at: 0, otherModifiers: false),
        .otherKeyDown(at: 0.05),
        .tick(at: 0.5),        // past the threshold, but the gesture is spent
        .tick(at: 1.5),
        .rightShiftUp(at: 2),
    ])
    #expect(actions == [.none, .none, .none, .none, .none])
    #expect(!gesture.isRecording)
}

/// Holding shift for a run of capitals ("HELLO") crosses the threshold before
/// the first letter lands, so the recording must be abandoned, not transcribed.
@Test func aKeyPressedDuringARecordingAbortsIt() {
    var gesture = DictationGesture()
    #expect(gesture.handle(.rightShiftDown(at: 0, otherModifiers: false)) == .none)
    #expect(gesture.handle(.tick(at: 0.4)) == .beginRecording)
    #expect(gesture.handle(.otherKeyDown(at: 0.6)) == .abortRecording)
    #expect(!gesture.isRecording)
    // The eventual key-up must not also report a finish.
    #expect(gesture.handle(.rightShiftUp(at: 1)) == .none)
}

@Test func aChordNeverArms() {
    var gesture = DictationGesture()
    let actions = run(&gesture, [
        .rightShiftDown(at: 0, otherModifiers: true),
        .tick(at: 1),
        .rightShiftUp(at: 1.5),
    ])
    #expect(actions == [.none, .none, .none])
    #expect(!gesture.isPending)
}

@Test func theMaxDurationCapFinishesOnItsOwn() {
    var gesture = DictationGesture(holdThreshold: 0.35, maxDuration: 10)
    #expect(gesture.handle(.rightShiftDown(at: 0, otherModifiers: false)) == .none)
    #expect(gesture.handle(.tick(at: 0.4)) == .beginRecording)
    #expect(gesture.handle(.tick(at: 10.3)) == .none)      // 9.9 s in
    #expect(gesture.handle(.tick(at: 10.5)) == .finishRecording)
    #expect(!gesture.isRecording)
    // No second finish from the ticks that follow, nor from the late key-up.
    #expect(gesture.handle(.tick(at: 11)) == .none)
    #expect(gesture.handle(.rightShiftUp(at: 12)) == .none)
}

/// A spent press must not re-arm; only a fresh key-down starts over.
@Test func aFreshPressArmsAgainAfterASpentOne() {
    var gesture = DictationGesture()
    _ = gesture.handle(.rightShiftDown(at: 0, otherModifiers: false))
    _ = gesture.handle(.otherKeyDown(at: 0.05))
    // Still held, still spent — a down event here is a duplicate, not a restart.
    #expect(gesture.handle(.rightShiftDown(at: 0.1, otherModifiers: false)) == .none)
    #expect(gesture.handle(.tick(at: 0.6)) == .none)

    #expect(gesture.handle(.rightShiftUp(at: 0.7)) == .none)
    #expect(gesture.handle(.rightShiftDown(at: 1, otherModifiers: false)) == .none)
    #expect(gesture.handle(.tick(at: 1.4)) == .beginRecording)
}

@Test func strayEventsWhileIdleAreIgnored() {
    var gesture = DictationGesture()
    let actions = run(&gesture, [
        .tick(at: 1),
        .otherKeyDown(at: 2),
        .rightShiftUp(at: 3),     // key-up with no matching key-down
    ])
    #expect(actions == [.none, .none, .none])
    #expect(!gesture.isPending)
}
