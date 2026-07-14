import SwiftUI

struct MenuBarView: View {
    var body: some View {
        Text("CallScribe \(AppInfo.version)")
        Divider()
        Button("Quit CallScribe") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
