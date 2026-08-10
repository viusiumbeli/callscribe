import Foundation

/// The "hold Right Shift to dictate" gesture, as a pure state machine.
///
/// Right Shift is a *typing* key, and that is the whole difficulty: hooked
/// naively, every capital letter would start a dictation. Three guards prevent
/// it, and they live here — no AppKit, no timers, no clock — so the logic that
/// decides whether your keystrokes become a recording is unit-tested instead of
/// hand-verified.
///
/// 1. A press shorter than `holdThreshold` produces nothing at all. Ordinary
///    shift-typing never crosses it.
/// 2. Any other key or modifier going down while Right Shift is held cancels the
///    gesture outright — you were shifting, not dictating.
/// 3. A chord (⌘/⌥/⌃ already held on the way down) never arms.
///
/// Time is passed in rather than read, so tests don't sleep. `tick` is the
/// caller's way of saying time has passed: it both promotes a long-enough hold
/// into a recording and enforces `maxDuration`.
public struct DictationGesture: Sendable {
    public enum Input: Sendable, Equatable {
        case rightShiftDown(at: TimeInterval, otherModifiers: Bool)
        case rightShiftUp(at: TimeInterval)
        /// Any *other* key or modifier going down — the "you're typing" signal.
        case otherKeyDown(at: TimeInterval)
        case tick(at: TimeInterval)
    }

    public enum Action: Sendable, Equatable {
        case none
        case beginRecording
        /// Stop, and transcribe what was captured.
        case finishRecording
        /// Stop, and throw the audio away.
        case abortRecording
    }

    private enum State: Equatable {
        case idle
        /// Held, but not yet long enough to count as a dictation.
        case armed(since: TimeInterval)
        case recording(since: TimeInterval)
        /// Held, but this press can no longer produce a recording. Only key-up
        /// leaves: without it an aborted gesture could re-arm under the same
        /// press and record the rest of the user's typing.
        case spent
    }

    /// How long Right Shift must be held before a recording starts.
    public var holdThreshold: TimeInterval
    /// Safety cap. A recording whose key-up never arrives — a Space switch, a
    /// dropped event, secure input taking over — still ends by itself.
    public var maxDuration: TimeInterval

    private var state: State = .idle

    public init(holdThreshold: TimeInterval = 0.35, maxDuration: TimeInterval = 120) {
        self.holdThreshold = holdThreshold
        self.maxDuration = maxDuration
    }

    public var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    /// Held and still able to become (or stay) a recording — the caller's cue to
    /// keep ticking. False means no tick can change anything, so stop the timer.
    public var isPending: Bool {
        switch state {
        case .armed, .recording: true
        case .idle, .spent: false
        }
    }

    public mutating func handle(_ input: Input) -> Action {
        switch input {
        case .rightShiftDown(let at, let otherModifiers):
            // Key repeat, or a stray duplicate: already held changes nothing.
            guard case .idle = state else { return .none }
            state = otherModifiers ? .spent : .armed(since: at)
            return .none

        case .rightShiftUp:
            let finishing = isRecording
            state = .idle
            // `.armed` lands here too: the hold never crossed the threshold, so
            // nothing was started and there is nothing to stop.
            return finishing ? .finishRecording : .none

        case .otherKeyDown:
            switch state {
            case .armed:
                state = .spent
                return .none
            case .recording:
                state = .spent
                return .abortRecording
            case .idle, .spent:
                return .none
            }

        case .tick(let now):
            switch state {
            case .armed(let since):
                guard now - since >= holdThreshold else { return .none }
                // Timed from now, not from key-down: `maxDuration` should bound
                // how long we *record*, not how long the key has been down.
                state = .recording(since: now)
                return .beginRecording
            case .recording(let since):
                guard now - since >= maxDuration else { return .none }
                state = .spent
                return .finishRecording
            case .idle, .spent:
                return .none
            }
        }
    }
}
