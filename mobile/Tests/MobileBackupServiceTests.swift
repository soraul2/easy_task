import Foundation
import PlanBaseCore
import SwiftData
import XCTest
@testable import PlanBase

@MainActor
private final class FakeMobileBackupFileAdapter: MobileBackupFileAdapter {
    var preparedImport: MobileBackupPreparedImport?
    var importError: Error?
    var exportArtifact: MobileBackupExportArtifact?
    var exportError: Error?
    var prepareImportCount = 0
    var prepareExportCount = 0
    var cleanedDirectoryURLs: [URL] = []

    func prepareImport(from sourceURL: URL) async throws -> MobileBackupPreparedImport {
        prepareImportCount += 1
        if let importError {
            throw importError
        }
        guard let preparedImport else {
            throw MobileBackupServiceError.fileOperation("테스트 가져오기 결과 없음")
        }
        return preparedImport
    }

    func prepareExport(
        contents: BackupPackageContents,
        suggestedFileName: String
    ) async throws -> MobileBackupExportArtifact {
        prepareExportCount += 1
        if let exportError {
            throw exportError
        }
        guard let exportArtifact else {
            throw MobileBackupServiceError.fileOperation("테스트 내보내기 결과 없음")
        }
        return exportArtifact
    }

    func cleanup(directoryURL: URL) async {
        cleanedDirectoryURLs.append(directoryURL)
    }
}

private final class NotificationCountBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int {
        lock.withLock { storedCount }
    }

    func increment() {
        lock.withLock {
            storedCount += 1
        }
    }
}

@MainActor
final class MobileBackupServiceTests: XCTestCase {
    func testImportCancellationDoesNotReadFileOrShowError() throws {
        let adapter = FakeMobileBackupFileAdapter()
        let coordinator = MobileBackupCoordinator(fileAdapter: adapter)
        let context = try PlanBaseContainerFactory.makeInMemory().mainContext

        coordinator.requestImport()
        coordinator.handlePickerResult(
            .cancelled,
            for: .importBackup,
            context: context
        )

        XCTAssertFalse(coordinator.isBusy)
        XCTAssertNil(coordinator.pickerRequest)
        XCTAssertNil(coordinator.notice)
        XCTAssertEqual(adapter.prepareImportCount, 0)
    }

    func testSecurityScopedAccessFailureLeavesStoreUnchangedAndPostsNoNotification() async throws {
        let adapter = FakeMobileBackupFileAdapter()
        adapter.importError = MobileBackupServiceError.securityScopedAccessDenied
        let coordinator = MobileBackupCoordinator(fileAdapter: adapter)
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        context.insert(PlanBaseCore.Task(
            title: "기존 작업",
            plannedAt: Date(),
            order: 100
        ))
        try context.save()
        let notifications = notificationCounter(for: context)
        defer { NotificationCenter.default.removeObserver(notifications.token) }

        coordinator.requestImport()
        await coordinator.importSelectedURL(
            URL(fileURLWithPath: "/tmp/access-denied.easytaskbackup"),
            context: context
        )

        XCTAssertEqual(
            try context.fetch(FetchDescriptor<PlanBaseCore.Task>()).map(\.title),
            ["기존 작업"]
        )
        XCTAssertEqual(notifications.count.count, 0)
        XCTAssertEqual(coordinator.notice?.kind, .failure)
        XCTAssertEqual(adapter.prepareImportCount, 1)
    }

    func testImportCopyFailureLeavesStoreUnchangedAndPostsNoNotification() async throws {
        let adapter = FakeMobileBackupFileAdapter()
        adapter.importError = MobileBackupServiceError.fileOperation("임시 복사 실패")
        let coordinator = MobileBackupCoordinator(fileAdapter: adapter)
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        let notifications = notificationCounter(for: context)
        defer { NotificationCenter.default.removeObserver(notifications.token) }

        coordinator.requestImport()
        await coordinator.importSelectedURL(
            URL(fileURLWithPath: "/tmp/copy-failure.easytaskbackup"),
            context: context
        )

        XCTAssertTrue(
            try context.fetch(FetchDescriptor<PlanBaseCore.Task>()).isEmpty
        )
        XCTAssertEqual(notifications.count.count, 0)
        XCTAssertEqual(coordinator.notice?.kind, .failure)
        XCTAssertTrue(
            coordinator.notice?.message.contains("임시 복사 실패") == true
        )
    }

