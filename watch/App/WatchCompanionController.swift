#if os(watchOS)
import Foundation
import Observation
import PlanBaseCore
import UserNotifications
import WatchConnectivity
import WatchKit
import WidgetKit

@MainActor
@Observable
final class WatchCompanionController: NSObject, WCSessionDelegate {
    static let shared = WatchCompanionController()
    private(set) var state = WatchCompanionState()
    private(set) var issue: String?
    private(set) var isReachable = false
    private(set) var focusPresentationID: UUID?
    private var fileURL: URL?
    private var canWrite = false
    private var activated = false
    private var sending = false
    private var notificationTask: Swift.Task<Void, Never>?
    private let notificationID = WatchCompanionProtocol.focusNotificationID

    override init() {
        super.init()
        do {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("WatchCompanionUITest-\(ProcessInfo.processInfo.processIdentifier)/state.json")
            } else {
                fileURL = try WatchCompanionStateStore.fileURL()
            }
#else
            fileURL = try WatchCompanionStateStore.fileURL()
#endif
            if let fileURL { state = try WatchCompanionStateStore.read(from: fileURL) }
            canWrite = true
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--watch-companion-fixture") {
                state.snapshot = WatchCompanionSnapshot(phoneID: UUID(), revision: 1, generatedAt: Date(), dayKey: DayKey.today,
                    tasks: [WatchCompanionTask(id: UUID(), title: "오늘 할 일 확인하기", status: "todo", updatedAt: Date(), plannedDayKey: DayKey.today),
                            WatchCompanionTask(id: UUID(), title: "책 읽고 집중 기록 남기기", status: "doing", updatedAt: Date(), plannedDayKey: DayKey.today)])
            }
#endif
        } catch { issue = error.localizedDescription }
    }

    func start() {
        reconcileTimer()
        scheduleNotification()
        publishWidget()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
#endif
        guard !activated, WCSession.isSupported() else { refresh(); return }
        activated = true
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func refresh() {
        reconcileTimer()
        scheduleNotification()
        flush(requestSnapshot: true)
    }

    func openFocusFromNotification() { focusPresentationID = UUID() }

    @discardableResult
    private func update(_ mutation: (inout WatchCompanionState) throws -> Void) -> Bool {
        guard canWrite, let fileURL else { issue = "저장소를 열지 못했습니다. 앱을 다시 열어 주세요."; return false }
        do {
            var next = state
            try mutation(&next)
            try WatchCompanionStateStore.write(next, to: fileURL)
            state = next
            issue = nil
            publishWidget()
            scheduleNotification()
            flush()
            return true
        } catch { issue = error.localizedDescription; return false }
    }

    func addTask(_ title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 500, title.utf8.count <= 2_000 else {
            issue = "작업 제목을 500자 이내로 줄여 주세요."; return false
        }
        guard state.snapshot?.dayKey == DayKey.today else {
            issue = "iPhone에서 오늘 목록을 받아온 뒤 추가해 주세요."; return false
        }
        return update { try $0.enqueue(.addTask(id: UUID(), title: title, dayKey: DayKey.today)) }
    }

    func setStatus(_ task: WatchCompanionTask, status: String, confirmedReminderAt: Date? = nil) {
        guard state.snapshot?.dayKey == DayKey.today else { issue = "오늘 목록을 새로 받아와 주세요."; return }
        guard let current = state.projectedTasks.first(where: { $0.id == task.id }), current.status != status else { return }
        _ = update { next in
            let now = Date()
            try next.enqueue(.setStatus(taskID: current.id, expectedStatus: current.status,
                expectedUpdatedAt: current.updatedAt, status: status, completionDayKey: DayKey.key(for: now),
                confirmedReminderAt: confirmedReminderAt), now: now)
            if status == "done", next.activeFocus?.taskID == task.id {
                try next.finishFocus(outcome: .taskCompleted, now: now)
            }
        }
    }

    func startFocus(_ task: WatchCompanionTask, minutes: Int) {
        guard state.activeFocus == nil, state.snapshot?.dayKey == DayKey.today,
              let current = state.projectedTasks.first(where: { $0.id == task.id && $0.status != "done" }) else { return }
        _ = update { next in
            if current.status == "todo" {
                try next.enqueue(.setStatus(taskID: current.id, expectedStatus: current.status,
                    expectedUpdatedAt: current.updatedAt, status: "doing", completionDayKey: DayKey.today,
                    confirmedReminderAt: nil))
            }
            next.activeFocus = FocusTimerRules.startFocus(taskID: task.id, taskTitle: task.title, focusSeconds: minutes * 60)
            next.completedFocus = nil
        }
    }

    func pauseOrResume() {
        reconcileTimer()
        _ = update { next in
            guard let active = next.activeFocus else { return }
            next.activeFocus = try active.runState == .paused ? FocusTimerRules.resume(active) : FocusTimerRules.pause(active)
        }
    }

    func stopFocus() {
        _ = update { try $0.finishFocus(outcome: .stopped) }
    }

    func startBreak() {
        _ = update { next in
            guard next.activeFocus == nil, let previous = next.completedFocus else { return }
            next.activeFocus = FocusTimerRules.startBreak(taskID: previous.taskID, taskTitle: previous.taskTitleSnapshot,
                focusSeconds: previous.plannedFocusSeconds)
            next.completedFocus = nil
        }
    }

    func reconcileTimer() {
        guard let active = state.activeFocus, FocusTimerRules.hasReachedDeadline(active) else { return }
        if update({ try $0.finishFocus(outcome: .completed) }) { WKInterfaceDevice.current().play(.notification) }
    }

    func dismissFailure() { _ = update { $0.lastFailure = nil; $0.failed = [] } }

    private func receive(_ data: Data) {
        do {
            let response = try WatchCompanionProtocol.decode(WatchCompanionResponse.self, from: data)
            let previousCount = state.pending.count
            // Save acknowledgements before sending the next ordered batch.
            guard canWrite, let fileURL else { return }
            var next = state
            try next.receive(response)
            if let active = next.activeFocus,
               next.projectedTasks.contains(where: { $0.id == active.taskID && $0.status == "done" }) {
                try next.finishFocus(outcome: .taskCompleted)
            }
            try WatchCompanionStateStore.write(next, to: fileURL)
            state = next
            issue = nil
            publishWidget()
            scheduleNotification()
            if state.pending.count != previousCount { flush() }
        } catch { issue = error.localizedDescription }
    }

    private func flush(requestSnapshot: Bool = false) {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
#endif
        let session = WCSession.default
        guard session.activationState == .activated, !sending,
              requestSnapshot || !state.pending.isEmpty else { return }
        isReachable = session.isReachable
        do {
            let request = WatchCompanionRequest(commands: Array(state.pending.prefix(WatchCompanionProtocol.maximumBatchCount)))
            let data = try WatchCompanionProtocol.encode(request)
            if session.isReachable {
                sending = true
                session.sendMessage([WatchCompanionProtocol.payloadKey: data], replyHandler: { [weak self] message in
                    let responseData = message[WatchCompanionProtocol.payloadKey] as? Data
                    Swift.Task { @MainActor in
                        guard let self else { return }
                        self.sending = false
                        if let responseData { self.receive(responseData) }
                        else { self.issue = "iPhone 저장을 기다리고 있어요."; self.enqueueBackground(data) }
                    }
                }, errorHandler: { [weak self] _ in
                    Swift.Task { @MainActor in
                        self?.sending = false
                        self?.enqueueBackground(data)
                    }
                })
            } else { enqueueBackground(data) }
        } catch { issue = error.localizedDescription }
    }

    private func enqueueBackground(_ data: Data) {
        // Preserve order and avoid accumulating duplicate background transfers.
        guard WCSession.default.outstandingUserInfoTransfers.allSatisfy({
            $0.userInfo[WatchCompanionProtocol.payloadKey] == nil
        }) else { return }
        WCSession.default.transferUserInfo([WatchCompanionProtocol.payloadKey: data])
    }

    private func publishWidget() {
        guard let snapshot = state.snapshot else { return }
        let tasks = state.projectedTasks
        func count(_ status: String, total: Int) -> Int {
            max(0, total + tasks.filter { $0.status == status }.count
                - snapshot.tasks.filter { $0.status == status }.count)
        }
        let widget = WatchWidgetSnapshot(generatedAt: Date(), dayKey: snapshot.dayKey,
            todoCount: count("todo", total: snapshot.todoCount),
            doingCount: count("doing", total: snapshot.doingCount),
            doneCount: count("done", total: snapshot.doneCount),
            eventCount: snapshot.eventCount, activeFocus: state.activeFocus)
        do {
            let directory: URL?
#if DEBUG
            directory = ProcessInfo.processInfo.arguments.contains("--ui-testing")
                ? fileURL?.deletingLastPathComponent().appendingPathComponent("Widget") : nil
#else
            directory = nil
#endif
            if try WatchWidgetSnapshotStore.writeIfChanged(widget, directoryURL: directory) {
                WidgetCenter.shared.reloadTimelines(ofKind: WatchWidgetConstants.kind)
            }
        } catch { issue = "위젯에 표시할 목록을 저장하지 못했어요." }
    }

    private func scheduleNotification() {
        notificationTask?.cancel()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        guard let active = state.activeFocus, active.runState == .running,
              let deadline = active.deadline, deadline > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = active.phase == .focus ? "집중 시간이 끝났어요" : "휴식이 끝났어요"
        content.body = active.taskTitleSnapshot
        content.sound = .default
        let request = UNNotificationRequest(identifier: notificationID, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false))
        notificationTask = Swift.Task { @MainActor in
            do {
                if await center.notificationSettings().authorizationStatus == .notDetermined {
                    _ = try await center.requestAuthorization(options: [.alert, .sound])
                }
                guard !Swift.Task.isCancelled, state.activeFocus == active else { return }
                try await center.add(request)
                if state.activeFocus != active { scheduleNotification() }
            } catch { issue = "타이머 알림을 설정하지 못했습니다. Watch 알림 설정을 확인해 주세요." }
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        guard activationState == .activated else { return }
        let data = session.receivedApplicationContext[WatchCompanionProtocol.payloadKey] as? Data
        Swift.Task { @MainActor [weak self] in
            if let data { self?.receive(data) }
            self?.refresh()
        }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Swift.Task { @MainActor [weak self] in self?.isReachable = reachable; self?.refresh() }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[WatchCompanionProtocol.payloadKey] as? Data else { return }
        Swift.Task { @MainActor [weak self] in self?.receive(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchCompanionProtocol.payloadKey] as? Data else { return }
        Swift.Task { @MainActor [weak self] in self?.receive(data) }
    }
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer,
                             error: (any Error)?) {
        guard error == nil, let data = userInfoTransfer.userInfo[WatchCompanionProtocol.payloadKey] as? Data,
              let request = try? WatchCompanionProtocol.decode(WatchCompanionRequest.self, from: data) else { return }
        let sentIDs = Set(request.commands.map(\.id))
        Swift.Task { @MainActor [weak self] in
            guard let self, !self.state.pending.isEmpty,
                  Set(self.state.pending.map(\.id)).isDisjoint(with: sentIDs) else { return }
            self.flush()
        }
    }
}
#endif
