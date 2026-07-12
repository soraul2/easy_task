#if os(iOS)
import EasyTaskCore
import Foundation
import SwiftData
import SwiftUI

struct MobileCarryoverSheet: View {
    var tasks: [TodoTask]
    var targetDate: Date
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
                            moveAllToTargetDate()
                        } label: {
                            Label("모두 이 날짜로 이월", systemImage: "calendar.badge.plus")
                        }
                        Button(role: .destructive) {
                            completeAll()
                        } label: {
                            Label("모두 완료 처리", systemImage: "checkmark.circle")
                        }
                    }
                    ForEach(remainingTasks) { task in
                        Button {
                            moveToTargetDate(task)
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
                TaskRules.completeAll(tasksToComplete, completionDayKey: DayKey.key(for: targetDate))
            }
            onApplied("\(tasksToComplete.count)개 이월 작업을 완료 처리했어요")
            dismiss()
        } catch {
            showError("이월 작업을 완료하지 못했습니다")
        }
    }

    private func moveAllToTargetDate() {
        let tasksToMove = remainingTasks
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                for task in tasksToMove {
                    TaskRules.move(task, to: targetDate)
                }
            }
            onApplied("\(tasksToMove.count)개 작업을 \(DayKey.display(targetDate))로 이월했어요")
            dismiss()
        } catch {
            showError("작업을 이월하지 못했습니다")
        }
    }

    private func moveToTargetDate(_ task: TodoTask) {
        do {
            try PersistenceCommandService.perform(in: modelContext) {
                TaskRules.move(task, to: targetDate)
            }
            movedTaskIDs.insert(task.id)
            let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let notice = title.isEmpty ? "작업을 \(DayKey.display(targetDate))로 이월했어요" : "\(title) · \(DayKey.display(targetDate))로 이월했어요"
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
