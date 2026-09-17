#if os(iOS)
import AppIntents
import Foundation
import PlanBaseCore
import SwiftData

@MainActor
enum PlanBaseTaskIntentRuntime {
    static func install(modelContainer: ModelContainer) {
        let executor = PlanBaseTaskIntentCommandExecutor(
            modelContainer: modelContainer
        )
        AppDependencyManager.shared.add(
            key: PlanBaseTaskIntentDependency.key,
            dependency: executor
        )
    }
}

@MainActor
private final class PlanBaseTaskIntentCommandExecutor:
    PlanBaseTaskIntentCommandHandling,
    @unchecked Sendable {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func perform(_ command: PlanBaseTaskIntentCommand) async throws {
        let context = modelContainer.mainContext
        let now = Date()

        switch command {
        case .pauseFocus(let sessionID, let revision):
            _ = try FocusSessionService.pause(
                expectedSessionID: sessionID,
                expectedRevision: revision,
                now: now
            )
            await TaskLiveActivityCoordinator.shared.reconcile(
                context: context,
                now: now,
                fromIntent: true,
                explicitStart: false
            )
            return
        case .resumeFocus(let sessionID, let revision):
            _ = try FocusSessionService.resume(
                expectedSessionID: sessionID,
                expectedRevision: revision,
                now: now
            )
            await TaskLiveActivityCoordinator.shared.reconcile(
                context: context,
                now: now,
                fromIntent: true,
                explicitStart: true
            )
            return
        case .stopFocus(let sessionID, let revision):
            if try FocusSessionService.activeSnapshot()?.phase == .breakTime {
                try FocusSessionService.endBreak(
                    expectedSessionID: sessionID,
                    expectedRevision: revision
                )
            } else {
                _ = try FocusSessionService.endFocus(
                    outcome: .stopped,
                    expectedSessionID: sessionID,
                    expectedRevision: revision,
                    now: now,
                    in: context
                )
            }
            await TaskLiveActivityCoordinator.shared.reconcile(
                context: context,
                now: now,
                fromIntent: true,
                explicitStart: false
            )
            return
        case .start, .startSelected, .complete, .advance:
            break
        }

        let coordinator = TaskLiveActivityCoordinator.shared
        let store = coordinator.selectionStore
        var explicitStart = false
        do {
            guard try FocusSessionService.activeSnapshot() == nil else {
                throw PlanBaseTaskIntentRuntimeError.staleTask
            }
            switch command {
            case .start(let id):
                try TaskLiveActivityCommandService.start(taskID: id, token: nil, in: context, selectionStore: store, now: now)
                explicitStart = true
            case .startSelected(let id, let token):
                try TaskLiveActivityCommandService.start(taskID: id, token: token, in: context, selectionStore: store, now: now)
                explicitStart = true
            case .complete(let id, let token):
                try TaskLiveActivityCommandService.complete(taskID: id, token: token, in: context, selectionStore: store, now: now)
                TaskNotificationScheduler.shared.cancelNotifications(for: [id])
            case .advance(let id, let token):
                try TaskLiveActivityCommandService.browse(taskID: id, token: token, in: context, selectionStore: store, now: now)
            case .pauseFocus, .resumeFocus, .stopFocus:
                return
            }
        } catch {
            await coordinator.reconcile(context: context, now: now, fromIntent: true)
            switch error {
            case TaskLiveActivitySelectionError.completionNeedsConfirmation:
                throw PlanBaseTaskIntentRuntimeError.completionNeedsConfirmation
            case TaskLiveActivitySelectionError.noOtherTask:
                throw PlanBaseTaskIntentRuntimeError.noNextTask
            case is TaskLiveActivitySelectionError:
                throw PlanBaseTaskIntentRuntimeError.staleTask
            default:
                throw error
            }
        }

        // The model command has committed. Publishing is a separate, retryable cache update.
        do {
            _ = try await CalendarWidgetSnapshotPublicationService.publish(
                context: context,
                themeID: UserDefaults.standard.string(forKey: AppTheme.storageKey) ?? AppThemePreset.defaultID,
                forceTimelineReload: true,
                referenceDate: now
            )
        } catch {
            print("PlanBase widget refresh after intent failed: \(error)")
        }
        await coordinator.reconcile(context: context, now: now, fromIntent: true, explicitStart: explicitStart)
    }

}

private enum PlanBaseTaskIntentRuntimeError: LocalizedError {
    case staleTask
    case noNextTask
    case completionNeedsConfirmation

    var errorDescription: String? {
        switch self {
        case .staleTask:
            "작업이 이미 변경되었습니다."
        case .noNextTask:
            "진행할 다음 작업이 없습니다."
        case .completionNeedsConfirmation:
            "예정된 알림을 확인한 뒤 앱에서 완료해 주세요."
        }
    }
}
#endif
