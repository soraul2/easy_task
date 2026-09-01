import PlanBaseCore
import SwiftUI

struct DesktopDiaryTaskSummarySection: View {
    let summary: DailyReviewTaskSummary
    let selectedDayKey: String
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                Text("그날 계획한 일")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)

                if summary.totalCount == 0 {
                    Text("이 날짜에 계획한 작업이 없습니다")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                } else {
                    taskGroup(
                        title: "완료",
                        systemImage: "checkmark.circle.fill",
                        color: AppTheme.done,
                        items: summary.completed
                    )
                    taskGroup(
                        title: "진행 중",
                        systemImage: "clock.fill",
                        color: AppTheme.doing,
                        items: summary.inProgress
                    )
                    taskGroup(
                        title: "할 일",
                        systemImage: "circle",
                        color: AppTheme.todo,
                        items: summary.pending
                    )
                }

                Divider().overlay(AppTheme.border)

                Text("그날 실제 완료한 일")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)

                if summary.actualCompleted.isEmpty {
                    Text("이 날짜에 완료한 작업이 없습니다")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                } else {
                    taskGroup(
                        title: "완료",
                        systemImage: "checkmark.circle.fill",
                        color: AppTheme.done,
                        items: summary.actualCompleted,
                        showsPlannedDate: true
                    )
                }
            }
            .padding(.top, 14)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("작업 요약")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)

                HStack(spacing: 8) {
                    countChip(title: "완료", count: summary.completed.count, color: AppTheme.done)
                    countChip(title: "진행 중", count: summary.inProgress.count, color: AppTheme.doing)
                    countChip(title: "할 일", count: summary.pending.count, color: AppTheme.todo)
                    countChip(title: "실제 완료", count: summary.actualCompleted.count, color: AppTheme.done)
                }
            }
        }
        .tint(AppTheme.secondaryText)
        .padding(16)
        .background(AppTheme.input.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .accessibilityIdentifier("desktop-review-task-summary")
    }

    private func countChip(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(title) \(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(color.opacity(0.16), in: Capsule())
    }

    @ViewBuilder
    private func taskGroup(
        title: String,
        systemImage: String,
        color: Color,
        items: [DailyReviewTaskSummaryItem],
        showsPlannedDate: Bool = false
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)

                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color)
                            .frame(width: 16)

                        Text(item.title)
                            .font(.callout)
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        if let detailText = taskDetailText(
                            for: item,
                            showsPlannedDate: showsPlannedDate
                        ) {
                            Text(detailText)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
            }
        }
    }

    private func taskDetailText(
        for item: DailyReviewTaskSummaryItem,
        showsPlannedDate: Bool
    ) -> String? {
        if showsPlannedDate, item.plannedDayKey != selectedDayKey {
            guard let date = DayKey.date(from: item.plannedDayKey) else {
                return "계획 \(item.plannedDayKey)"
            }
            let components = DayKey.calendar.dateComponents([.month, .day], from: date)
            guard let month = components.month, let day = components.day else {
                return "계획 \(item.plannedDayKey)"
            }
            return "계획 \(month)월 \(day)일"
        }
        guard item.isCarryover,
              let date = DayKey.date(from: item.plannedDayKey) else { return nil }
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return nil }
        return "\(month)월 \(day)일에서 이월"
    }
}
