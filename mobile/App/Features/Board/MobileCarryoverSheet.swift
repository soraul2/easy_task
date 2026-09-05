#if os(iOS)
import PlanBaseCore
import Foundation
import SwiftData
import SwiftUI

private struct PendingMobileCarryoverCompletion {
    var taskIDs: [UUID]
    var upcomingReminderCount: Int
}

struct MobileCarryoverSheet: View {
    var tasks: [TodoTask]
    var onApplied: (String) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var movedTaskIDs: Set<UUID> = []
    @State private var message: String?
    @State private var isErrorMessage = false
    @State private var pendingCompletion: PendingMobileCarryoverCompletion?

    private var remainingTasks: [TodoTask] {
        tasks.filter { !movedTaskIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let message {
                    Section {
                        MobileNoticeBanner(message: message, tone: isErrorMessage ? .error : .success)
                            .accessibilityIdentifier("carryover-result-notice")
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if remainingTasks.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("이월할 작업 없음")
                                .lineLimit(nil)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "tray")
                        }
                    } description: {
                        Text("과거 날짜에 남아 있는 미완료 작업이 없습니다.")
                    }
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        Button {
                            moveAllToToday()
                        } label: {
                            Label("모두 오늘로 이월", systemImage: "calendar.badge.plus")
                        }
                        Button(role: .destructive) {
                            requestCompleteAll()
                        } label: {
                            Label("원래 날짜에 모두 완료", systemImage: "checkmark.circle")
                        }
                    }
                    .listRowBackground(AppTheme.panel)
                    ForEach(remainingTasks) { task in
                        Button {
                            moveToToday(task)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title)
                                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                    Text(DayKey.date(from: task.plannedDayKey).map(DayKey.display) ?? task.plannedDayKey)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                            }
                            .frame(minHeight: PlanBaseControlMetrics.minimumTargetSize)
                        }
                        .accessibilityLabel("\(task.title), 오늘로 이월")
                        .accessibilityValue("원래 날짜 \(DayKey.date(from: task.plannedDayKey).map(DayKey.display) ?? task.plannedDayKey)")
                        .accessibilityHint("원래 날짜의 미완료 작업을 오늘 할 일로 옮겨요")
                        .listRowBackground(AppTheme.panel)
                    }
                }
            }
            .navigationTitle("이월함")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .foregroundStyle(AppTheme.primaryText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .tint(AppTheme.accent)
        .presentationBackground(AppTheme.background)
        .alert(
            "예정된 알림이 있습니다",
            isPresented: Binding(
                get: { pendingCompletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingCompletion = nil
                    }
                }
            ),
            presenting: pendingCompletion
        ) { pending in
            Button("완료하기", role: .destructive) {
                pendingCompletion = nil
                completeAll(taskIDs: pending.taskIDs)
            }
            Button("취소", role: .cancel) {}
        } message: { pending in
            Text(
                "\(pending.upcomingReminderCount)개의 작업에 예정된 알림이 있습니다. " +
                    "모두 완료하면 해당 알림이 중지되며 설정 기록은 계속 유지됩니다."
            )
        }
        .presentationDetents([.medium, .large])
    }

    private func requestCompleteAll() {
        let tasksToComplete = remainingTasks
        let pending = PendingMobileCarryoverCompletion(
            taskIDs: tasksToComplete.map(\.id),
            upcomingReminderCount: TaskReminderRules.upcomingReminderCount(
                in: tasksToComplete,
                now: Date()
            )
        )
        if pending.upcomingReminderCount > 0 {
            pendingCompletion = pending
        } else {
            completeAll(taskIDs: pending.taskIDs)
        }
    }

    private func completeAll(taskIDs: [UUID]) {
        do {
            var tasksToComplete: [TodoTask] = []
            for taskID in taskIDs {
                if let task = try modelContext.fetch(
                    BoundedQueryService.taskDescriptor(id: taskID)
                ).first,
                   task.status != TaskStatus.done.rawValue {
                    tasksToComplete.append(task)
                }
            }
            guard !tasksToComplete.isEmpty else {
                showError("완료할 작업이 변경되었습니다")
                return
            }
            try PersistenceCommandService.perform(in: modelContext) {
                try TaskLifecycleService.completeOnPlannedDays(
                    tasksToComplete,
                    in: modelContext,
                    now: Date()
                )
            }
            TaskNotificationScheduler.shared.cancelNotifications(
                for: tasksToComplete.map(\.id)
            )
            onApplied("\(tasksToComplete.count)개 작업을 원래 날짜에 완료 처리했어요")
            dismiss()
        } catch {
            showError("이월 작업을 완료하지 못했습니다")
        }
    }

    private func moveAllToToday() {
        let tasksToMove = remainingTasks
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                let now = Date()
                let todayKey = DayKey.key(for: now)
                var nextOrder = try BoundedQueryService.nextOrder(
                    in: modelContext,
                    dayKey: todayKey,
                    status: .todo
                )
                for task in tasksToMove {
                    try TaskLifecycleService.bringToToday(
                        task,
                        in: modelContext,
                        order: nextOrder,
                        now: now
                    )
                    nextOrder += 100
                }
            }
            onApplied("\(tasksToMove.count)개 작업을 오늘로 이월했어요")
            dismiss()
        } catch {
            showError("작업을 이월하지 못했습니다")
        }
    }

    private func moveToToday(_ task: TodoTask) {
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                let now = Date()
                let nextOrder = try BoundedQueryService.nextOrder(
                    in: modelContext,
                    dayKey: DayKey.key(for: now),
                    status: .todo
                )
                try TaskLifecycleService.bringToToday(
                    task,
                    in: modelContext,
                    order: nextOrder,
                    now: now
                )
            }
            movedTaskIDs.insert(task.id)
            let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let notice = title.isEmpty ? "작업을 오늘로 이월했어요" : "\(title) · 오늘로 이월했어요"
            isErrorMessage = false
            message = notice
            onApplied(notice)
        } catch {
            showError("작업을 이월하지 못했습니다")
        }
    }

    private func showError(_ errorMessage: String) {
        isErrorMessage = true
        message = errorMessage
    }
}

#endif