    func testSuccessfulPackageImportPostsOneNotificationAndCleansOnlyPreparedDirectory() async throws {
        let source = try PlanBaseContainerFactory.makeInMemory()
        let importedTask = PlanBaseCore.Task(
            title: "가져온 작업",
            plannedAt: Date(),
            order: 100
        )
        source.mainContext.insert(importedTask)
        try source.mainContext.save()
        let contents = try BackupPackageCodec.makeContents(
            context: source.mainContext
        )
        let cleanupURL = URL(fileURLWithPath: "/tmp/mobile-backup-success")
        let adapter = FakeMobileBackupFileAdapter()
        adapter.preparedImport = MobileBackupPreparedImport(
            payload: .package(contents),
            cleanupDirectoryURL: cleanupURL
        )
        let coordinator = MobileBackupCoordinator(fileAdapter: adapter)
        let destination = try PlanBaseContainerFactory.makeInMemory()
        let context = destination.mainContext
        let notifications = notificationCounter(for: context)
        defer { NotificationCenter.default.removeObserver(notifications.token) }

        coordinator.requestImport()
        await coordinator.importSelectedURL(
            URL(fileURLWithPath: "/tmp/valid.easytaskbackup"),
            context: context
        )

        XCTAssertEqual(
            try context.fetch(FetchDescriptor<PlanBaseCore.Task>()).map(\.title),
            ["가져온 작업"]
        )
        XCTAssertEqual(notifications.count.count, 1)
        XCTAssertEqual(adapter.cleanedDirectoryURLs, [cleanupURL])
        XCTAssertEqual(coordinator.notice?.kind, .success)
        XCTAssertTrue(
            coordinator.notice?.message.contains("데이터 1건") == true
        )
        XCTAssertFalse(coordinator.isBusy)
    }

    func testTamperedPackageLeavesStoreUnchangedAndPostsNoNotification() async throws {
        let source = try PlanBaseContainerFactory.makeInMemory()
        source.mainContext.insert(PlanBaseCore.Task(
            title: "변조된 백업 작업",
            plannedAt: Date(),
            order: 100
        ))
        try source.mainContext.save()
        var contents = try BackupPackageCodec.makeContents(
            context: source.mainContext
        )
        contents.manifest.recordsSHA256 = String(repeating: "0", count: 64)

        let cleanupURL = URL(fileURLWithPath: "/tmp/mobile-backup-tampered")
        let adapter = FakeMobileBackupFileAdapter()
        adapter.preparedImport = MobileBackupPreparedImport(
            payload: .package(contents),
            cleanupDirectoryURL: cleanupURL
        )
        let coordinator = MobileBackupCoordinator(fileAdapter: adapter)
        let destination = try PlanBaseContainerFactory.makeInMemory()
        let context = destination.mainContext
        context.insert(PlanBaseCore.Task(
            title: "기존 작업",
            plannedAt: Date(),
            order: 100
        ))
        try context.save()
        let notifications = notificationCounter(for: context)
        defer { NotificationCenter.default.removeObserver(notifications.token) }

        coordinator.requestImport()
        await coordinator.importSelectedURL(
            URL(fileURLWithPath: "/tmp/tampered.easytaskbackup"),
            context: context
        )

        XCTAssertEqual(
            try context.fetch(FetchDescriptor<PlanBaseCore.Task>()).map(\.title),
            ["기존 작업"]
        )
        XCTAssertEqual(notifications.count.count, 0)
        XCTAssertEqual(adapter.cleanedDirectoryURLs, [cleanupURL])
        XCTAssertEqual(coordinator.notice?.kind, .failure)
        XCTAssertFalse(coordinator.isBusy)
    }

