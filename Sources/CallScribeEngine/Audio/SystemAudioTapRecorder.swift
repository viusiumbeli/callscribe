import AVFAudio
import CoreAudio
import Foundation

/// Records everything other processes play (the remote-participants track)
/// via a Core Audio process tap — the AudioCap pattern:
///
///   1. a global tap that excludes our own process,
///   2. wrapped in a private aggregate device clocked by the default output,
///   3. read through an IOProc block scheduled on the sink's serial queue,
///      so buffers are converted and written synchronously with zero copies.
///
/// Requires the Audio Recording TCC grant (`NSAudioCaptureUsageDescription`);
/// creating the tap triggers the system prompt on first use.
final class SystemAudioTapRecorder: @unchecked Sendable {
    private let sink: TrackSink
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    init(sink: TrackSink) {
        self.sink = sink
    }

    func start() throws {
        let ownProcess = try CoreAudioSupport.translatePIDToProcessObject(getpid())

        let description = CATapDescription(
            stereoGlobalTapButExcludeProcesses: [ownProcess]
        )
        description.name = "CallScribe System Audio Tap"
        description.isPrivate = true
        // muteBehavior defaults to CATapUnmuted — the user keeps hearing the call.

        var tapID = AudioObjectID(kAudioObjectUnknown)
        try checkOSStatus(AudioHardwareCreateProcessTap(description, &tapID), "create process tap")
        self.tapID = tapID

        do {
            var asbd = try CoreAudioSupport.tapStreamDescription(tapID)
            guard let format = AVAudioFormat(streamDescription: &asbd) else {
                throw AudioCaptureError.formatUnsupported("tap stream description not representable")
            }

            let outputUID = try CoreAudioSupport.deviceUID(CoreAudioSupport.defaultOutputDevice())
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "CallScribe Tap Aggregate",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [
                    [kAudioSubDeviceUIDKey: outputUID]
                ],
                kAudioAggregateDeviceTapListKey: [
                    [
                        kAudioSubTapDriftCompensationKey: true,
                        kAudioSubTapUIDKey: description.uuid.uuidString,
                    ]
                ],
            ]
            var aggregateID = AudioObjectID(kAudioObjectUnknown)
            try checkOSStatus(
                AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID),
                "create aggregate device"
            )
            self.aggregateID = aggregateID

            // Scheduling the IOProc on the sink queue lets us consume the
            // buffer list synchronously (pointers are only valid inside the
            // block), so no copy is needed.
            let sink = self.sink
            var procID: AudioDeviceIOProcID?
            try checkOSStatus(
                AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, sink.queue) {
                    _, inInputData, _, _, _ in
                    guard let buffer = AVAudioPCMBuffer(
                        pcmFormat: format,
                        bufferListNoCopy: inInputData,
                        deallocator: nil
                    ), buffer.frameLength > 0 else { return }
                    sink.processInline(buffer)
                },
                "create IOProc"
            )
            self.ioProcID = procID

            try checkOSStatus(AudioDeviceStart(aggregateID, procID), "start aggregate device")
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let procID = ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            ioProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }
}
