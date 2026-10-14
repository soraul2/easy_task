import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import EasyTaskCore

private enum BootstrapImageTestError: Error {
    case beforeCommit
}

@Test @MainActor
func bootstrapImageMigrationMatchesLegacyCheckpointAndRetainsRetryableReferences() async throws {
    let directory = try bootstrapImageTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let png = try bootstrapImagePNG()
    try png.write(to: directory.appendingPathComponent("repeat.png"))
    try Data(png.prefix(8)).write(to: directory.appendingPathComponent("corrupt.png"))
    let baseline = try PlanBaseContainerFactory.makeInMemory()
    let candidate = try PlanBaseContainerFactory.makeInMemory()
    let fileNames = ["repeat.png", "missing.png", "repeat.png", "corrupt.png", "../unsafe.png"]
    for container in [baseline, candidate] {
        try seedBootstrapImageReview(in: container.mainContext, id: 1, fileNames: fileNames,
                                     blockFileName: "repeat.png")
    }
    let expected = try bootstrapImageLegacyPreparation(in: baseline.mainContext, directory: directory)
    let first = try await bootstrapImageWorkerPreparation(container: candidate, directory: directory)
    #expect(first.integrity == expected.integrity)
    #expect(first.legacyImages == expected.legacyImages)
    #expect(first.legacyImages?.importedCount == 2)
    #expect(first.legacyImages?.missingFileNames == ["missing.png"])
    #expect(first.legacyImages?.rejectedFileNames == ["../unsafe.png", "corrupt.png"])
    #expect(first.legacyImages?.deferredFileNames == [])
    #expect(try bootstrapImageGraph(in: ModelContext(candidate))
            == bootstrapImageGraph(in: ModelContext(baseline)))

    let second = try await bootstrapImageWorkerPreparation(container: candidate, directory: directory)
    #expect(second.legacyImages?.importedCount == 0)
    #expect(second.legacyImages?.missingFileNames == ["missing.png"])
    #expect(second.legacyImages?.rejectedFileNames == ["../unsafe.png", "corrupt.png"])
    do {
        let context = ModelContext(candidate)
        let review = try #require(context.fetch(FetchDescriptor<DailyReview>()).first)
        let block = try #require(context.fetch(FetchDescriptor<DiaryBlock>()).first)
        let attachments = try context.fetch(FetchDescriptor<DiaryAttachment>())
        #expect(review.imageFileNames == fileNames)
        #expect(block.supersededAt == nil)
        #expect(attachments.count == 2)
        #expect(Set(attachments.map(\.id)).count == 2)
        #expect(attachments.allSatisfy { $0.data == png })
    }

    try png.write(to: directory.appendingPathComponent("missing.png"))
    try png.write(to: directory.appendingPathComponent("corrupt.png"), options: .atomic)
    // An unsafe reference cannot become resolvable by writing outside the fixture.
    // Remove that reference as a committed user edit, then retry the remaining files.
    for container in [baseline, candidate] {
        let context = ModelContext(container)
        let review = try #require(context.fetch(FetchDescriptor<DailyReview>()).first)
        review.imageFileNames = Array(fileNames.dropLast())
        try context.save()
    }
    let recoveredExpected = try bootstrapImageLegacyPreparation(in: ModelContext(baseline),
                                                              directory: directory)
    let recovered = try await bootstrapImageWorkerPreparation(container: candidate, directory: directory)
    #expect(recovered.legacyImages == recoveredExpected.legacyImages)
    #expect(recovered.legacyImages?.importedCount == 2)
    #expect(recovered.legacyImages?.missingFileNames == [])
    #expect(recovered.legacyImages?.rejectedFileNames == [])
    let finalContext = ModelContext(candidate)
    #expect(try bootstrapImageGraph(in: finalContext)
            == bootstrapImageGraph(in: ModelContext(baseline)))
    #expect(try finalContext.fetch(FetchDescriptor<DailyReview>()).first?.imageFileNames.isEmpty == true)
    #expect(try finalContext.fetch(FetchDescriptor<DiaryBlock>()).first?.supersededAt == bootstrapImageNow)
    let attachments = try finalContext.fetch(FetchDescriptor<DiaryAttachment>()).sorted { $0.order < $1.order }
    #expect(attachments.count == 4)
    #expect(attachments.map(\.order) == [0, 100, 200, 300])
    #expect(Set(attachments.map(\.id)).count == 4)
    let finalPass = try await bootstrapImageWorkerPreparation(container: candidate, directory: directory)
    #expect(finalPass.legacyImages == LegacyDiaryAttachmentMigrationReport())
}

