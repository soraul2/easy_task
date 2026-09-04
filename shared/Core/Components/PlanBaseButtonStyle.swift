import SwiftUI

/// Shared action surfaces use the palette's resolved foreground, including light accents in dark themes.
public struct PlanBaseButtonStyle: ButtonStyle {
    public enum Emphasis { case primary, secondary }
    private let emphasis: Emphasis
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ emphasis: Emphasis = .primary) { self.emphasis = emphasis }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: minimumHeight)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(emphasis == .secondary ? AppTheme.border : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.76 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        if !isEnabled { return AppTheme.secondaryText }
        return emphasis == .primary ? AppTheme.eventForeground : AppTheme.primaryText
    }

    private var background: Color {
        if !isEnabled { return AppTheme.input }
        return emphasis == .primary ? AppTheme.event : AppTheme.panel
    }

    private var minimumHeight: CGFloat {
        #if os(macOS)
        32
        #else
        44
        #endif
    }
}
