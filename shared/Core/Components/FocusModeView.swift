import Combine
import SwiftData
import SwiftUI

@MainActor
public enum FocusModeSelectionRequest {
    public nonisolated static let didRequestNotification = Notification.Name(
        "PlanBaseFocusModeSelectionRequested"
    )
    private static var pendingTaskID: UUID?

    public static func post(taskID: UUID) {
        pendingTaskID = taskID
        NotificationCenter.default.post(
            name: didRequestNotification,
            object: taskID
        )
    }

    public static func consume() -> UUID? {
        defer { pendingTaskID = nil }
        return pendingTaskID
    }
}

public struct FocusModeLauncher: View {
    private let action: () -> Void
    @State private var snapshot: FocusActiveSessionSnapshot?

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Group {
            if let snapshot {
                Button(action: action) {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        HStack(spacing: 7) {
                            Image(systemName: "timer.circle.fill")
                            Text(FocusModeFormatting.clock(
                                FocusTimerRules.remainingSeconds(
                                    for: snapshot,
                                    now: timeline.date
                                )
                            ))
                            .monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 13)
                        .frame(minHeight: 40)
                        .foregroundStyle(AppTheme.primaryText)
                        .background(AppTheme.floatingBar, in: Capsule())
                        .overlay {
                            Capsule().stroke(AppTheme.event.opacity(0.55), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("진행 중인 집중 모드 열기")
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(
            for: FocusActiveSessionStore.didChangeNotification
        )) { _ in
            reload()
        }
    }

    private func reload() {
        snapshot = try? FocusSessionService.activeSnapshot()
    }
}

public struct FocusModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var snapshot: FocusActiveSessionSnapshot?
    @State private var candidates: [FocusTaskCandidate] = []
    @State private var selectedTaskID: UUID?
    @State private var focusMinutes = FocusTimerRules.defaultFocusSeconds / 60
    @State private var breakMinutes = FocusTimerRules.defaultBreakSeconds / 60
    @State private var completion: FocusCompletionPresentation?
    @State private var todaySummary = FocusDaySummary()
    @State private var errorMessage: String?
    @State private var visibleFocusSessionID: UUID?

    public init(initialTaskID: UUID? = nil) {
        _selectedTaskID = State(initialValue: initialTaskID)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                Group {
                    if let snapshot {
                        timerView(snapshot)
                    } else if let completion {
                        completionView(completion)
                    } else {
                        setupView
                    }
                }
                .frame(maxWidth: 620)
                .padding(24)
            }
            .foregroundStyle(AppTheme.primaryText)
            .navigationTitle("집중 모드")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기", action: close)
                }
            }
        }
        .task {
            load()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: FocusActiveSessionStore.didChangeNotification
        )) { _ in
            reloadSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: PersistenceCommandService.dataChangedNotification
        )) { _ in
            reconcile()
            loadCandidates()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: FocusModeSelectionRequest.didRequestNotification
        )) { notification in
            guard let taskID = notification.object as? UUID else { return }
            _ = FocusModeSelectionRequest.consume()
            completion = nil
            selectedTaskID = taskID
            loadCandidates()
        }
        .onChange(of: snapshot?.sessionID) {
            updatePresentationVisibility()
        }
        .onChange(of: completion?.sessionID) {
            updatePresentationVisibility()
        }
        .onDisappear(perform: clearPresentationVisibility)
        .alert("집중 모드를 실행할 수 없습니다", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "알 수 없는 오류")
        }
    }

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("지금 한 가지에만 집중해요", systemImage: "scope")
                        .font(.title2.bold())
                    Text("작업을 고르면 진행 중 상태로 바뀌고 25분 타이머가 시작됩니다.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Label(
                    "오늘 \(todaySummary.sessionCount)회 · " +
                        "\(FocusModeFormatting.minutes(todaySummary.focusedDurationSeconds)) 집중",
                    systemImage: "chart.bar.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 10) {
                    Text("작업")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)

                    if candidates.isEmpty {
                        ContentUnavailableView(
                            "집중할 작업이 없어요",
                            systemImage: "checkmark.circle",
                            description: Text("보드에서 할 일을 만든 뒤 다시 열어 주세요.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        ForEach(candidates) { candidate in
                            Button {
                                selectedTaskID = candidate.id
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: candidate.status == .doing
                                        ? "play.circle.fill"
                                        : "circle")
                                        .foregroundStyle(candidate.status == .doing
                                            ? AppTheme.event
                                            : AppTheme.secondaryText)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(candidate.title)
                                            .font(.body.weight(.semibold))
                                            .lineLimit(2)
                                        Text(candidate.status == .doing ? "진행 중" : candidate.dayKey)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                    }
                                    Spacer()
                                    Image(systemName: selectedTaskID == candidate.id
                                        ? "checkmark.circle.fill"
                                        : "circle")
                                        .foregroundStyle(AppTheme.event)
                                }
                                .padding(14)
                                .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(
                                            selectedTaskID == candidate.id
                                                ? AppTheme.event
                                                : AppTheme.border,
                                            lineWidth: selectedTaskID == candidate.id ? 2 : 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 12) {
                    durationControl(
                        title: "집중",
                        selection: $focusMinutes,
                        range: (FocusTimerRules.minimumFocusSeconds / 60)...(FocusTimerRules.maximumFocusSeconds / 60)
                    )
                    durationControl(
                        title: "휴식",
                        selection: $breakMinutes,
                        range: (FocusTimerRules.minimumBreakSeconds / 60)...(FocusTimerRules.maximumBreakSeconds / 60)
                    )
                }

                HStack(spacing: 8) {
                    Text("빠른 설정")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    ForEach([15, 25, 50], id: \.self) { minutes in
                        Button("\(minutes)분") { focusMinutes = minutes }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                Button(action: beginFocus) {
                    Label("집중 시작", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.event)
                .disabled(selectedTaskID == nil)
            }
        }
    }

    private func timerView(_ active: FocusActiveSessionSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = FocusTimerRules.remainingSeconds(
                for: active,
                now: timeline.date
            )
            let planned = active.phase == .focus
                ? active.plannedFocusSeconds
                : active.plannedBreakSeconds
            let progress = planned > 0
                ? 1 - remaining / TimeInterval(planned)
                : 0

            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text(active.phase == .focus ? "FOCUS" : "BREAK")
                        .font(.caption.weight(.bold))
                        .tracking(2.4)
                        .foregroundStyle(AppTheme.event)
                    Text(active.taskTitleSnapshot)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }

                ZStack {
                    Circle()
                        .stroke(AppTheme.border.opacity(0.65), lineWidth: 16)
                    Circle()
                        .trim(from: 0, to: min(1, max(0, progress)))
                        .stroke(
                            AppTheme.event,
                            style: StrokeStyle(lineWidth: 16, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
                    VStack(spacing: 7) {
                        Text(FocusModeFormatting.clock(remaining))
                            .font(.system(size: 54, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                        Text(active.runState == .paused ? "일시정지" : "진행 중")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .frame(width: 260, height: 260)
                .onChange(of: remaining) { _, value in
                    if value <= 0 { reconcile() }
                }

                HStack(spacing: 12) {
                    Button {
                        togglePause(active)
                    } label: {
                        Label(
                            active.runState == .paused ? "계속" : "일시정지",
                            systemImage: active.runState == .paused ? "play.fill" : "pause.fill"
                        )
                        .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.event)

                    Button(role: .destructive) {
                        end(active)
                    } label: {
                        Label(active.phase == .focus ? "종료" : "건너뛰기", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                }

                if active.phase == .focus {
                    Button {
                        completeTask(active)
                    } label: {
                        Label("작업도 완료하기", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func completionView(_ completed: FocusCompletionPresentation) -> some View {
        VStack(spacing: 22) {
            Image(systemName: completed.kind == .focus ? "checkmark.circle.fill" : "cup.and.saucer.fill")
                .font(.system(size: 66))
                .foregroundStyle(completed.kind == .focus ? AppTheme.done : AppTheme.event)
            VStack(spacing: 7) {
                Text(completionTitle(completed))
                    .font(.title.bold())
                Text(completed.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(completionSubtitle(completed))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if completed.kind == .focus {
                Button {
                    beginBreak(completed)
                } label: {
                    Label("\(completed.breakMinutes)분 휴식 시작", systemImage: "cup.and.saucer.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.event)

                Button {
                    beginAgain(completed)
                } label: {
                    Label("계속 집중", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    beginAgain(completed)
                } label: {
                    Label("집중 시작", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.event)

                Button {
                    extendBreak(completed)
                } label: {
                    Label("5분 더 쉬기", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }

            Button("다른 작업 선택") {
                selectAnotherTask()
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func durationControl(
        title: String,
        selection: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)

            HStack(spacing: 5) {
                Button {
                    selection.wrappedValue = max(
                        range.lowerBound,
                        selection.wrappedValue - 1
                    )
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .disabled(selection.wrappedValue <= range.lowerBound)

                Text("\(selection.wrappedValue)분")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .frame(maxWidth: .infinity)

                Button {
                    selection.wrappedValue = min(
                        range.upperBound,
                        selection.wrappedValue + 1
                    )
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .disabled(selection.wrappedValue >= range.upperBound)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private func load() {
        if let requestedTaskID = FocusModeSelectionRequest.consume() {
            selectedTaskID = requestedTaskID
        }
        reconcile()
        restoreNotificationCompletionIfNeeded()
        loadCandidates()
    }

    @MainActor
    private func loadCandidates() {
        let done = TaskStatus.done.rawValue
        var descriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.supersededAt == nil &&
                    task.archivedAt == nil &&
                    task.status != done
            },
            sortBy: [
                SortDescriptor(\Task.updatedAt, order: .reverse),
                SortDescriptor(\Task.instanceID, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 100
        do {
            let tasks = try modelContext.fetch(descriptor)
            var seen: Set<UUID> = []
            candidates = tasks.compactMap { task in
                guard seen.insert(task.id).inserted else { return nil }
                return FocusTaskCandidate(
                    id: task.id,
                    title: task.title,
                    dayKey: task.plannedDayKey,
                    status: TaskStatus(rawValue: task.status) ?? .todo,
                    updatedAt: task.updatedAt
                )
            }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status { return lhs.status == .doing }
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            if selectedTaskID.map({ selectedID in
                candidates.contains(where: { $0.id == selectedID })
            }) != true {
                selectedTaskID = candidates.first?.id
            }
            todaySummary = try FocusSessionQueryService.summary(in: modelContext)
        } catch {
            present(error)
        }
    }

    @MainActor
    private func beginFocus() {
        guard let selectedTaskID else { return }
        do {
            completion = nil
            snapshot = try FocusSessionService.beginFocus(
                taskID: selectedTaskID,
                focusSeconds: focusMinutes * 60,
                breakSeconds: breakMinutes * 60,
                in: modelContext
            )
        } catch {
            present(error)
        }
    }

    private func togglePause(_ active: FocusActiveSessionSnapshot) {
        do {
            snapshot = if active.runState == .paused {
                try FocusSessionService.resume(
                    expectedSessionID: active.sessionID,
                    expectedRevision: active.revision
                )
            } else {
                try FocusSessionService.pause(
                    expectedSessionID: active.sessionID,
                    expectedRevision: active.revision
                )
            }
        } catch {
            present(error)
            reloadSnapshot()
        }
    }

    @MainActor
    private func end(_ active: FocusActiveSessionSnapshot) {
        do {
            if active.phase == .breakTime {
                try FocusActiveSessionStore.clear()
                snapshot = nil
                completion = nil
                return
            }
            let record = try FocusSessionService.endFocus(
                outcome: .stopped,
                expectedSessionID: active.sessionID,
                expectedRevision: active.revision,
                in: modelContext
            )
            showCompletion(record, snapshot: active)
        } catch {
            present(error)
            reloadSnapshot()
        }
    }

    @MainActor
    private func completeTask(_ active: FocusActiveSessionSnapshot) {
        do {
            guard let task = try BoundedQueryService.representativeTask(
                from: modelContext.fetch(
                    BoundedQueryService.taskCandidatesDescriptor(id: active.taskID)
                )
            ) else {
                reconcile()
                return
            }
            try PersistenceCommandService.perform(in: modelContext) {
                _ = try TaskLifecycleService.applyStatus(
                    .done,
                    to: task,
                    in: modelContext
                )
            }
            reconcile()
        } catch {
            present(error)
            reloadSnapshot()
        }
    }

    @MainActor
    private func reconcile() {
        do {
            let source = snapshot ?? (try? FocusSessionService.activeSnapshot())
            switch try FocusSessionService.reconcile(in: modelContext) {
            case .unchanged(let value):
                snapshot = value
            case .focusEnded(let record):
                snapshot = nil
                completion = FocusCompletionPresentation(
                    sessionID: record.id,
                    kind: .focus,
                    taskID: record.taskId,
                    title: source?.taskTitleSnapshot ?? "집중 작업",
                    focusedSeconds: record.focusedDurationSeconds,
                    focusMinutes: record.plannedDurationSeconds / 60,
                    breakMinutes: source.map { $0.plannedBreakSeconds / 60 }
                        ?? FocusTimerRules.defaultBreakSeconds / 60,
                    outcome: FocusSessionOutcome(rawValue: record.outcomeRawValue) ?? .interrupted
                )
            case .breakEnded:
                snapshot = nil
                if let source {
                    completion = FocusCompletionPresentation(
                        sessionID: source.sessionID,
                        kind: .breakTime,
                        taskID: source.taskID,
                        title: source.taskTitleSnapshot,
                        focusedSeconds: 0,
                        focusMinutes: source.plannedFocusSeconds / 60,
                        breakMinutes: source.plannedBreakSeconds / 60,
                        outcome: .completed
                    )
                }
            case .noActiveSession:
                snapshot = nil
            }
        } catch {
            present(error)
            reloadSnapshot()
        }
    }

    private func reloadSnapshot() {
        do {
            snapshot = try FocusSessionService.activeSnapshot()
            if snapshot == nil {
                restoreNotificationCompletionIfNeeded()
            }
        } catch {
            present(error)
        }
    }

    private func showCompletion(
        _ record: FocusSession?,
        snapshot source: FocusActiveSessionSnapshot
    ) {
        snapshot = nil
        completion = FocusCompletionPresentation(
            sessionID: source.sessionID,
            kind: .focus,
            taskID: source.taskID,
            title: source.taskTitleSnapshot,
            focusedSeconds: record?.focusedDurationSeconds ?? 0,
            focusMinutes: source.plannedFocusSeconds / 60,
            breakMinutes: source.plannedBreakSeconds / 60,
            outcome: record.flatMap { FocusSessionOutcome(rawValue: $0.outcomeRawValue) }
                ?? .stopped
        )
    }

    private func beginBreak(_ completed: FocusCompletionPresentation) {
        do {
            snapshot = try FocusSessionService.beginBreak(
                taskID: completed.taskID,
                taskTitle: completed.title,
                focusSeconds: completed.focusMinutes * 60,
                breakSeconds: completed.breakMinutes * 60
            )
            completion = nil
            try? FocusNotificationActionTokenStore.clear()
        } catch {
            present(error)
        }
    }

    private func beginAgain(_ completed: FocusCompletionPresentation) {
        do {
            snapshot = try FocusSessionService.beginFocus(
                taskID: completed.taskID,
                focusSeconds: completed.focusMinutes * 60,
                breakSeconds: completed.breakMinutes * 60,
                in: modelContext
            )
            completion = nil
            try? FocusNotificationActionTokenStore.clear()
        } catch {
            present(error)
        }
    }

    private func extendBreak(_ completed: FocusCompletionPresentation) {
        do {
            snapshot = try FocusSessionService.beginBreak(
                taskID: completed.taskID,
                taskTitle: completed.title,
                focusSeconds: completed.focusMinutes * 60,
                breakSeconds: FocusNotificationRules.extensionBreakSeconds
            )
            completion = nil
            try? FocusNotificationActionTokenStore.clear()
        } catch {
            present(error)
        }
    }

    @MainActor
    private func restoreNotificationCompletionIfNeeded(now: Date = Date()) {
        guard snapshot == nil, completion == nil else { return }
        do {
            guard let token = try FocusNotificationActionTokenStore.read() else { return }
            guard FocusNotificationRules.isActionable(token, now: now) else {
                if now > token.expiresAt {
                    try? FocusNotificationActionTokenStore.clear()
                }
                return
            }
            guard try FocusSessionService.activeSnapshot() == nil else { return }

            let focusedSeconds: Int
            let outcome: FocusSessionOutcome
            if token.phase == .focus {
                let id = token.sessionID
                let instanceID = token.instanceID
                let records = try modelContext.fetch(FetchDescriptor<FocusSession>(
                    predicate: #Predicate<FocusSession> { session in
                        session.id == id &&
                            session.instanceID == instanceID &&
                            session.supersededAt == nil
                    }
                ))
                guard let record = records.first(where: {
                    $0.taskId == token.taskID &&
                        $0.endedAt == token.deadline &&
                        $0.outcomeRawValue == FocusSessionOutcome.completed.rawValue
                }) else { return }
                focusedSeconds = record.focusedDurationSeconds
                outcome = .completed
            } else {
                focusedSeconds = 0
                outcome = .completed
            }

            completion = FocusCompletionPresentation(
                sessionID: token.sessionID,
                kind: token.phase == .focus ? .focus : .breakTime,
                taskID: token.taskID,
                title: token.taskTitleSnapshot,
                focusedSeconds: focusedSeconds,
                focusMinutes: token.plannedFocusSeconds / 60,
                breakMinutes: token.plannedBreakSeconds / 60,
                outcome: outcome
            )
        } catch {
            present(error)
        }
    }

    private func completionTitle(_ completed: FocusCompletionPresentation) -> String {
        if completed.kind == .breakTime { return "휴식 완료" }
        return completed.outcome == .completed ? "집중 완료" : "집중 기록 저장됨"
    }

    private func completionSubtitle(_ completed: FocusCompletionPresentation) -> String {
        if completed.kind == .breakTime { return "다시 집중할 준비가 됐나요?" }
        return "\(FocusModeFormatting.minutes(completed.focusedSeconds)) 집중했어요"
    }

    private func selectAnotherTask() {
        try? FocusNotificationActionTokenStore.clear()
        completion = nil
        loadCandidates()
    }

    private func close() {
        if completion != nil {
            try? FocusNotificationActionTokenStore.clear()
        }
        clearPresentationVisibility()
        dismiss()
    }

    private func updatePresentationVisibility() {
        let nextSessionID = snapshot?.sessionID ?? completion?.sessionID
        guard visibleFocusSessionID != nextSessionID else { return }
        if let visibleFocusSessionID {
            FocusPresentationVisibilityStore.shared.hide(sessionID: visibleFocusSessionID)
        }
        visibleFocusSessionID = nextSessionID
        if let nextSessionID {
            FocusPresentationVisibilityStore.shared.show(sessionID: nextSessionID)
        }
    }

    private func clearPresentationVisibility() {
        if let visibleFocusSessionID {
            FocusPresentationVisibilityStore.shared.hide(sessionID: visibleFocusSessionID)
        }
        visibleFocusSessionID = nil
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

private struct FocusTaskCandidate: Identifiable {
    let id: UUID
    let title: String
    let dayKey: String
    let status: TaskStatus
    let updatedAt: Date
}

private struct FocusCompletionPresentation {
    let sessionID: UUID
    let kind: FocusCompletionKind
    let taskID: UUID
    let title: String
    let focusedSeconds: Int
    let focusMinutes: Int
    let breakMinutes: Int
    let outcome: FocusSessionOutcome
}

private enum FocusCompletionKind {
    case focus
    case breakTime
}

private enum FocusModeFormatting {
    static func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    static func minutes(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)초" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)분" : "\(minutes)분 \(remainder)초"
    }
}