@Test @MainActor
func bootstrapImageMigrationDefersBeyondLimitWithoutLosingReferences() async throws {
    let directory = try bootstrapImageTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let png = try bootstrapImagePNG()
    let fileNames = (0..<12).map { String(format: "image-%02d.png", $0) }
    for fileName in fileNames { try png.write(to: directory.appendingPathComponent(fileName)) }
    let container = try PlanBaseContainerFactory.makeInMemory()
    try seedBootstrapImageReview(in: container.mainContext, id: 2, fileNames: fileNames,
                                 blockFileName: fileNames[11])

    let first = try await bootstrapImageWorkerPreparation(container: container, directory: directory)
    #expect(first.legacyImages?.importedCount == DiaryAttachmentService.maximumAttachmentCount)
    #expect(first.legacyImages?.deferredFileNames == Array(fileNames.suffix(2)))
    let afterFirst = try bootstrapImageGraph(in: ModelContext(container))
    let second = try await bootstrapImageWorkerPreparation(container: container, directory: directory)
    #expect(second.legacyImages?.importedCount == 0)
    #expect(second.legacyImages?.deferredFileNames == Array(fileNames.suffix(2)))
    #expect(try bootstrapImageGraph(in: ModelContext(container)) == afterFirst)

    let context = ModelContext(container)
    let review = try #require(context.fetch(FetchDescriptor<DailyReview>()).first)
    let block = try #require(context.fetch(FetchDescriptor<DiaryBlock>()).first)
    let attachments = try context.fetch(FetchDescriptor<DiaryAttachment>())
    #expect(review.imageFileNames == fileNames)
    #expect(block.supersededAt == nil)
    #expect(attachments.count == 10)
    #expect(attachments.allSatisfy { $0.supersededAt == nil && $0.data == png })
    #expect(DiaryAttachmentService.unresolvedLegacyImageFileNames(
        for: review, blocks: [block], attachments: attachments) == Array(fileNames.suffix(2)))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 12)
}

@Test @MainActor
func bootstrapImageMigrationStillValidatesExistingModernAttachments() async throws {
    let directory = try bootstrapImageTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let png = try bootstrapImagePNG()
    let corrupt = Data(png.prefix(8))
    let container = try PlanBaseContainerFactory.makeInMemory()
    try seedBootstrapImageReview(in: container.mainContext, id: 3)
    for (index, data) in [png, corrupt].enumerated() {
        container.mainContext.insert(DiaryAttachment(
            id: bootstrapImageID(30 + index), instanceID: bootstrapImageID(130 + index),
            reviewId: bootstrapImageID(3), order: Double(index) * 100,
            originalFileName: " modern.png ", mimeType: "invalid", byteCount: -1,
            sha256: "invalid", data: data, createdAt: bootstrapImageCreatedAt,
            updatedAt: bootstrapImageCreatedAt))
    }
    try container.mainContext.save()

    let result = try await PlanBaseBootstrapService.prepare(
        container: container, legacyImageMigration: bootstrapImageConfiguration(directory))
    #expect(result.integrity.normalizedFields > 0)
    #expect(result.integrity.supersededRecords == 1)
    #expect(result.legacyImages == LegacyDiaryAttachmentMigrationReport())
    let context = ModelContext(container)
    let rows = try context.fetch(FetchDescriptor<DiaryAttachment>())
    let valid = try #require(rows.first { $0.id == bootstrapImageID(30) })
    let invalid = try #require(rows.first { $0.id == bootstrapImageID(31) })
    let metadata = try DiaryAttachmentService.inspect(png)
    #expect(valid.supersededAt == nil)
    #expect(valid.originalFileName == "modern.png")
    #expect(valid.mimeType == metadata.mediaType.rawValue)
    #expect(valid.byteCount == metadata.byteCount)
    #expect(valid.sha256 == metadata.sha256)
    #expect(valid.data == png)
    #expect(invalid.supersededAt != nil)
    #expect(invalid.data == corrupt)
    let second = try await PlanBaseBootstrapService.prepare(
        container: container, legacyImageMigration: bootstrapImageConfiguration(directory))
    #expect(second.integrity == .noChanges)
    #expect(second.legacyImages == LegacyDiaryAttachmentMigrationReport())
}

