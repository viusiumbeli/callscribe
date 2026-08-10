import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

/// Puts text where the cursor is, in whatever app owns it.
///
/// By clipboard + a synthetic ⌘V, which is the only method that works
/// everywhere. Setting `kAXSelectedTextAttribute` through the Accessibility API
/// is the tidier-looking option and fails silently in too many of the places
/// people actually type: Electron apps, terminals, most web views. ⌘V is what
/// those apps all implement.
///
/// The user's clipboard is snapshotted first and put back afterwards, so
/// dictating doesn't cost them whatever they had copied.
///
/// `@MainActor` for `NSPasteboard`, which Apple does not document as
/// thread-safe. The awaits inside release the actor, so nothing blocks the UI.
@MainActor
public enum TextInserter {
    public enum Outcome: Sendable, Equatable {
        case pasted
        /// Couldn't paste, but the text is on the clipboard — a genuinely useful
        /// fallback, since ⌘V by hand then finishes the job.
        case copiedOnly(reason: String)
    }

    /// How long to let the pasteboard settle, and any physically-held modifier
    /// clear, before posting ⌘V.
    private static let settleDelay = Duration.milliseconds(120)
    /// How long to leave our text on the clipboard for the target app to read.
    private static let restoreDelay = Duration.milliseconds(500)
    /// Skip snapshotting a clipboard larger than this rather than hold a copy in
    /// memory. Restoring a 200 MB image isn't worth the residency.
    private static let maxSnapshotBytes = 16 * 1024 * 1024

    public static func insert(_ text: String) async -> Outcome {
        guard !text.isEmpty else { return .copiedOnly(reason: "Nothing to insert.") }

        // Secure input (a focused password field) blackholes synthetic events, so
        // check before touching the clipboard — reporting a paste that silently
        // went nowhere would be worse than not trying.
        if IsSecureEventInputEnabled() {
            copy(text)
            return .copiedOnly(reason: "A password field has keyboard input locked. Text copied instead.")
        }
        guard AXIsProcessTrusted() else {
            copy(text)
            return .copiedOnly(reason: "Accessibility access is off, so ⌘V can't be sent. Text copied instead.")
        }

        let snapshot = snapshotClipboard()
        let ours = copy(text)
        try? await Task.sleep(for: settleDelay)
        guard postCommandV() else {
            return .copiedOnly(reason: "Could not synthesize ⌘V. Text copied instead.")
        }
        restoreClipboard(snapshot, ifStillAt: ours)
        return .pasted
    }

    // MARK: - Clipboard

    @discardableResult
    private static func copy(_ text: String) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return pasteboard.changeCount
    }

    /// Every type of every item, by raw type name so the value stays `Sendable`.
    /// nil means "don't restore": either nothing was there, or it was too big.
    private static func snapshotClipboard() -> [[String: Data]]? {
        guard let items = NSPasteboard.general.pasteboardItems, !items.isEmpty else { return nil }
        var total = 0
        var snapshot: [[String: Data]] = []
        for item in items {
            var copied: [String: Data] = [:]
            for type in item.types {
                // File promises and other lazily-provided types answer nil here;
                // they can't be reproduced and are dropped.
                guard let data = item.data(forType: type) else { continue }
                total += data.count
                guard total <= maxSnapshotBytes else {
                    Log.shared.info("dictation: clipboard too large to preserve (>\(maxSnapshotBytes / 1_000_000) MB)")
                    return nil
                }
                copied[type.rawValue] = data
            }
            snapshot.append(copied)
        }
        return snapshot
    }

    /// Put the old clipboard back, once the target app has had time to read ours.
    ///
    /// Unawaited: the caller has a HUD to update and shouldn't wait half a second
    /// to hear that the paste worked.
    private static func restoreClipboard(_ snapshot: [[String: Data]]?, ifStillAt changeCount: Int) {
        guard let snapshot else { return }
        Task { @MainActor in
            try? await Task.sleep(for: restoreDelay)
            let pasteboard = NSPasteboard.general
            // If something else has written to the clipboard since, that's the
            // user's newer copy — restoring over it would be the real data loss.
            guard pasteboard.changeCount == changeCount else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects(snapshot.map { fields in
                let item = NSPasteboardItem()
                for (type, data) in fields {
                    item.setData(data, forType: NSPasteboard.PasteboardType(type))
                }
                return item
            })
        }
    }

    // MARK: - Synthetic ⌘V

    private static func postCommandV() -> Bool {
        // `.privateState`, not `.hidSystemState`: a source tied to the real HID
        // state inherits whatever modifiers are physically down, and the user has
        // just this moment been holding Right Shift — ⌘⇧V is a different command
        // in a lot of apps (paste-and-match-style, or nothing at all).
        guard let source = CGEventSource(stateID: .privateState) else { return false }
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        else { return false }
        // ⌘ stays asserted across both halves; releasing it between them reads as
        // a bare V to apps that track flags themselves.
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
