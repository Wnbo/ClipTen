import AppKit
import SwiftUI

private struct InteractiveCursor: ViewModifier {
    let enabled: Bool
    @State private var ownsCursor = false

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    if enabled {
                        ownsCursor = true
                        NSCursor.pointingHand.set()
                    }
                case .ended:
                    resetCursor()
                }
            }
            .onChange(of: enabled) { enabled in
                if !enabled { resetCursor() }
            }
            .onDisappear { resetCursor() }
    }

    private func resetCursor() {
        if ownsCursor {
            ownsCursor = false
            NSCursor.arrow.set()
        }
    }
}

extension View {
    func interactiveCursor(enabled: Bool = true) -> some View {
        modifier(InteractiveCursor(enabled: enabled))
    }
}

struct HoverButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var horizontalPadding: CGFloat = 6
    var verticalPadding: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        HoverButtonBody(configuration: configuration, tint: tint,
                        horizontalPadding: horizontalPadding, verticalPadding: verticalPadding)
    }
}

private struct HoverButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(isEnabled ? (hovering ? tint : Color.secondary) : Color.secondary.opacity(0.35))
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(tint.opacity(isEnabled ? (configuration.isPressed ? 0.22 : (hovering ? 0.12 : 0)) : 0))
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .interactiveCursor(enabled: isEnabled)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
