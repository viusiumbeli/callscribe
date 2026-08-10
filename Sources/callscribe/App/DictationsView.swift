import AppKit
import CallScribeCore
import SwiftUI

/// Everything you've dictated, grouped by day and newest first, with a search
/// field and per-entry copy and delete.
///
/// Its own window rather than a pane in the main one: dictations are global,
/// while the main window is scoped to the selected project, and folding a global
/// list in there would misrepresent what the project buttons control.
struct DictationsView: View {
    @Bindable var history: DictationHistory

    @State private var pendingDelete: DictationLogFormat.Entry?
    /// The entry whose copy button is currently showing a checkmark.
    @State private var justCopied: Int?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 460, minHeight: 400)
        .navigationTitle("Dictations")
        // Covers a write this process didn't make — the CLI's `dictate`, or the
        // file hand-edited. In-app appends push a reload from DictationController.
        .onAppear { history.reload() }
        .confirmationDialog(
            "Delete this dictation?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("Delete dictation", role: .destructive) {
                history.delete(entry)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { entry in
            Text("“\(snippet(entry.text))” will be removed from dictations.md. This can't be undone.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search dictations", text: $history.search)
                    .textFieldStyle(.plain)
                if !history.search.isEmpty {
                    Button {
                        history.search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Clear the search")
                    .pointerCursor()
                }
            }
            .softField()

            if let error = history.error {
                ErrorBanner(message: error) { history.clearError() }
            }
        }
        .padding(Spacing.lg)
    }

    // MARK: - List

    @ViewBuilder private var content: some View {
        let entries = history.filtered
        if entries.isEmpty {
            if history.entries.isEmpty {
                ContentUnavailableView(
                    "No dictations yet",
                    systemImage: "mic",
                    description: Text("Hold Right Shift anywhere, speak, and let go.")
                )
            } else {
                ContentUnavailableView.search(text: history.search)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(daySections(of: entries)) { section in
                        Text(section.title)
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.top, Spacing.md)
                            .padding(.bottom, Spacing.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(section.entries) { entry in
                            row(entry)
                        }
                    }
                }
                .padding(Spacing.sm)
            }
        }
    }

    private func row(_ entry: DictationLogFormat.Entry) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(DictationHistory.time(entry))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    // Only on entries dictated since the language was threaded
                    // through; older ones simply don't carry one.
                    if let language = entry.language {
                        Text(language.uppercased())
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(entry.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: Spacing.xs) {
                Button {
                    copy(entry)
                } label: {
                    Image(systemName: justCopied == entry.index ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(justCopied == entry.index ? Color.brand : .secondary)
                }
                .buttonStyle(.borderless)
                .help("Copy this dictation")
                .pointerCursor()

                Button {
                    pendingDelete = entry
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete this dictation")
                .pointerCursor()
            }
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .background(
            Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contextMenu {
            Button("Copy") { copy(entry) }
            Button("Delete", role: .destructive) { pendingDelete = entry }
        }
    }

    // MARK: - Actions

    /// Copy, and confirm it visibly. Every other copy button in the app is
    /// silent, which is fine for one button on a detail page and not fine in a
    /// list where every row has one and they all look alike.
    private func copy(_ entry: DictationLogFormat.Entry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        justCopied = entry.index
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if justCopied == entry.index { justCopied = nil }
        }
    }

    private func snippet(_ text: String, limit: Int = 60) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count <= limit ? flat : String(flat.prefix(limit)) + "…"
    }

    // MARK: - Grouping

    /// Day sections in the order the entries arrive (newest first), the same
    /// accumulation `CallsColumn.daySections` uses.
    private func daySections(of entries: [DictationLogFormat.Entry]) -> [DaySection] {
        var order: [Date] = []
        var byDay: [Date: [DictationLogFormat.Entry]] = [:]
        for entry in entries {
            let day = DictationHistory.day(entry)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(entry)
        }
        return order.map { day in
            DaySection(
                id: day.timeIntervalSince1970,
                title: CallFormatting.dayTitle(day),
                entries: byDay[day] ?? []
            )
        }
    }

    struct DaySection: Identifiable {
        let id: TimeInterval
        let title: String
        let entries: [DictationLogFormat.Entry]
    }
}
