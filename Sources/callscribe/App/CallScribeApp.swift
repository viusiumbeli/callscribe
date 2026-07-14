import AppKit
import SwiftUI

struct CallScribeApp: App {
    init() {
        // LSUIElement covers the bundled case; this covers bare-binary runs.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: "waveform.circle")
        }
    }
}