@Test @MainActor
func bootstrapImageMigrationReadsOffMainAndCommitsBeforeFreshUIContext() async throws {
    let directory = try bootstrapImageTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let png = try bootstrapImagePNG()
    try png.write(to: directory.appendingPathComponent("ready.png"))
    let container = try PlanBaseContainerFactory.makeInMemory()
    try seedBootstrapImageReview(in: container.mainContext, id: 4,
                                 blockFileName: "ready.png")
    let reads = BootstrapImageThreadRecorder()
    let (result, probe) = try await PlanBaseBootstrapService.withWorker(container: container) { worker in
        let probe = await worker.executionProbe()
        let report = try await worker.prepare(
            legacyImageMigration: bootstrapImageConfiguration(directory), now: bootstrapImageNow,
            beforeImageRead: { reads.record() }, beforeSave: { #expect(!Thread.isMainThread) })
        return (report, probe)
    }
    #expect(!probe.createdOnMainThread)
    #expect(!probe.executingOnMainThread)
    // The hook runs directly before the read and after the synchronous inspect.
    #expect(reads.mainThreadValues == [false, false])
    #expect(result.legacyImages?.importedCount == 1)
    let freshUIContext = ModelContext(container)
    #expect(freshUIContext !== container.mainContext)
    let attachments = try freshUIContext.fetch(FetchDescriptor<DiaryAttachment>())
    #expect(attachments.count == 1)
    #expect(attachments.first?.data == png)
    #expect(attachments.first?.reviewId == bootstrapImageID(4))
    #expect(try freshUIContext.fetch(FetchDescriptor<DiaryBlock>()).first?.supersededAt == bootstrapImageNow)
}

@Test @MainActor
func bootstrapImageMigrationFinalSaveFailureRollsBackWholeGraphBeforeSameWorkerRetry() async throws {
    let directory = try bootstrapImageTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let png = try bootstrapImagePNG()
    for fileName in ["first.png", "second.png"] {
        try png.write(to: directory.appendingPathComponent(fileName))
    }
    let container = try PlanBaseContainerFactory.makeInMemory()
    try seedBootstrapImageReview(in: container.mainContext, id: 5,
                                 fileNames: ["first.png"], blockFileName: "first.png")
    try seedBootstrapImageReview(in: container.mainContext, id: 6,
                                 blockFileName: "second.png")
    container.mainContext.insert(DiaryAttachment(
        id: bootstrapImageID(50), instanceID: bootstrapImageID(150), reviewId: bootstrapImageID(5),
        order: 200, originalFileName: " modern.png ", mimeType: "invalid", byteCount: -1,
        sha256: "invalid", data: png, createdAt: bootstrapImageCreatedAt,
        updatedAt: bootstrapImageCreatedAt))
    try container.mainContext.save()
    let committed = try bootstrapImageGraph(in: container.mainContext)
    let reads = BootstrapImageThreadRecorder()

    try await PlanBaseBootstrapService.withWorker(container: container) { worker in
        do {
            _ = try await worker.prepare(
                legacyImageMigration: bootstrapImageConfiguration(directory), now: bootstrapImageNow,
                beforeImageRead: { reads.record() }, beforeSave: {
                    #expect(!Thread.isMainThread)
                    throw BootstrapImageTestError.beforeCommit
                })
            Issue.record("Injected final-save failure was not propagated")
        } catch BootstrapImageTestError.beforeCommit {
            // Neither the earlier review nor integrity repairs may be committed.
        }
        do {
            let afterFailure = ModelContext(container)
            #expect(try bootstrapImageGraph(in: afterFailure) == committed)
            #expect(try afterFailure.fetchCount(FetchDescriptor<DiaryAttachment>()) == 1)
            #expect(try afterFailure.fetch(FetchDescriptor<DiaryBlock>()).allSatisfy { $0.supersededAt == nil })
        }

        let retried = try await worker.prepare(
            legacyImageMigration: bootstrapImageConfiguration(directory), now: bootstrapImageNow,
            beforeImageRead: { reads.record() }, beforeSave: { #expect(!Thread.isMainThread) })
        #expect(retried.legacyImages?.importedCount == 2)
        let afterRetry = ModelContext(container)
        let reviews = try afterRetry.fetch(FetchDescriptor<DailyReview>())
        let blocks = try afterRetry.fetch(FetchDescriptor<DiaryBlock>())
        let attachments = try afterRetry.fetch(FetchDescriptor<DiaryAttachment>())
        #expect(reviews.allSatisfy { $0.imageFileNames.isEmpty && $0.updatedAt == bootstrapImageNow })
        #expect(blocks.allSatisfy { $0.supersededAt == bootstrapImageNow })
        #expect(attachments.count == 3)
        #expect(attachments.allSatisfy { $0.supersededAt == nil && $0.data == png })
        #expect(attachments.first { $0.id == bootstrapImageID(50) }?.mimeType == "image/png")
    }
    #expect(reads.mainThreadValues.count == 8)
    #expect(reads.mainThreadValues.allSatisfy { !$0 })
}

@Test @MainActor
func startupSessionPublishesImageMigrationReportBeforeInstallingWriters() async throws {
    let directory = try bootstrapImageTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let png = try bootstrapImagePNG()
    try png.write(to: directory.appendingPathComponent("ready.png"))
    let container = try PlanBaseContainerFactory.makeInMemory()
    try seedBootstrapImageReview(in: container.mainContext, id: 7,
                                 fileNames: ["ready.png"], blockFileName: "ready.png")
    try seedBootstrapImageReview(in: container.mainContext, id: 8, fileNames: ["missing.png"])
    let session = PlanBaseStartupSession()
    var installedContext: ModelContext?
    var installedReport: LegacyDiaryAttachmentMigrationReport?
    await session.load(open: { container }, legacyImageMigration: bootstrapImageConfiguration(directory),
                       onReady: { opened, context in
        #expect(opened === container)
        #expect(context !== container.mainContext)
        installedContext = context
        installedReport = session.legacyImageMigrationReport
        #expect(installedReport?.importedCount == 1)
        #expect(installedReport?.missingFileNames == ["missing.png"])
        do {
            let reviews = try context.fetch(FetchDescriptor<DailyReview>())
            #expect(reviews.first { $0.id == bootstrapImageID(7) }?.imageFileNames.isEmpty == true)
            #expect(reviews.first { $0.id == bootstrapImageID(8) }?.imageFileNames == ["missing.png"])
            #expect(try context.fetchCount(FetchDescriptor<DiaryAttachment>()) == 1)
            #expect(try context.fetch(FetchDescriptor<DiaryBlock>()).first?.supersededAt != nil)
        } catch { Issue.record("Fresh UI context could not read migrated graph: \(error)") }
    })
    guard case .ready(_, let context) = session.state else {
        Issue.record("Image bootstrap did not become ready")
        return
    }
    #expect(context === installedContext)
    #expect(session.legacyImageMigrationReport == installedReport)
}

@Test @MainActor
func startupSessionAggregatesImageMigrationImportsAndUsesLatestUnresolvedLists() async throws {
    let directory = try bootstrapImageTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let png = try bootstrapImagePNG()
    try png.write(to: directory.appendingPathComponent("ready.png"))
    let container = try PlanBaseContainerFactory.makeInMemory()
    try seedBootstrapImageReview(in: container.mainContext, id: 9,
                                 fileNames: ["ready.png", "missing.png"])
    let recorder = BootstrapImageImportRecorder()
    let session = PlanBaseStartupSession(prepare: { container, configuration in
        recorder.passes += 1
        let report = try await PlanBaseBootstrapService.prepare(
            container: container, legacyImageMigration: configuration)
        if recorder.passes == 1 {
            #expect(report.legacyImages?.importedCount == 1)
            #expect(report.legacyImages?.missingFileNames == ["missing.png"])
            try png.write(to: directory.appendingPathComponent("missing.png"))
            recorder.session?.recordImport(CloudKitSyncEventSummary(
                kind: .import, isCompleted: true, succeeded: true))
        }
        return report
    })
    recorder.session = session
    await session.load(open: { container }, legacyImageMigration: bootstrapImageConfiguration(directory),
                       onReady: { _, context in
        #expect(session.legacyImageMigrationReport?.importedCount == 2)
        #expect(session.legacyImageMigrationReport?.missingFileNames == [])
        #expect(session.legacyImageMigrationReport?.rejectedFileNames == [])
        #expect(session.legacyImageMigrationReport?.deferredFileNames == [])
        do {
            #expect(try context.fetchCount(FetchDescriptor<DiaryAttachment>()) == 2)
            #expect(try context.fetch(FetchDescriptor<DailyReview>()).first?.imageFileNames.isEmpty == true)
        } catch { Issue.record("Fresh UI context could not read repeated migration: \(error)") }
    })
    #expect(recorder.passes == 2)
    #expect(session.takePendingImport() == nil)
    guard case .ready = session.state else {
        Issue.record("Repeated image bootstrap did not become ready")
        return
    }
}

@Test @MainActor
func bootstrapImageMigrationCancellationBeforeFinalSaveRollsBackAndFreshFacadeCanRetry() async throws {
    let directory = try bootstrapImageTestDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let png = try bootstrapImagePNG()
    try png.write(to: directory.appendingPathComponent("cancelled.png"))
    let container = try PlanBaseContainerFactory.makeInMemory()
    try seedBootstrapImageReview(in: container.mainContext, id: 10,
                                 fileNames: ["cancelled.png"], blockFileName: "cancelled.png")
    container.mainContext.insert(DiaryAttachment(
        id: bootstrapImageID(100), instanceID: bootstrapImageID(400), reviewId: bootstrapImageID(10),
        order: 200, originalFileName: " modern.png ", mimeType: "invalid", byteCount: -1,
        sha256: "invalid", data: png, createdAt: bootstrapImageCreatedAt,
        updatedAt: bootstrapImageCreatedAt))
    try container.mainContext.save()
    let committed = try bootstrapImageGraph(in: container.mainContext)
    let reads = BootstrapImageThreadRecorder()

    do {
        _ = try await PlanBaseBootstrapService.withWorker(container: container) { worker in
            try await worker.prepare(
                legacyImageMigration: bootstrapImageConfiguration(directory), now: bootstrapImageNow,
                beforeImageRead: { reads.record() }, beforeSave: {
                    #expect(!Thread.isMainThread)
                    // Return normally: only the worker's final cancellation check
                    // can abort this fully mutated graph before its single save.
                    withUnsafeCurrentTask { task in
                        #expect(task != nil)
                        task?.cancel()
                        #expect(task?.isCancelled == true)
                    }
                })
        }
        Issue.record("Final-save cancellation did not propagate CancellationError")
    } catch is CancellationError {
        // The detached preparation is cancelled; the caller remains usable.
    }
    try Swift.Task.checkCancellation()
    #expect(reads.mainThreadValues == [false, false])
    do {
        let afterCancellation = ModelContext(container)
        #expect(try bootstrapImageGraph(in: afterCancellation) == committed)
        #expect(try afterCancellation.fetchCount(FetchDescriptor<DiaryAttachment>()) == 1)
        #expect(try afterCancellation.fetch(FetchDescriptor<DailyReview>()).first?.imageFileNames
                == ["cancelled.png"])
        #expect(try afterCancellation.fetch(FetchDescriptor<DiaryBlock>()).first?.supersededAt == nil)
    }

    let retried = try await bootstrapImageWorkerPreparation(container: container, directory: directory)
    #expect(retried.legacyImages?.importedCount == 1)
    let freshUIContext = ModelContext(container)
    let attachments = try freshUIContext.fetch(FetchDescriptor<DiaryAttachment>())
    let modern = try #require(attachments.first { $0.id == bootstrapImageID(100) })
    let metadata = try DiaryAttachmentService.inspect(png)
    #expect(attachments.count == 2)
    #expect(attachments.allSatisfy { $0.supersededAt == nil && $0.data == png })
    #expect(modern.originalFileName == "modern.png")
    #expect(modern.mimeType == metadata.mediaType.rawValue)
    #expect(modern.byteCount == metadata.byteCount)
    #expect(modern.sha256 == metadata.sha256)
    #expect(try freshUIContext.fetch(FetchDescriptor<DailyReview>()).first?.imageFileNames.isEmpty == true)
    #expect(try freshUIContext.fetch(FetchDescriptor<DiaryBlock>()).first?.supersededAt == bootstrapImageNow)
}

private var bootstrapImageCreatedAt: Date { Date(timeIntervalSince1970: 1_783_800_000) }
private var bootstrapImageNow: Date { bootstrapImageCreatedAt.addingTimeInterval(300) }

private func bootstrapImageID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "12000000-0000-0000-0000-%012d", value))!
}

