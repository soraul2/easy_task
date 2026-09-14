import SwiftUI

/// A miniature of the actual neutral card, selected navigation, and primary action.
/// Uses the candidate palette rather than the currently active application's style.
public struct ThemePalettePreview: View {
    private let colors: AppThemeColorSet

    public init(preset: AppThemePreset) {
        colors = preset.colorSet(for: .light)
    }

    public var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("보드", systemImage: "rectangle.split.3x1")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(colors.accentForeground.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(colors.selectedTab.color, in: Capsule())
                Spacer(minLength: 4)
                Text("7")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(colors.onAccent.color)
                    .frame(width: 24, height: 24)
                    .background(colors.accentFill.color, in: Circle())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("오늘의 계획")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colors.primaryText.color)
                HStack(spacing: 4) {
                    Label("진행 중", systemImage: "play.circle")
                        .foregroundStyle(colors.accentForeground.color)
                    Spacer(minLength: 0)
                    Text("집중")
                        .foregroundStyle(colors.onAccent.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(colors.accentFill.color, in: RoundedRectangle(cornerRadius: 7))
                }
                .font(.caption2.weight(.medium))
            }
            .padding(10)
            .background(colors.panel.color, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10).stroke(colors.border.color, lineWidth: 1)
            }
        }
        .padding(10)
        .background(
            LinearGradient(colors: [colors.backgroundTop.color, colors.backgroundBottom.color],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .accessibilityHidden(true)
    }
}
