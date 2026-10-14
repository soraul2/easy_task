#if os(iOS)
import Combine
import Foundation
import PlanBaseCore
import SwiftData
import UIKit
import WatchConnectivity

@MainActor
final class WatchCompanionBridge: NSObject, WCSessionDelegate {
    static let shared = WatchCompanionBridge()
    private var container: ModelContainer?
    private var appContext: ModelContext?
    private var service: WatchCompanionService?
    private var subscriptions: Set<AnyCancellable> = []
    private var refreshTask: Swift.Task<Void, Never>?
    private var hasCompatibilityClient = UserDefaults.standard.bool(forKey: "PlanBaseWatchCompanionClient")

    func install(container: ModelContainer, context: ModelContext? = nil) {
        guard WCSession.isSupported(), !PlanBaseLaunchEnvironment.isUITesting else { return }
        self.container = container
        appContext = context ?? container.mainContext
        do {
            let url = URL.applicationSupportDirectory.appendingPathComponent("WatchCompanion/phone-journal-v1.json")
            service = try WatchCompanionService(journalURL: url)
        } catch {
            // No acknowledgement is sent when the durable journal cannot be opened.
            print("PlanBase Watch 연결 저장소: \(error.localizedDescription)")
            return
        }
        guard subscriptions.isEmpty else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        for name in [PersistenceCommandService.dataChangedNotification,
                     CloudKitSyncService.eventChangedNotification, .NSCalendarDayChanged,
                     UIApplication.didBecomeActiveNotification] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.scheduleSnapshot() }
                .store(in: &subscriptions)
        }
    }

    private func scheduleSnapshot() {
        guard hasCompatibilityClient else { return }
        refreshTask?.cancel()
        refreshTask = Swift.Task { @MainActor [weak self] in
            do { try await Swift.Task.sleep(for: .milliseconds(700)) } catch { return }
            self?.publishSnapshot()
        }
    }

    private func publishSnapshot() {
        guard let container, let service, WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        do {
            let response = WatchCompanionResponse(snapshot: try service.snapshot(in: ModelContext(container)))
            let data = try WatchCompanionProtocol.encode(response)
            try WCSession.default.updateApplicationContext([WatchCompanionProtocol.payloadKey: data])
        } catch {
            print("PlanBase Watch 목록 전송: \(error.localizedDescription)")
        }
    }

    private func receive(_ data: Data, reply: Reply? = nil) {
        guard let container, let service, let appContext else { reply?.send(["retry": true]); return }
        hasCompatibilityClient = true
        UserDefaults.standard.set(true, forKey: "PlanBaseWatchCompanionClient")
        do {
            let request = try WatchCompanionProtocol.decode(WatchCompanionRequest.self, from: data)
            let response = try service.respond(to: request, in: ModelContext(container))
            let payload = [WatchCompanionProtocol.payloadKey: try WatchCompanionProtocol.encode(response)]
            if let reply { reply.send(payload) }
            // Background replies carry receipts; applicationContext is reserved for the
            // replaceable snapshot, so later updates cannot overwrite an acknowledgement.
            else { WCSession.default.transferUserInfo(payload) }
            publishSnapshot()
            Swift.Task { @MainActor in
                await TaskNotificationScheduler.shared.reconcile(context: appContext)
                await TaskLiveActivityCoordinator.shared.reconcile(context: appContext)
            }
        } catch {
            reply?.send(["retry": true])
            print("PlanBase Watch 변경 수신: \(error.localizedDescription)")
        }
    }

    private struct Reply: @unchecked Sendable { let send: ([String: Any]) -> Void }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        guard activationState == .activated else { return }
        Swift.Task { @MainActor [weak self] in self?.scheduleSnapshot() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Swift.Task { @MainActor [weak self] in self?.scheduleSnapshot() }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let data = message[WatchCompanionProtocol.payloadKey] as? Data else {
            replyHandler(["retry": true]); return
        }
        let reply = Reply(send: replyHandler)
        Swift.Task { @MainActor [weak self] in self?.receive(data, reply: reply) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[WatchCompanionProtocol.payloadKey] as? Data else { return }
        Swift.Task { @MainActor [weak self] in self?.receive(data) }
    }
}
#endif
