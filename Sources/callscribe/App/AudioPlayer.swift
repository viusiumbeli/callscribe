import AVFoundation
import CallScribeCore
import Foundation
import Observation

/// Plays a call's two tracks (mic = "Me", system = "Others") mixed and synced
/// through a single AVPlayer, so the whole conversation is heard with one
/// transport. Tolerates a missing track.
@MainActor
@Observable
final class CallAudioPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isReady = false

    private var player: AVPlayer?
    private var observer: Any?

    /// (Re)build the player for a call folder. No-op-safe if neither WAV exists.
    func load(_ folder: CallFolder) {
        teardown()
        Task { await build(folder) }
    }

    private func build(_ folder: CallFolder) async {
        let composition = AVMutableComposition()
        var maxDuration = CMTime.zero

        for wav in [folder.micWAV, folder.systemWAV] {
            guard FileManager.default.fileExists(atPath: wav.path) else { continue }
            let asset = AVURLAsset(url: wav)
            guard let sourceTrack = try? await asset.loadTracks(withMediaType: .audio).first,
                  let assetDuration = try? await asset.load(.duration),
                  let track = composition.addMutableTrack(
                      withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let range = CMTimeRange(start: .zero, duration: assetDuration)
            try? track.insertTimeRange(range, of: sourceTrack, at: .zero)
            if assetDuration > maxDuration { maxDuration = assetDuration }
        }

        guard maxDuration > .zero else { return }
        duration = maxDuration.seconds

        let player = AVPlayer(playerItem: AVPlayerItem(asset: composition))
        self.player = player
        isReady = true

        // Drive the scrubber and stop state.
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds
                if self.isPlaying, time.seconds >= self.duration - 0.05 {
                    self.pause()
                    self.seek(to: 0)
                }
            }
        }
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        if currentTime >= duration - 0.05 { seek(to: 0) }
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func seek(to seconds: TimeInterval) {
        currentTime = seconds
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func teardown() {
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        player?.pause()
        player = nil
        isPlaying = false
        isReady = false
        currentTime = 0
        duration = 0
    }

    static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let t = Int(seconds)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }
}
