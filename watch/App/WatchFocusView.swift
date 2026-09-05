#if os(watchOS)
import Foundation
import PlanBaseCore
import SwiftData
import SwiftUI
import UserNotifications
import WatchKit

struct WatchFocusDestination: Hashable {
    let taskID: UUID?
}

struct WatchFocusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let initialTaskID: UUID?

    @State private var taskTitle: String?
    @State private var focusMinutes = FocusTimerRules.defaultFocusSeconds / 60
    @State private var estimatedMinutes: Int?
    @State private var hasAppliedEstimate = false
    @State private var snapshot: FocusActiveSessionSnapshot?
    @State private var completion: WatchFocusCompletion?
    @State private var errorMessage: String?
    @State private var isMutating = false
    @State private var visibleFocusSessionID: UUID?

    var body: some View {
        Group {
            if let snapshot {
                activeView(snapshot)
            } else if let completion {
                completionView(completion)
            } else {
                setupView
            }
        }
        .navigationTitle(snapshot?.phase == .breakTime ? "휴식" : "집중")
        .task {
            load()
        }
        .onChange(of: snapshot?.sessionID) { _, _ in
            updatePresentationVisibility()
        }
        .onChange(of: completion?.sessionID) { _, _ in
            updatePresentationVisibility()
        }
        .onDisappear(perform: clearPresentationVisibility)
        .onReceive(NotificationCenter.default.publisher(
            for: FocusActiveSessionStore.didChangeNotification
        )) { _ in
            reloadSnapshot()
        }
        .alert("집중 모드 오류", isPresented: Binding(
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
            VStack(spacing: 12) {
                Image(systemName: "timer.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)

                Text(taskTitle ?? "작업을 불러오는 중")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .privacySensitive()

                Stepper(
                    value: $focusMinutes,
                    in: (FocusTimerRules.minimumFocusSeconds / 60)...(FocusTimerRules.maximumFocusSeconds / 60)
                ) {
                    Text("\(focusMinutes)분")
                        .font(.title3.monospacedDigit().weight(.semibold))
                }
                .accessibilityLabel("집중 시간")
                .accessibilityValue("\(focusMinutes)분")

                if let estimatedMinutes, estimatedMinutes > 0 {
                    Text("작업 예상 \(estimatedMinutes)분")
                        .font(.caption2).foregroundStyle(.secondary)
                    if estimatedMinutes < 5 || estimatedMinutes > 120 {
                        Text("집중 시간은 5~120분으로 설정해요.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Button(action: beginFocus) {
                    Label("집중 시작", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(taskTitle == nil || isMutating)
            }
            .padding(.horizontal, 4)
        }
    }

    private func activeView(_ active: FocusActiveSessionSnapshot) -> some View {
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

            ScrollView {
                VStack(spacing: 12) {
                    Text(active.phase == .focus ? "FOCUS" : "BREAK")
                        .font(.caption2.weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(.blue)

                    Text(active.taskTitleSnapshot)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .privacySensitive()

                    ZStack {
                        Circle()
                            .stroke(.secondary.opacity(0.25), lineWidth: 9)
                        Circle()
                            .trim(from: 0, to: min(1, max(0, progress)))
                            .stroke(
                                active.phase == .focus ? Color.blue : Color.green,
                                style: StrokeStyle(lineWidth: 9, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Text(Self.clock(remaining))
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .minimumScaleFactor(0.7)
                            Text(active.runState == .paused ? "일시정지" : "진행 중")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 116, height: 116)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(active.phase == .focus ? "집중 타이머" : "휴식 타이머")
                    .accessibilityValue(
                        "\(Self.clock(remaining)), " +
                            (active.runState == .paused ? "일시정지" : "진행 중")
                    )
                    .onChange(of: remaining) { _, value in
                        if value <= 0 {
                            reconcile(playHaptic: true)
                        }
                    }

                    Button {
                        togglePause(active)
                    } label: {
                        Label(
                            active.runState == .paused ? "계속" : "일시정지",
                            systemImage: active.runState == .paused
                                ? "play.fill"
                                : "pause.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isMutating)

                    Button(role: .destructive) {
                        stop(active)
                    } label: {
                        Label(
                            active.phase == .focus ? "집중 종료" : "휴식 건너뛰기",
                            systemImage: "stop.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isMutating)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func completionView(_ completed: WatchFocusCompletion) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: completed.kind == .focus
                    ? "checkmark.circle.fill"
                    : "cup.and.saucer.fill")
                    .font(.largeTitle)
                    .foregroundStyle(completed.kind == .focus ? .green : .blue)

                Text(completionTitle(completed))
                    .font(.headline)

                Text(completed.title)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .privacySensitive()

                Text(completionSubtitle(completed))
                    .font(.title3.monospacedDigit().weight(.semibold))

                if completed.kind == .focus {
                    Button {
                        beginBreak(completed)
                    } label: {
                        Label("\(completed.breakMinutes)분 휴식", systemImage: "cup.and.saucer.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isMutating)

                    Button {
                        beginAgain(completed)
                    } label: {
                        Label("계속 집중", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isMutating)
                } else {
                    Button {
                        beginAgain(completed)
                    } label: {
                        Label("집중 시작", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isMutating)

                    Button {
                        extendBreak(completed)
                    } label: {
                        Label("5분 더 쉬기", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isMutating)
                }

                Button("완료") {
                    try? FocusNotificationActionTokenStore.clear()
                    dismiss()
                }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    @MainActor
    private func load() {
        do {
            snapshot = try FocusSessionService.activeSnapshot()
            if snapshot == nil {
                restoreNotificationCompletionIfNeeded()
                try loadTask()
            } else {
                reconcile(playHaptic: false)
            }
        } catch {
            present(error)
        }
    }

    @MainActor
    private func loadTask() throws {
        guard let initialTaskID else {
            taskTitle = nil
            return
        }
        let candidates = try modelContext.fetch(
            BoundedQueryService.taskCandidatesDescriptor(id: initialTaskID)
        )
        guard let task = BoundedQueryService.representativeTask(from: candidates),
              task.archivedAt == nil,
              TaskStatus(rawValue: task.status) != .done else {
            taskTitle = nil
            throw FocusSessionServiceError.taskUnavailable
        }
        taskTitle = task.title
        estimatedMinutes = task.estimatedMinutes
        if !hasAppliedEstimate {
            focusMinutes = FocusTimerRules.suggestedFocusMinutes(estimatedMinutes: task.estimatedMinutes)
            hasAppliedEstimate = true
        }
    }

    @MainActor
    private func beginFocus() {
        guard let initialTaskID else { return }
        performMutation {
            snapshot = try FocusSessionService.beginFocus(
                taskID: initialTaskID,
                focusSeconds: focusMinutes * 60,
                in: modelContext
            )
            completion = nil
            try? FocusNotificationActionTokenStore.clear()
            WKInterfaceDevice.current().play(.start)
            syncPlatform(requestAuthorizationIfNeeded: true)
        }
    }

    @MainActor
    private func togglePause(_ active: FocusActiveSessionSnapshot) {
        performMutation {
            if active.runState == .paused {
                snapshot = try FocusSessionService.resume(
                    expectedSessionID: active.sessionID,
                    expectedRevision: active.revision
                )
            } else {
                snapshot = try FocusSessionService.pause(
                    expectedSessionID: active.sessionID,
                    expectedRevision: active.revision
                )
            }
            WKInterfaceDevice.current().play(.click)
            syncPlatform()
        }
    }

    @MainActor
    private func stop(_ active: FocusActiveSessionSnapshot) {
        performMutation {
            if active.phase == .breakTime {
                try FocusSessionService.endBreak(
                    expectedSessionID: active.sessionID,
                    expectedRevision: active.revision
                )
                snapshot = nil
                completion = nil
                WKInterfaceDevice.current().play(.stop)
                syncPlatform()
                dismiss()
                return
            }
            let record = try FocusSessionService.endFocus(
                outcome: .stopped,
                expectedSessionID: active.sessionID,
                expectedRevision: active.revision,
                in: modelContext
            )
            showCompletion(record, source: active, fallbackOutcome: .stopped)
            WKInterfaceDevice.current().play(.stop)
            syncPlatform()
        }
    }

    @MainActor
    private func reconcile(playHaptic: Bool) {
        let source = snapshot
        do {
            switch try FocusSessionService.reconcile(in: modelContext) {
            case .unchanged(let active):
                snapshot = active
            case .focusEnded(let record):
                if let source {
                    showCompletion(
                        record,
                        source: source,
                        fallbackOutcome: .completed
                    )
                } else {
                    snapshot = nil
                }
                if playHaptic { WKInterfaceDevice.current().play(.notification) }
                syncPlatform()
            case .breakEnded:
                snapshot = nil
                if let source {
                    completion = WatchFocusCompletion(
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
                if playHaptic { WKInterfaceDevice.current().play(.notification) }
                syncPlatform()
            case .noActiveSession:
                snapshot = nil
            }
        } catch {
            present(error)
            reloadSnapshot()
        }
    }

    @MainActor
    private func beginBreak(_ completed: WatchFocusCompletion) {
        performMutation {
            snapshot = try FocusSessionService.beginBreak(
                taskID: completed.taskID,
                taskTitle: completed.title,
                focusSeconds: completed.focusMinutes * 60,
                breakSeconds: completed.breakMinutes * 60
            )
            completion = nil
            try? FocusNotificationActionTokenStore.clear()
            WKInterfaceDevice.current().play(.start)
            syncPlatform()
        }
    }

    @MainActor
    private func beginAgain(_ completed: WatchFocusCompletion) {
        performMutation {
            snapshot = try FocusSessionService.beginFocus(
                taskID: completed.taskID,
                focusSeconds: completed.focusMinutes * 60,
                breakSeconds: completed.breakMinutes * 60,
                in: modelContext
            )
            completion = nil
            try? FocusNotificationActionTokenStore.clear()
            WKInterfaceDevice.current().play(.start)
            syncPlatform()
        }
    }

    @MainActor
    private func extendBreak(_ completed: WatchFocusCompletion) {
        performMutation {
            snapshot = try FocusSessionService.beginBreak(
                taskID: completed.taskID,
                taskTitle: completed.title,
                focusSeconds: completed.focusMinutes * 60,
                breakSeconds: FocusNotificationRules.extensionBreakSeconds
            )
            completion = nil
            try? FocusNotificationActionTokenStore.clear()
            WKInterfaceDevice.current().play(.start)
            syncPlatform()
        }
    }

    private func showCompletion(
        _ record: FocusSession?,
        source: FocusActiveSessionSnapshot,
        fallbackOutcome: FocusSessionOutcome
    ) {
        snapshot = nil
        completion = WatchFocusCompletion(
            sessionID: source.sessionID,
            kind: .focus,
            taskID: source.taskID,
            title: source.taskTitleSnapshot,
            focusedSeconds: record?.focusedDurationSeconds
                ?? Int(FocusTimerRules.focusedDurationSeconds(for: source).rounded(.down)),
            focusMinutes: source.plannedFocusSeconds / 60,
            breakMinutes: source.plannedBreakSeconds / 60,
            outcome: record.flatMap { FocusSessionOutcome(rawValue: $0.outcomeRawValue) }
                ?? fallbackOutcome
        )
    }

    @MainActor
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

            var focusedSeconds = 0
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
            }

            completion = WatchFocusCompletion(
                sessionID: token.sessionID,
                kind: token.phase == .focus ? .focus : .breakTime,
                taskID: token.taskID,
                title: token.taskTitleSnapshot,
                focusedSeconds: focusedSeconds,
                focusMinutes: token.plannedFocusSeconds / 60,
                breakMinutes: token.plannedBreakSeconds / 60,
                outcome: .completed
            )
        } catch {
            present(error)
        }
    }

    private func completionTitle(_ completed: WatchFocusCompletion) -> String {
        if completed.kind == .breakTime { return "휴식 완료" }
        return completed.outcome == .completed ? "집중 완료" : "집중 기록 저장됨"
    }

    private func completionSubtitle(_ completed: WatchFocusCompletion) -> String {
        if completed.kind == .breakTime { return "다시 집중할 시간이에요" }
        return "\(Self.duration(completed.focusedSeconds)) 집중"
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

    @MainActor
    private func performMutation(_ operation: () throws -> Void) {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try operation()
        } catch {
            WKInterfaceDevice.current().play(.failure)
            present(error)
        }
    }

    private func syncPlatform(requestAuthorizationIfNeeded: Bool = false) {
        Swift.Task { @MainActor in
            await WatchFocusNotificationScheduler.shared.reconcile(
                requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
            )
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)초" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)분" : "\(minutes)분 \(remainder)초"
    }
}

private struct WatchFocusCompletion {
    let sessionID: UUID
    let kind: WatchFocusCompletionKind
    let taskID: UUID
    let title: String
    let focusedSeconds: Int
    let focusMinutes: Int
    let breakMinutes: Int
    let outcome: FocusSessionOutcome
}

private enum WatchFocusCompletionKind {
    case focus
    case breakTime
}

@MainActor
final class WatchFocusNotificationScheduler {
    static let shared = WatchFocusNotificationScheduler()

    private static let identifierPrefix = "planbase.focus.watch."
    private let center = UNUserNotificationCenter.current()
    private var isReconciling = false
    private var needsAnotherPass = false

    nonisolated static func registerCategories(
        center: UNUserNotificationCenter = .current()
    ) {
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: FocusNotificationRules.focusEndedCategoryIdentifier,
                actions: [
                    UNNotificationAction(
                        identifier: FocusNotificationRules.startBreakActionIdentifier,
                        title: "휴식 시작"
                    ),
                    UNNotificationAction(
                        identifier: FocusNotificationRules.continueFocusActionIdentifier,
                        title: "계속 집중"
                    )
                ],
                intentIdentifiers: [],
                options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: FocusNotificationRules.breakEndedCategoryIdentifier,
                actions: [
                    UNNotificationAction(
                        identifier: FocusNotificationRules.startFocusActionIdentifier,
                        title: "집중 시작"
                    ),
                    UNNotificationAction(
                        identifier: FocusNotificationRules.extendBreakActionIdentifier,
                        title: "5분 더 쉬기"
                    )
                ],
                intentIdentifiers: [],
                options: [.customDismissAction]
            )
        ])
    }

    func reconcile(
        now: Date = Date(),
        requestAuthorizationIfNeeded: Bool = false
    ) async {
        if isReconciling {
            needsAnotherPass = true
            return
        }
        isReconciling = true
        defer { isReconciling = false }
        repeat {
            needsAnotherPass = false
            await reconcileOnce(
                now: now,
                requestAuthorizationIfNeeded: requestAuthorizationIfNeeded
            )
        } while needsAnotherPass
    }

    func removeDeliveredNotification(identifier: String) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func reconcileOnce(
        now: Date,
        requestAuthorizationIfNeeded: Bool
    ) async {
        do {
            let snapshot = try FocusSessionService.activeSnapshot()
            var settings = await center.notificationSettings()
            if snapshot != nil,
               requestAuthorizationIfNeeded,
               settings.authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
                settings = await center.notificationSettings()
            }

            let pending = await center.pendingNotificationRequests()
            let ownedIDs = pending.map(\.identifier).filter(Self.isManaged)
            let delivered = await center.deliveredNotifications()
            let ownedDeliveredIDs = delivered.map(\.request.identifier).filter(Self.isManaged)
            let storedToken = try? FocusNotificationActionTokenStore.read()

            if let storedToken,
               !FocusNotificationRules.isActionable(storedToken, now: now),
               now > storedToken.expiresAt {
                try? FocusNotificationActionTokenStore.clear()
            }
            if let storedToken,
               FocusNotificationRules.isActionable(storedToken, now: now),
               snapshot.map({ FocusNotificationRules.matches(storedToken, snapshot: $0) }) != false {
                if !ownedIDs.isEmpty {
                    center.removePendingNotificationRequests(withIdentifiers: ownedIDs)
                }
                let staleDelivered = ownedDeliveredIDs.filter {
                    $0 != storedToken.requestIdentifier
                }
                if !staleDelivered.isEmpty {
                    center.removeDeliveredNotifications(withIdentifiers: staleDelivered)
                }
                return
            }

            guard [.authorized, .provisional].contains(settings.authorizationStatus),
                  let snapshot,
                  snapshot.runState == .running,
                  let deadline = snapshot.deadline,
                  deadline > now else {
                if !ownedIDs.isEmpty {
                    center.removePendingNotificationRequests(withIdentifiers: ownedIDs)
                }
                if !ownedDeliveredIDs.isEmpty {
                    center.removeDeliveredNotifications(withIdentifiers: ownedDeliveredIDs)
                }
                try? FocusNotificationActionTokenStore.clear()
                return
            }

            let desiredID = try FocusNotificationRules.requestIdentifier(
                namespace: Self.identifierPrefix,
                snapshot: snapshot
            )
            let token: FocusNotificationActionToken
            if let storedToken,
               storedToken.requestIdentifier == desiredID,
               FocusNotificationRules.matches(storedToken, snapshot: snapshot) {
                token = storedToken
            } else {
                token = try FocusNotificationRules.makeToken(
                    snapshot: snapshot,
                    requestIdentifier: desiredID
                )
            }
            let staleIDs = ownedIDs.filter { $0 != desiredID }
            if !staleIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: staleIDs)
            }
            let staleDeliveredIDs = ownedDeliveredIDs.filter { $0 != desiredID }
            if !staleDeliveredIDs.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: staleDeliveredIDs)
            }
            guard !pending.contains(where: { request in
                request.identifier == desiredID &&
                    (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                        == deadline
            }) else {
                try FocusNotificationActionTokenStore.write(token)
                return
            }

            let content = UNMutableNotificationContent()
            content.title = FocusNotificationRules.title(for: token)
            content.body = FocusNotificationRules.body(for: token)
            content.sound = .default
            content.categoryIdentifier = FocusNotificationRules.categoryIdentifier(
                for: snapshot.phase ?? .focus
            )
            content.userInfo = Self.userInfo(for: token)

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            var components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: deadline
            )
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            do {
                try FocusNotificationActionTokenStore.write(token)
                try await center.add(UNNotificationRequest(
                    identifier: desiredID,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(
                        dateMatching: components,
                        repeats: false
                    )
                ))
            } catch {
                if (try? FocusNotificationActionTokenStore.read()?.tokenID) == token.tokenID {
                    try? FocusNotificationActionTokenStore.clear()
                }
                throw error
            }
        } catch {
            print("Watch Focus notification reconciliation failed: \(error)")
        }
    }

    private nonisolated static func userInfo(
        for token: FocusNotificationActionToken
    ) -> [AnyHashable: Any] {
        [
            FocusNotificationRules.routeKindKey: FocusNotificationRules.routeKindValue,
            FocusNotificationRules.tokenIDKey: token.tokenID.uuidString,
            FocusNotificationRules.sessionIDKey: token.sessionID.uuidString,
            FocusNotificationRules.revisionKey: token.revision,
            FocusNotificationRules.phaseKey: token.phaseRawValue,
            FocusNotificationRules.deadlineKey: token.deadline.timeIntervalSince1970
        ]
    }

    private static func isManaged(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }
}
#endif
