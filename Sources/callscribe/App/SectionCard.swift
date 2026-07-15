import AppKit
import SwiftUI

/// A titled, collapsible card: an icon + title header, a divider, and padded
/// content, wrapped in a bordered rounded background so each section reads as a
/// distinct block instead of blending with its neighbours.
struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    /// When set, a copy button appears in the header.
    var onCopy: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The whole padded header row toggles; the copy button (a real
            // Button) still intercepts its own clicks.
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: 18)
                Text(title).font(.headline)
                Spacer(minLength: 0)

                if let onCopy {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Copy this section")
                    .pointerCursor()
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            }
            .pointerCursor()

            if isExpanded {
                Divider()
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }
}

extension View {
    /// Show the pointing-hand cursor while hovering (macOS controls don't do
    /// this for plain/borderless buttons).
    func pointerCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
