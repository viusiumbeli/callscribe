import AppKit
import SwiftUI

/// What the dictation overlay is currently saying.
enum DictationStatus: Equatable {
    case listening
    case loadingModel
    case transcribing
    case note(String)
    case failure(String)
}

/// Observable backing for the overlay, so status and level changes redraw the
/// SwiftUI content without rebuilding the panel.
@MainActor
@Observable
final class DictationHUDModel {
    var status: DictationStatus = .listening
    /// Smoothed 0…1 input level, for the meter.
    private(set) var level: Double = 0

    /// Fast attack, slow release: a meter that decayed as fast as the signal
    /// reads as flicker rather than as speech.
    func report(rms: Float) {
        // Speech RMS sits around 0.01–0.2, so raw values would barely move the
        // bar. Square-rooted and scaled to spread that range over the meter.
        let scaled = min(1, Double(rms).squareRoot() * 2.5)
        level = max(scaled, level * 0.82)
    }

    func resetLevel() { level = 0 }
}

/// The floating "Listening…" overlay.
///
/// The whole point of this class is that it must **not take focus**. Dictation
/// pastes into whatever app owns the cursor, so if showing the overlay activated
/// CallScribe, the text would land in CallScribe instead. Hence a
/// `.nonactivatingPanel` ordered in with `orderFrontRegardless()` — never
/// `makeKeyAndOrderFront`, and no `NSApp.activate` anywhere near it.
@MainActor
final class DictationHUD {
    private static let size = NSSize(width: 260, height: 60)
    /// Clear of the Dock in its default position.
    private static let bottomInset: CGFloat = 120

    let model = DictationHUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ status: DictationStatus) {
        hideTask?.cancel()
        hideTask = nil
        model.status = status
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    /// Show a final message, then fade out on its own.
    func flash(_ status: DictationStatus, for seconds: TimeInterval = 2) {
        show(status)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
        model.resetLevel()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Above normal windows and full-screen apps, below the menu bar's own.
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false          // the card inside draws its own
        panel.ignoresMouseEvents = true  // never intercept a click meant for the app behind
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        // Follows the user across Spaces and over full-screen apps; `.stationary`
        // keeps it from sliding during a Space switch.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.contentView = NSHostingView(rootView: DictationHUDView(model: model))
        return panel
    }

    /// Bottom-centre of whichever screen the pointer is on — the best available
    /// proxy for "where the user is looking" without asking for more permissions.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - Self.size.width / 2,
            y: frame.minY + Self.bottomInset
        ))
    }
}

// MARK: - Content

private struct DictationHUDView: View {
    @Bindable var model: DictationHUDModel

    var body: some View {
        HStack(spacing: Spacing.md) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if case .listening = model.status {
                    LevelMeter(level: model.level)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        .animation(.easeOut(duration: 0.15), value: model.status)
    }

    @ViewBuilder private var icon: some View {
        switch model.status {
        case .listening:
            Image(systemName: "mic.fill")
                .foregroundStyle(Color.brand)
                .font(.title3)
        case .loadingModel, .transcribing:
            ProgressView()
                .controlSize(.small)
        case .note:
            Image(systemName: "text.cursor")
                .foregroundStyle(Color.brand)
                .font(.title3)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
        }
    }

    private var label: String {
        switch model.status {
        case .listening: "Listening…"
        case .loadingModel: "Loading the model…"
        case .transcribing: "Transcribing…"
        case .note(let text): text
        case .failure(let text): text
        }
    }
}

/// A single bar that tracks the mic level — the answer to "is it hearing me?".
private struct LevelMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(LinearGradient.brand)
                    .frame(width: max(2, geometry.size.width * level))
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