private func bootstrapImageTestDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "PlanBaseBootstrapImages-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func bootstrapImageConfiguration(_ directory: URL) -> PlanBaseLegacyImageMigrationConfiguration {
    PlanBaseLegacyImageMigrationConfiguration(
        appSupportFolder: "UnusedBootstrapImageTestFolder", imageDirectoryURL: directory)
}

@MainActor
private func seedBootstrapImageReview(
    in context: ModelContext,
    id: Int,
    fileNames: [String] = [],
    blockFileName: String? = nil
) throws {
    let dayKey = String(format: "2026-07-%02d", id)
    context.insert(DailyReview(
        id: bootstrapImageID(id), instanceID: bootstrapImageID(100 + id), dayKey: dayKey,
        title: "이미지 이관 \(id)", content: "보존할 회고 \(id)", imageFileNames: fileNames,
        createdAt: bootstrapImageCreatedAt, updatedAt: bootstrapImageCreatedAt))
    if let blockFileName {
        context.insert(DiaryBlock(
            id: bootstrapImageID(200 + id), instanceID: bootstrapImageID(300 + id),
            reviewId: bootstrapImageID(id), dayKey: dayKey, type: .image,
            imageFileName: blockFileName, order: 0, createdAt: bootstrapImageCreatedAt,
            updatedAt: bootstrapImageCreatedAt))
    }
    try context.save()
}

