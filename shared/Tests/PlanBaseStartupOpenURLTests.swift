import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

private enum StartupOpenURLTestError: Error {
    case openingFailed
}

@Test @MainActor
func startupOpenURLsStayQueuedUntilReadyAndDrainInFIFOOrderOnce() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let session = startupOpenURLTestSession()
    let board = try #require(PlanBaseDeepLink.boardNewTaskTodayURL())
    let calendar = try #require(PlanBaseDeepLink.calendarURL(dayKey: "2026-10-13"))
    // Repeated delivery is retained as a distinct queue entry.
    let expected = [board, calendar, board]
    for url in expected { session.recordOpenURL(url) }
    #expect(session.pendingOpenURLRevision == 3)
    #expect(session.takePendingOpenURLs().isEmpty)
    #expect(session.pendingOpenURLRevision == 3)
    var installedWriters = 0
    await session.load(open: {
        #expect(session.takePendingOpenURLs().isEmpty)
        return container
    }, onReady: { opened, context in
        installedWriters += 1
        #expect(opened === container)
        #expect(context !== container.mainContext)
        // Installation precedes the ready transition, so draining here must
        // preserve URLs for the ready scene's handler.
        #expect(session.takePendingOpenURLs().isEmpty)
    })
    guard case .ready = session.state else {
        Issue.record("Startup did not become ready for queued URLs")
        return
    }
    #expect(installedWriters == 1)
    #expect(session.takePendingOpenURLs() == expected)
    #expect(session.takePendingOpenURLs().isEmpty)
    #expect(session.pendingOpenURLRevision == 3)
}

@Test @MainActor
func startupOpenURLsSurviveOpeningFailureAndRetry() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let session = startupOpenURLTestSession()
    let first = try #require(PlanBaseDeepLink.boardURL(dayKey: "2026-10-13"))
    let whileFailed = try #require(PlanBaseDeepLink.focusURL())
    let afterRetry = try #require(PlanBaseDeepLink.calendarTodayURL())
    var installedWriters = 0
    session.recordOpenURL(first)
    await session.load(open: { throw StartupOpenURLTestError.openingFailed },
                       onReady: { _, _ in installedWriters += 1 })
    guard case .failed = session.state else {
        Issue.record("Injected opening failure was not reported")
        return
    }
    #expect(installedWriters == 0)
    session.recordOpenURL(whileFailed)
    #expect(session.pendingOpenURLRevision == 2)
    #expect(session.takePendingOpenURLs().isEmpty)

    session.retry()
    #expect(session.attempt == 1)
    #expect(session.pendingOpenURLRevision == 2)
    #expect(session.takePendingOpenURLs().isEmpty)
    session.recordOpenURL(afterRetry)
    await session.load(open: { container }, onReady: { _, _ in installedWriters += 1 })
    guard case .ready = session.state else {
        Issue.record("Retried startup did not become ready")
        return
    }
    #expect(installedWriters == 1)
    #expect(session.pendingOpenURLRevision == 3)
    #expect(session.takePendingOpenURLs() == [first, whileFailed, afterRetry])
    #expect(session.takePendingOpenURLs().isEmpty)
}

@Test @MainActor
func startupOpenURLsQueuedAfterReadyAdvanceRevisionAndDrainOnce() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let session = startupOpenURLTestSession()
    await session.load(open: { container })
    guard case .ready = session.state else {
        Issue.record("Startup did not become ready")
        return
    }
    #expect(session.pendingOpenURLRevision == 0)
    #expect(session.takePendingOpenURLs().isEmpty)
    let first = try #require(PlanBaseDeepLink.focusURL())
    let second = try #require(PlanBaseDeepLink.calendarTodayURL())
    let later = try #require(PlanBaseDeepLink.boardNewTaskTodayURL())
    session.recordOpenURL(first)
    #expect(session.pendingOpenURLRevision == 1)
    session.recordOpenURL(second)
    #expect(session.pendingOpenURLRevision == 2)
    #expect(session.takePendingOpenURLs() == [first, second])
    #expect(session.takePendingOpenURLs().isEmpty)
    #expect(session.pendingOpenURLRevision == 2)
    session.recordOpenURL(later)
    #expect(session.pendingOpenURLRevision == 3)
    #expect(session.takePendingOpenURLs() == [later])
    #expect(session.takePendingOpenURLs().isEmpty)
}

@Test @MainActor
func cancelledSceneCallerKeepsSharedStartupAndPendingOpenURLs() async throws {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let preparation = StartupOpenURLTestSuspension()
    let secondSceneStarted = StartupOpenURLTestSignal()
    let session = PlanBaseStartupSession(prepare: { _, _ in
        await preparation.suspend()
        // Cancelling a scene caller must not cancel the session's shared task.
        try Swift.Task.checkCancellation()
        return PlanBaseBootstrapPreparationReport(integrity: .noChanges)
    })
    let first = try #require(PlanBaseDeepLink.boardURL(dayKey: "2026-10-13"))
    let afterCancellation = try #require(PlanBaseDeepLink.focusURL())
    var openCount = 0
    var installedWriters = 0
    session.recordOpenURL(first)
    let firstScene = Swift.Task { @MainActor in
        await session.load(open: { openCount += 1; return container },
                           onReady: { _, _ in installedWriters += 1 })
    }
    await preparation.entered.wait()
    #expect(session.takePendingOpenURLs().isEmpty)
    firstScene.cancel()
    #expect(firstScene.isCancelled)
    session.recordOpenURL(afterCancellation)
    let secondScene = Swift.Task { @MainActor in
        secondSceneStarted.signal()
        await session.load(open: { openCount += 1; return container },
                           onReady: { _, _ in installedWriters += 1 })
    }
    await secondSceneStarted.wait()
    preparation.resume()
    await firstScene.value
    await secondScene.value
    guard case .ready = session.state else {
        Issue.record("Cancelling one scene prevented the shared startup from completing")
        return
    }
    #expect(openCount == 1)
    #expect(installedWriters == 1)
    #expect(session.pendingOpenURLRevision == 2)
    #expect(session.takePendingOpenURLs() == [first, afterCancellation])
    #expect(session.takePendingOpenURLs().isEmpty)
}

@MainActor
private func startupOpenURLTestSession() -> PlanBaseStartupSession {
    PlanBaseStartupSession(prepare: { _, _ in
        PlanBaseBootstrapPreparationReport(integrity: .noChanges)
    })
}

/// One-shot signals keep cancellation and scene-joining checks deterministic.
@MainActor
private final class StartupOpenURLTestSignal {
    private var isSignalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isSignalled else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        guard !isSignalled else { return }
        isSignalled = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations { continuation.resume() }
    }
}

@MainActor
private final class StartupOpenURLTestSuspension {
    let entered = StartupOpenURLTestSignal()
    private let released = StartupOpenURLTestSignal()

    func suspend() async {
        entered.signal()
        await released.wait()
    }

    func resume() {
        released.signal()
    }
}
