import CallScribeCore
import SwiftUI

/// The transcript rendered as chat bubbles: "Me" on the right (accent tint),
/// other speakers on the left, each speaker color-coded. Every timecode is
/// clickable and seeks the audio player to that moment; the turn currently
/// playing is highlighted so the text follows the audio.
///
/// Rows are parsed and styled once (on transcript change) into `@State`, and
/// rendered with a `LazyVStack` so only on-screen bubbles are built — a big
/// transcript (hundreds of selectable-text bubbles) would otherwise take
/// seconds to materialize on first open.
struct TranscriptView: View {
    let transcript: String
    let names: [String: String]
    let player: CallAudioPlayer

    /// Colors for non-"Me" speakers, assigned in first-appearance order.
    private static let palette: [Color] = [.green, .orange, .purple, .pink, .teal, .indigo, .brown]

    /// A bubble's fully-precomputed data, so `body` does no parsing/coloring.
    private struct Row: Identifiable {
        let id: Int
        let start: TimeInterval
        let end: TimeInterval   // next turn's start; last = .greatestFiniteMagnitude
        let label: String
        let text: String
        let color: Color
        let isMe: Bool
    }

    @State private var rows: [Row] = []

    var body: some View {
        Group {
            if rows.isEmpty {
                Text("No transcript.").foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        let active = player.isPlaying
                            && player.currentTime >= row.start
                            && player.currentTime < max(row.end, row.start + 0.1)
                        bubble(row, active: active)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: transcript, initial: true) { _, _ in rebuild() }
        .onChange(of: names) { _, _ in rebuild() }
    }

    /// Parse + color the transcript once. A displayed label may be a renamed
    /// name; map it back to its canonical form ("Speaker 1", "Me") so colors
    /// stay stable, then assign colors in first-appearance order.
    private func rebuild() {
        let turns = TranscriptParse.parse(transcript)
        let reverse = Dictionary(names.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })

        var colors: [String: Color] = [:]
        var others = 0
        for turn in turns {
            let canonical = reverse[turn.label] ?? turn.label
            guard colors[canonical] == nil else { continue }
            if canonical == "Me" {
                colors[canonical] = .accentColor
            } else {
                colors[canonical] = Self.palette[others % Self.palette.count]
                others += 1
            }
        }

        rows = turns.enumerated().map { index, turn in
            let canonical = reverse[turn.label] ?? turn.label
            let end = index + 1 < turns.count ? turns[index + 1].start : .greatestFiniteMagnitude
            return Row(
                id: index,
                start: turn.start,
                end: end,
                label: turn.label,
                text: turn.text,
                color: colors[canonical] ?? .gray,
                isMe: canonical == "Me"
            )
        }
    }

    @ViewBuilder
    private func bubble(_ row: Row, active: Bool) -> some View {
        HStack(spacing: 0) {
            if row.isMe { Spacer(minLength: 40) }
            VStack(alignment: row.isMe ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    timecode(row)
                    Text(row.label).font(.caption.weight(.semibold)).foregroundStyle(row.color)
                }
                Text(row.text)
                    .textSelection(.enabled)
                    .multilineTextAlignment(row.isMe ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(row.color.opacity(active ? 0.28 : 0.13))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(row.color.opacity(active ? 0.9 : 0), lineWidth: 1.5)
            )
            .frame(maxWidth: 480, alignment: row.isMe ? .trailing : .leading)
            if !row.isMe { Spacer(minLength: 40) }
        }
    }

    /// Clickable timecode that seeks playback to this turn. Falls back to plain
    /// text when there's no audio to seek.
    @ViewBuilder
    private func timecode(_ row: Row) -> some View {
        if player.isReady {
            Button {
                player.seek(to: row.start)
                player.play()
            } label: {
                Text(CallAudioPlayer.clock(row.start)).font(.caption2.monospacedDigit())
            }
            .buttonStyle(.plain)
            .foregroundStyle(row.color)
            .help("Jump to this point in the audio")
            .pointerCursor()
        } else {
            Text(CallAudioPlayer.clock(row.start))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