@MainActor
private func bootstrapImageLegacyPreparation(
    in context: ModelContext, directory: URL
) throws -> PlanBaseBootstrapPreparationReport {
    let integrity = try DataIntegrityService.reconcile(context: context)
    let legacyImages = try LegacyDiaryAttachmentMigrationService.migrateIfNeeded(
        context: context, appSupportFolder: "UnusedBootstrapImageTestFolder",
        now: bootstrapImageNow, imageDirectoryURL: directory)
    return PlanBaseBootstrapPreparationReport(integrity: integrity, legacyImages: legacyImages)
}

private func bootstrapImageWorkerPreparation(
    container: ModelContainer, directory: URL
) async throws -> PlanBaseBootstrapPreparationReport {
    try await PlanBaseBootstrapService.withWorker(container: container) { worker in
        try await worker.prepare(legacyImageMigration: bootstrapImageConfiguration(directory),
                                 now: bootstrapImageNow)
    }
}

private func bootstrapImagePNG() throws -> Data {
    let pixel = Data([0xF0, 0x30, 0x50, 0xFF])
    let provider = try #require(CGDataProvider(data: pixel as CFData))
    let image = try #require(CGImage(
        width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
}

private struct BootstrapImageGraph: Equatable, Sendable {
    struct Review: Equatable, Sendable {
        let id: UUID
        let dayKey: String
        let title: String
        let content: String
        let files: [String]
        let createdAt: Date
        let updatedAt: Date
        let supersededAt: Date?
    }
    struct Block: Equatable, Sendable {
        let id: UUID
        let reviewID: UUID
        let dayKey: String
        let type: String
        let file: String?
        let order: Double
        let updatedAt: Date
        let supersededAt: Date?
    }
    struct Attachment: Equatable, Sendable {
        let id: UUID
        let reviewID: UUID
        let order: Double
        let file: String?
        let mimeType: String
        let byteCount: Int
        let sha256: String
        let data: Data
        let createdAt: Date
        let updatedAt: Date
        let supersededAt: Date?
    }
    let reviews: [Review]
    let blocks: [Block]
    let attachments: [Attachment]
}

