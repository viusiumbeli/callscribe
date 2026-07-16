import CallScribeCore
import SwiftUI

/// The transcript rendered as chat bubbles: "Me" on the right (accent tint),
/// other speakers on the left, each speaker color-coded. Every timecode is
/// clickable and seeks the audio player to that moment; the turn currently
/// playing is highlighted so the text follows the audio.
struct TranscriptView: View {
    let transcript: String
    let names: [String: String]
    let player: CallAudioPlayer

    /// Colors for non-"Me" speakers, assigned in first-appearance order.
    private static let palette: [Color] = [.green, .orange, .purple, .pink, .teal, .indigo, .brown]

    var body: some View {
        let turns = TranscriptParse.parse(transcript)
        if turns.isEmpty {
            Text("No transcript.").foregroundStyle(.secondary)
        } else {
            // A displayed label may be a renamed name; map it back to its
            // canonical form ("Speaker 1", "Me") so colors stay stable.
            let reverse = Dictionary(names.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
            let colors = colorMap(turns, reverse: reverse)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                    let canonical = reverse[turn.label] ?? turn.label
                    let color = colors[canonical] ?? .gray
                    let end = index + 1 < turns.count ? turns[index + 1].start : player.duration
                    let active = player.isPlaying
                        && player.currentTime >= turn.start
                        && player.currentTime < max(end, turn.start + 0.1)
                    bubble(turn, color: color, isMe: canonical == "Me", active: active)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func colorMap(_ turns: [TranscriptParse.Turn], reverse: [String: String]) -> [String: Color] {
        var map: [String: Color] = [:]
        var others = 0
        for turn in turns {
            let canonical = reverse[turn.label] ?? turn.label
            guard map[canonical] == nil else { continue }
            if canonical == "Me" {
                map[canonical] = .accentColor
            } else {
                map[canonical] = Self.palette[others % Self.palette.count]
                others += 1
            }
        }
        return map
    }

    @ViewBuilder
    private func bubble(_ turn: TranscriptParse.Turn, color: Color, isMe: Bool, active: Bool) -> some View {
        HStack(spacing: 0) {
            if isMe { Spacer(minLength: 40) }
            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    timecode(turn, color: color)
                    Text(turn.label).font(.caption.weight(.semibold)).foregroundStyle(color)
                }
                Text(turn.text)
                    .textSelection(.enabled)
                    .multilineTextAlignment(isMe ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(active ? 0.28 : 0.13))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color.opacity(active ? 0.9 : 0), lineWidth: 1.5)
            )
            .frame(maxWidth: 480, alignment: isMe ? .trailing : .leading)
            if !isMe { Spacer(minLength: 40) }
        }
    }

    /// Clickable timecode that seeks playback to this turn. Falls back to plain
    /// text when there's no audio to seek.
    @ViewBuilder
    private func timecode(_ turn: TranscriptParse.Turn, color: Color) -> some View {
        if player.isReady {
            Button {
                player.seek(to: turn.start)
                player.play()
            } label: {
                Text(CallAudioPlayer.clock(turn.start)).font(.caption2.monospacedDigit())
            }
            .buttonStyle(.plain)
            .foregroundStyle(color)
            .help("Jump to this point in the audio")
            .pointerCursor()
        } else {
            Text(CallAudioPlayer.clock(turn.start))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
