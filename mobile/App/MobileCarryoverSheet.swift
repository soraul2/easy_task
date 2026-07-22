#if os(iOS)
import PlanBaseCore
import Foundation
import SwiftData
import SwiftUI

struct MobileCarryoverSheet: View {
    var tasks: [TodoTask]
    var onApplied: (String) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var movedTaskIDs: Set<UUID> = []
    @State private var message: String?
    @State private var isErrorMessage = false

    private var remainingTasks: [TodoTask] {
        tasks.filter { !movedTaskIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                if remainingTasks.isEmpty {
                    ContentUnavailableView("이월할 작업 없음", systemImage: "tray")
                } else {
                    Section {
                        if let message {
                            Label(
                                message,
                                systemImage: isErrorMessage ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                            )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isErrorMessage ? Color.red : Color.secondary)
                        }
                        Button {
                            moveAllToToday()
                        } label: {
                            Label("모두 오늘로 이월", systemImage: "calendar.badge.plus")
                        }
                        Button(role: .destructive) {
                            completeAll()
                        } label: {
                            Label("원래 날짜에 모두 완료", systemImage: "checkmark.circle")
                        }
                    }
                    ForEach(remainingTasks) { task in
                        Button {
                            moveToToday(task)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title)
                                        .lineLimit(2)
                                    Text(task.plannedDayKey)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                            }
                        }
                    }
                }
            }
            .navigationTitle("이월함")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func completeAll() {
        let tasksToComplete = remainingTasks
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                TaskRules.completeOnPlannedDays(tasksToComplete)
            }
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
                    TaskRules.bringToToday(task, order: nextOrder, now: now)
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
                TaskRules.bringToToday(task, order: nextOrder, now: now)
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