    func testLegacyJSONImportWarnsThatReferencedImagesAreNotIncluded() async throws {
        let source = try PlanBaseContainerFactory.makeInMemory()
        _ = DailyReviewService.save(
            review: nil,
            dayKey: "2026-07-24",
            content: "가져온 회고",
            imageFileNames: ["legacy-image.jpg"],
            in: source.mainContext
        )
        try source.mainContext.save()
        let payload = try BackupCodec.makePayload(context: source.mainContext)
        let cleanupURL = URL(fileURLWithPath: "/tmp/mobile-backup-legacy")
        let adapter = FakeMobileBackupFileAdapter()
        adapter.preparedImport = MobileBackupPreparedImport(
            payload: .legacyJSON(payload),
            cleanupDirectoryURL: cleanupURL
        )
        let coordinator = MobileBackupCoordinator(fileAdapter: adapter)
        let destination = try PlanBaseContainerFactory.makeInMemory()
        let context = destination.mainContext
        let notifications = notificationCounter(for: context)
        defer { NotificationCenter.default.removeObserver(notifications.token) }

        coordinator.requestImport()
        await coordinator.importSelectedURL(
            URL(fileURLWithPath: "/tmp/legacy.json"),
            context: context
        )

        XCTAssertEqual(
            try context.fetch(FetchDescriptor<DailyReview>()).map(\.content),
            ["가져온 회고"]
        )
        XCTAssertEqual(notifications.count.count, 1)
        XCTAssertEqual(adapter.cleanedDirectoryURLs, [cleanupURL])
        XCTAssertEqual(coordinator.notice?.kind, .success)
        XCTAssertTrue(
            coordinator.notice?.message.contains("이미지 원본 미포함 1개") == true
        )
        XCTAssertFalse(coordinator.isBusy)
    }

    func testExportCancellationCleansPreparedDirectoryWithoutNotice() async throws {
        let cleanupURL = URL(fileURLWithPath: "/tmp/mobile-backup-export")
        let packageURL = cleanupURL.appendingPathComponent(
            "planbase-backup.easytaskbackup",
            isDirectory: true
        )
        let adapter = FakeMobileBackupFileAdapter()
        adapter.exportArtifact = MobileBackupExportArtifact(
            packageURL: packageURL,
            cleanupDirectoryURL: cleanupURL
        )
        let coordinator = MobileBackupCoordinator(fileAdapter: adapter)
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext

        coordinator.requestExport(context: context)
        let request = try await waitForPickerRequest(coordinator)
        coordinator.handlePickerResult(
            .cancelled,
            for: request,
            context: context
        )
        await waitForIdle(coordinator)

        XCTAssertEqual(adapter.prepareExportCount, 1)
        XCTAssertEqual(adapter.cleanedDirectoryURLs, [cleanupURL])
        XCTAssertNil(coordinator.notice)
    }

    private func notificationCounter(
        for context: ModelContext
    ) -> (token: NSObjectProtocol, count: NotificationCountBox) {
        let count = NotificationCountBox()
        let token = NotificationCenter.default.addObserver(
            forName: PersistenceCommandService.dataChangedNotification,
            object: context,
            queue: nil
        ) { _ in
            count.increment()
        }
        return (token, count)
    }

    private func waitForPickerRequest(
        _ coordinator: MobileBackupCoordinator
    ) async throws -> MobileBackupPickerRequest {
        for _ in 0..<200 {
            if let request = coordinator.pickerRequest {
                return request
            }
            try await Swift.Task.sleep(for: .milliseconds(5))
        }
        XCTFail("백업 파일 선택 요청이 생성되지 않았습니다.")
        throw MobileBackupServiceError.fileOperation("테스트 시간 초과")
    }

    private func waitForIdle(_ coordinator: MobileBackupCoordinator) async {
        for _ in 0..<200 where coordinator.isBusy {
            try? await Swift.Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(coordinator.isBusy)
    }
}
