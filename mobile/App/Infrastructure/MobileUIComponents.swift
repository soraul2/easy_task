#if os(iOS)
import PlanBaseCore
import SwiftUI

typealias TodoTask = Task

enum MobileLayout {
    static let bottomTabClearance: CGFloat = 96
}

struct MobileChecklistProgressChip: View {
    var progress: ChecklistProgress

    var body: some View {
        if !progress.isEmpty {
            Label(
                "\(progress.completedCount)/\(progress.totalCount)",
                systemImage: progress.isComplete ? "checkmark.circle.fill" : "checklist"
            )
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(AppTheme.cardMutedText)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(AppTheme.panel.opacity(0.52), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("checklist-progress")
            .accessibilityLabel("체크리스트 진행률")
            .accessibilityValue(
                "\(progress.completedCount)개 완료, 전체 \(progress.totalCount)개"
            )
        }
    }
}

struct MobileThemeButton: View {
    var action: () -> Void
    var minimumHitSize: CGFloat = 34

    var body: some View {
        Button(action: action) {
            Image(systemName: "paintpalette")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: minimumHitSize, height: minimumHitSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("테마 선택")
        .accessibilityHint("앱 색상 테마 변경")
    }
}
#endif
