@preconcurrency import AVFoundation

public enum PermissionsProbe {
    /// Triggers the Microphone TCC prompt if undetermined; returns whether
    /// access is granted.
    public static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
