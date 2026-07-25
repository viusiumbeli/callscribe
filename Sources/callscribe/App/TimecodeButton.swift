import SwiftUI

/// A clickable timecode that seeks playback to that point in the call. Falls back
/// to plain text when there's no audio to seek. Shared by the transcript bubbles
/// and the summary's topic rows.
struct TimecodeButton: View {
    let start: TimeInterval
    var color: Color = .secondary
    let player: CallAudioPlayer

    var body: some View {
        if player.isReady {
            Button {
                player.seek(to: start)
                player.play()
            } label: {
                label
            }
            .buttonStyle(.plain)
            .foregroundStyle(color)
            .help("Jump to this point in the audio")
            .pointerCursor()
        } else {
            label.foregroundStyle(.secondary)
        }
    }

    private var label: Text {
        Text(CallAudioPlayer.clock(start)).font(.caption2.monospacedDigit())
    }
}
