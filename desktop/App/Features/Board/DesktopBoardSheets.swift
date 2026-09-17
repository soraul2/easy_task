import SwiftData
import SwiftUI
import PlanBaseCore

private struct PendingDesktopCarryoverCompletion {
    var taskIDs: [UUID]
    var upcomingReminderCount: Int
}

struct CarryoverSheet: View {
    var session: CarryoverInboxSession
    private var tasks: [Task] { session.displayedTasks }
    @Binding var failureMessage: String?
    var onBringToToday: (Task) -> Void
    var onCompleteAll: ([UUID]) -> Void
    var onDelete: (Task) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pendingCompletion: PendingDesktopCarryoverCompletion?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("이월함")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("과거 날짜의 미완료 작업을 오늘로 가져오거나 원래 날짜에서 완료 처리합니다.")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                if !tasks.isEmpty {
                    Button {
                        requestCompleteAll()
                    } label: {
                        Label("원래 날짜에 모두 완료", systemImage: "checkmark.circle")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(PlanBaseButtonStyle(.secondary))
                    .help("이월함의 모든 작업을 각 작업의 원래 날짜에서 완료 상태로 변경")
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: PlanBaseControlMetrics.minimumTargetSize,
                               height: PlanBaseControlMetrics.minimumTargetSize)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.secondaryText)
                .accessibilityLabel("이월함 닫기")
                .keyboardShortcut(.cancelAction)
            }

            CarryoverInboxSummary(session: session)

            if tasks.isEmpty && session.errorMessage == nil {
                EmptySheetState(
                    symbol: "tray",
                    title: "이월할 작업 없음",
                    message: "과거 날짜에 남아 있는 미완료 작업이 없습니다."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach([true, false], id: \.self) { isNew in
                            let group = tasks.filter {
                                session.presentedNewKeys.contains(CarryoverEntryKey($0)) == isNew
                            }
                            if !group.isEmpty {
                                Text(isNew ? "새로 들어온 작업" : "이전에 남은 작업")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                                ForEach(group) { task in
                                    CarryoverTaskRow(
                                        task: task,
                                        onBringToToday: onBringToToday,
                                        onDelete: onDelete
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .task(id: session.snapshotRevision) { session.didDisplayInbox() }
        .onDisappear { session.endPresentation() }
        .padding(22)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 360, idealHeight: 480)
        .background(AppTheme.panel)
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
                onCompleteAll(pending.taskIDs)
            }
            Button("취소", role: .cancel) {}
        } message: { pending in
            Text(
                "\(pending.upcomingReminderCount)개의 작업에 예정된 알림이 있습니다. " +
                    "모두 완료하면 해당 알림이 중지되며 설정 기록은 계속 유지됩니다."
            )
        }
        .persistenceFailureAlert(message: $failureMessage)
    }

    private func requestCompleteAll() {
        let pending = PendingDesktopCarryoverCompletion(
            taskIDs: tasks.map(\.id),
            upcomingReminderCount: TaskReminderRules.upcomingReminderCount(
                in: tasks,
                now: Date()
            )
        )
        if pending.upcomingReminderCount > 0 {
            pendingCompletion = pending
        } else {
            onCompleteAll(pending.taskIDs)
        }
    }
}

struct EmptySheetState: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(18)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

struct CarryoverTaskRow: View {
    var task: Task
    var onBringToToday: (Task) -> Void
    var onDelete: (Task) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text(task.plannedDayKey)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Button {
                onBringToToday(task)
            } label: {
                Label("오늘로", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(PlanBaseButtonStyle(.primary))
            .accessibilityLabel("\(task.title) 오늘로 이월")

            Button(role: .destructive) {
                onDelete(task)
            } label: {
                Image(systemName: "trash")
                    .frame(width: PlanBaseControlMetrics.minimumTargetSize,
                           height: PlanBaseControlMetrics.minimumTargetSize)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppTheme.secondaryText)
            .accessibilityLabel("\(task.title) 작업 삭제")
        }
        .padding(10)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
    }
}
