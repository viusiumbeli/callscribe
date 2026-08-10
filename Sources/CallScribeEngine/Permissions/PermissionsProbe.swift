@preconcurrency import AVFoundation
import AppKit
import ApplicationServices

public enum PermissionsProbe {
    /// Triggers the Microphone TCC prompt if undetermined; returns whether
    /// access is granted.
    public static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Already granted, checked synchronously. Dictation needs this: it starts
    /// recording from a key-press handler, where awaiting a TCC round-trip would
    /// cost the first syllables.
    public static var hasMicrophoneAccess: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Whether the app is trusted for Accessibility — dictation's one extra
    /// grant, covering both halves of it: watching for the Right Shift hold, and
    /// posting the ⌘V that inserts the text.
    public static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Ask for Accessibility, showing the system prompt that offers to open
    /// System Settings.
    ///
    /// Unlike Microphone this is not a callback API: the answer only arrives when
    /// the user flips the switch, at which point macOS restarts the app's
    /// event-tap eligibility. So this returns the state *now* — callers poll
    /// `isAccessibilityTrusted` rather than await a decision.
    @discardableResult
    public static func requestAccessibilityAccess() -> Bool {
        // The option key spelled out rather than via `kAXTrustedCheckOptionPrompt`:
        // the SDK imports that constant as a mutable global, which Swift 6 strict
        // concurrency rejects outright. The string is its documented value.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Open the Accessibility pane directly. The system prompt only appears once
    /// per app, so the menu item needs its own way in.
    public static func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
