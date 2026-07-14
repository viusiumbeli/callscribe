import Foundation

public enum AudioCaptureError: LocalizedError {
    case microphoneAccessDenied
    case coreAudio(String, OSStatus)
    case formatUnsupported(String)

    public var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied:
            "Microphone access was denied. Grant it in System Settings → Privacy & Security → Microphone."
        case .coreAudio(let what, let status):
            "Core Audio call failed (\(what)): OSStatus \(status)"
        case .formatUnsupported(let detail):
            "Unsupported audio format: \(detail)"
        }
    }
}

func checkOSStatus(_ status: OSStatus, _ what: String) throws {
    guard status == noErr else { throw AudioCaptureError.coreAudio(what, status) }
}