private func bootstrapImageGraph(in context: ModelContext) throws -> BootstrapImageGraph {
    BootstrapImageGraph(
        reviews: try context.fetch(FetchDescriptor<DailyReview>()).sorted { $0.id.uuidString < $1.id.uuidString }
            .map { .init(id: $0.id, dayKey: $0.dayKey, title: $0.title, content: $0.content,
                         files: $0.imageFileNames, createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                         supersededAt: $0.supersededAt) },
        blocks: try context.fetch(FetchDescriptor<DiaryBlock>()).sorted { $0.id.uuidString < $1.id.uuidString }
            .map { .init(id: $0.id, reviewID: $0.reviewId, dayKey: $0.dayKey, type: $0.type,
                         file: $0.imageFileName, order: $0.order, updatedAt: $0.updatedAt,
                         supersededAt: $0.supersededAt) },
        attachments: try context.fetch(FetchDescriptor<DiaryAttachment>()).sorted { $0.id.uuidString < $1.id.uuidString }
            .map { .init(id: $0.id, reviewID: $0.reviewId, order: $0.order, file: $0.originalFileName,
                         mimeType: $0.mimeType, byteCount: $0.byteCount, sha256: $0.sha256,
                         data: $0.data, createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                         supersededAt: $0.supersededAt) })
}

private final class BootstrapImageThreadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    func record() {
        let isMainThread = Thread.isMainThread
        lock.lock()
        defer { lock.unlock() }
        values.append(isMainThread)
    }

    var mainThreadValues: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

@MainActor
private final class BootstrapImageImportRecorder {
    weak var session: PlanBaseStartupSession?
    var passes = 0
}
