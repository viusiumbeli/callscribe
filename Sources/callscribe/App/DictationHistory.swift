import CallScribeCore
import CallScribeEngine
import Foundation
import Observation

/// Past dictations, read from `dictations.md`, for the Dictations window.
///
/// Reload is explicit — there is no file watching anywhere in this app, by
/// convention (`AppState.refreshHistory()` is likewise called by whoever just
/// changed something). `DictationController` calls `reload()` after each append,
/// which is the case that matters: the window can be open *behind* the app you're
/// dictating into, so no activation or appearance hook would ever fire.
@MainActor
@Observable
final class DictationHistory {
    /// Newest first — the end of the log is the part you want.
    private(set) var entries: [DictationLogFormat.Entry] = []
    var search: String = ""
    /// Set when a delete fails, shown as a banner. Reads never fail loudly: an
    /// unreadable log is indistinguishable from an empty one.
    private(set) var error: String?

    private let log: DictationLog

    init(log: DictationLog = DictationLog()) {
        self.log = log
    }

    func reload() {
        entries = log.entries().reversed()
    }

    /// Entries matching the current search, newest first.
    ///
    /// `localizedStandardContains` rather than a lowercased `contains`: it is
    /// case- *and* diacritic-insensitive and locale-aware, which is what makes it
    /// work on the Russian entries as well as the English ones.
    var filtered: [DictationLogFormat.Entry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.text.localizedStandardContains(query)
                || Self.time($0).localizedStandardContains(query)
                || ($0.language?.localizedStandardContains(query) ?? false)
        }
    }

    /// Delete one entry and re-read. Addressed by `Entry.index`, the entry's
    /// ordinal in the file — display order is reversed and filtered, so a row's
    /// position on screen is unrelated to its position on disk.
    func delete(_ entry: DictationLogFormat.Entry) {
        do {
            try log.remove(index: entry.index)
            error = nil
        } catch {
            self.error = error.localizedDescription
            Log.shared.error("dictation: could not delete an entry: \(Log.truncated(error.localizedDescription))")
        }
        // Reload either way: on success the indices below this one have shifted,
        // and on failure the on-disk truth is what should be on screen.
        reload()
    }

    func clearError() { error = nil }

    // MARK: - Formatting

    /// Time of day ("13:05"), matching how the calls list labels a row.
    static func time(_ entry: DictationLogFormat.Entry) -> String {
        entry.date?.formatted(date: .omitted, time: .shortened) ?? "—"
    }

    /// The day an entry belongs to, for section grouping. Undated entries (a
    /// hand-edited stamp) fall into `.distantPast`, which `CallFormatting.dayTitle`
    /// renders as "Earlier" — the same fallback the calls list uses.
    static func day(_ entry: DictationLogFormat.Entry) -> Date {
        entry.date.map { Calendar.current.startOfDay(for: $0) } ?? .distantPast
    }
}
