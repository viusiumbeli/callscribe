import AppKit
import SwiftUI

struct MenuBarView: View {
    @Bindable var state: AppState
    @Bindable var dictation: DictationController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ControlBar(state: state)
        Divider()
        Toggle("Dictation — hold Right Shift", isOn: $dictation.isEnabled)
        // Only while dictation can hear you but not paste — the text goes to the
        // clipboard instead, and this is the way out of that.
        if dictation.needsAccessibility {
            Button("Grant Accessibility Access…") { dictation.openAccessibilitySettings() }
        }
        Button("Dictations…") { dictation.showDictations() }
        Divider()
        Button("Open Window") { openWindow(id: "main") }
        Button("Quit CallScribe") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
