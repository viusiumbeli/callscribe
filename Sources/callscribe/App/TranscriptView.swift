import CallScribeCore
import SwiftUI

/// One utterance ready to render: real `[start, end]` times (so playback
/// highlight can track overlapping speech), a canonical speaker label
/// ("Me"/"Speaker 1"), and the text.
struct Turn: Identifiable {
    let id: Int
    let start: TimeInterval
    let end: TimeInterval
    let label: String
    let text: String
}

/// The transcript rendered as chat bubbles: "Me" on the right (accent tint),
/// other speakers on the left, each speaker color-coded. Every timecode is
/// clickable and seeks the audio player; a turn is highlighted whenever the
/// playhead is within its real time range — so a long monologue stays lit for
/// its whole duration and a short interjection nested inside it lights only when
/// it actually occurs (both can be lit at once during overlap).
struct TranscriptView: View {
    let turns: [Turn]
    let names: [String: String]
    let player: CallAudioPlayer

    /// Colors for non-"Me" speakers, assigned in first-appearance order.
    private static let palette: [Color] = [.teal, .orange, .pink, .green, .brown, .cyan, .mint]

    var body: some View {
        if turns.isEmpty {
            Text("No transcript.").foregroundStyle(.secondary)
        } else {
            let colors = colorMap(turns)
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(turns) { turn in
                    let active = player.isPlaying
                        && player.currentTime >= turn.start
                        && player.currentTime <= turn.end
                    bubble(turn, color: colors[turn.label] ?? .gray, isMe: turn.label == "Me", active: active)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func colorMap(_ turns: [Turn]) -> [String: Color] {
        var map: [String: Color] = [:]
        var others = 0
        for turn in turns where map[turn.label] == nil {
            if turn.label == "Me" {
                map[turn.label] = .brand
            } else {
                map[turn.label] = Self.palette[others % Self.palette.count]
                others += 1
            }
        }
        return map
    }

    @ViewBuilder
    private func bubble(_ turn: Turn, color: Color, isMe: Bool, active: Bool) -> some View {
        HStack(spacing: 0) {
            if isMe { Spacer(minLength: 40) }
            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    timecode(turn, color: color)
                    Text(names[turn.label] ?? turn.label)
                        .font(.caption.weight(.semibold)).foregroundStyle(color)
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
    private func timecode(_ turn: Turn, color: Color) -> some View {
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
