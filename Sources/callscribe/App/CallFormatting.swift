import Foundation

/// Display formatting for calls in the history list and detail view.
enum CallFormatting {
    /// Prefer the LLM-generated name; fall back to the start date, then folder.
    static func title(_ call: AppState.CallSummary) -> String {
        if let t = call.title, !t.isEmpty { return t }
        guard let started = call.startedAt else { return call.name }
        return started.formatted(date: .abbreviated, time: .shortened)
    }

    /// Time-of-day of the call ("10:37").
    static func time(_ call: AppState.CallSummary) -> String {
        call.startedAt?.formatted(date: .omitted, time: .shortened) ?? call.name
    }

    /// Secondary line: time (when a title is the primary) and/or duration.
    static func subtitle(_ call: AppState.CallSummary) -> String {
        var parts: [String] = []
        if call.title != nil { parts.append(time(call)) }
        if let dur = call.durationSec, dur > 0 { parts.append(duration(dur)) }
        return parts.joined(separator: " · ")
    }

    /// Clean H:MM:SS / M:SS duration (rounded to whole seconds).
    static func duration(_ seconds: Double) -> String {
        let t = Int(seconds.rounded())
        if t >= 3600 {
            return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
        }
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    /// Friendly label for a pipeline stage shown while a call is processing.
    static func stageLabel(_ stage: String) -> String {
        switch stage {
        case "queued": "Queued…"
        case "echoCancel": "Cleaning audio…"
        case "transcribe": "Transcribing…"
        case "diarize": "Detecting speakers…"
        case "merge": "Merging…"
        case "summarize": "Summarizing…"
        default: "Processing…"
        }
    }

    /// Day-section heading: Today / Yesterday / an abbreviated date.
    static func dayTitle(_ day: Date) -> String {
        if day == .distantPast { return "Earlier" }
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}
