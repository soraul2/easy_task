import SwiftUI

/// A quiet placeholder below either a status picker or a column heading.
public struct BoardEmptyStateView: View {
    public let status: TaskStatus
    public let isBoardEmpty: Bool
    public let showsIcon: Bool
    public let minimumHeight: CGFloat
    public let onAddTask: () -> Void
    @ScaledMetric(relativeTo: .headline) private var titleSize = 16.0
    @ScaledMetric(relativeTo: .subheadline) private var descriptionSize = 13.0
    @ScaledMetric(relativeTo: .title2) private var iconSize = 28.0

    public init(
        status: TaskStatus,
        isBoardEmpty: Bool,
        showsIcon: Bool = true,
        minimumHeight: CGFloat = 240,
        onAddTask: @escaping () -> Void
    ) {
        self.status = status
        self.isBoardEmpty = isBoardEmpty
        self.showsIcon = showsIcon
        self.minimumHeight = minimumHeight
        self.onAddTask = onAddTask
    }

    public var body: some View {
        VStack(spacing: 8) {
            if showsIcon {
                Image(systemName: status.emptyStateSystemImage)
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(AppTheme.secondaryText.opacity(0.7))
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)
            }

            Text(status.emptyStateTitle(isBoardEmpty: isBoardEmpty))
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(status.emptyStateDescription)
                .font(.system(size: descriptionSize))
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if status == .todo && isBoardEmpty {
                Button("할 일 추가", systemImage: "plus", action: onAddTask)
                    .buttonStyle(PlanBaseButtonStyle(.secondary))
                    .padding(.top, 8)
                    .accessibilityIdentifier("board-empty-add-task")
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        // Keep titles aligned across columns even when descriptions wrap.
        .padding(.top, minimumHeight / 3)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .top)
        .accessibilityElement(children: .contain)
    }
}
