#if DEBUG && canImport(CoreGraphics) && canImport(ImageIO) && canImport(Darwin)
import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import EasyTaskCore

/// Actual public full reconcile, with 0/20/100 saved, validated, DISTINCT synthetic
/// 1024x1024 PNGs. One untimed warmup and five independent fresh local file stores
/// per condition. The measured context is fresh; setup, image encoding/inspection,
/// fixture saves, independent before/after reads and full-value hashes are untimed.
/// Current reconcile inspects each valid attachment in normalization AND reference
/// validation. Neither check is skipped or replaced with trust in stored metadata.
///
/// These PNGs are generated pixels, not photographs. File size/codec/compression,
/// OS file cache and ImageIO behavior limit extrapolation to real photo libraries.
/// Fresh stores/contexts do NOT imply a cold OS cache; this is function wall/process
/// CPU timing, not app launch, frame latency, CloudKit, or a cache optimization test.
/// No array of 100 decoded images is retained: generation uses one RGBA buffer at
/// a time and saves at most ten compressed PNG models in each short-lived writer.
/// Existing safety coverage remains in DiaryAttachmentServiceTests (unsupported/
/// oversized input and failed replacement) and BackupPackageTests (checksum
/// rejection before restore); this harness does not relax those expectations.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_ATTACHMENT_INTEGRITY_PERFORMANCE"] == "1"))
@MainActor
func goalAttachmentIntegrityPerformance() throws {
    let source = ProcessInfo.processInfo.environment["PLANBASE_GOAL_SOURCE_LABEL"] ?? "unspecified"
    for count in [0, 20, 100] {
        var samples: [GoalAttachmentIntegritySample] = []
        var setupMs: [Double] = []
        var expectedDigest: String?
        for index in -1..<5 {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "PlanBaseGoalAttachmentIntegrity-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let sample: GoalAttachmentIntegritySample
            do {
                // All ModelContainer/ModelContext lifetimes end before deleting
                // this uniquely owned fixture directory, including external blobs.
                defer { try? FileManager.default.removeItem(at: directory) }
                sample = try autoreleasepool {
                    try goalAttachmentIntegritySample(count: count, directory: directory)
                }
            }
            if let expectedDigest { #expect(sample.valueDigest == expectedDigest) }
            else { expectedDigest = sample.valueDigest }
            setupMs.append(sample.setupMs)
            if index >= 0 { samples.append(sample) }
        }
        goalAttachmentIntegrityReport(source: source, count: count, samples: samples,
                                      setupMs: setupMs, digest: expectedDigest ?? "missing")
    }
}

private struct GoalAttachmentIntegrityFixture {
    let container: ModelContainer
    let expectedRows: [String]
    let setupMs: Double
}

private struct GoalAttachmentIntegrityRead {
    let valuePayload: String
    let physicalPayload: String
    let imageSHAs: [String]
    let byteCounts: [Int]
}

private struct GoalAttachmentIntegritySample {
    let wallMs: Double
    let processCpuMs: Double
    let setupMs: Double
    let valueDigest: String
    let physicalDigest: String
    let byteCounts: [Int]
}

@MainActor
private func goalAttachmentIntegritySample(count: Int, directory: URL) throws -> GoalAttachmentIntegritySample {
    let fixture = try goalAttachmentIntegrityFixture(count: count, directory: directory)
    let before = try goalAttachmentIntegrityRead(in: fixture.container, count: count)
    let expected = (fixture.expectedRows + [goalAttachmentIntegrityCountRow(count: count)]).sorted()
        .joined(separator: "\n")
    #expect(before.valuePayload == expected)
    #expect(Set(before.imageSHAs).count == count)
    let context = ModelContext(fixture.container)
    context.autosaveEnabled = false
    #expect(!context.hasChanges)

    let cpuStart = try goalAttachmentIntegrityCPUms()
    let clockStart = DispatchTime.now().uptimeNanoseconds
    let report = try DataIntegrityService.reconcile(context: context)
    let wallMs = goalAttachmentIntegrityElapsed(clockStart)
    let processCpuMs = try goalAttachmentIntegrityCPUms() - cpuStart

    // All output validation is outside both measured clocks. A second independent
    // reader verifies every persisted field and hashes actual image bytes again.
    #expect(report == .noChanges)
    #expect(!context.hasChanges)
    #expect(context.insertedModelsArray.isEmpty)
    #expect(context.changedModelsArray.isEmpty)
    #expect(context.deletedModelsArray.isEmpty)
    let after = try goalAttachmentIntegrityRead(in: fixture.container, count: count)
    #expect(after.valuePayload == expected)
    #expect(after.valuePayload == before.valuePayload)
    #expect(after.physicalPayload == before.physicalPayload)
    #expect(after.imageSHAs == before.imageSHAs)
    #expect(after.byteCounts == before.byteCounts)
    withExtendedLifetime(fixture.container) {}
    return GoalAttachmentIntegritySample(wallMs: wallMs, processCpuMs: processCpuMs,
        setupMs: fixture.setupMs, valueDigest: goalAttachmentIntegritySHA(Data(after.valuePayload.utf8)),
        physicalDigest: goalAttachmentIntegritySHA(Data(after.physicalPayload.utf8)),
        byteCounts: after.byteCounts)
}

@MainActor
private func goalAttachmentIntegrityFixture(count: Int, directory: URL) throws -> GoalAttachmentIntegrityFixture {
    let setupStart = DispatchTime.now().uptimeNanoseconds
    let container = try PlanBaseContainerFactory.makePersistent(
        storeURL: directory.appendingPathComponent("fixture.store"), mode: .local)
    container.mainContext.autosaveEnabled = false
    var expectedRows: [String] = []
    let perReview = DiaryAttachmentService.maximumAttachmentCount
    let reviewCount = (count + perReview - 1) / perReview
    for reviewIndex in 0..<reviewCount {
        let rows: [String] = try autoreleasepool {
            let writer = ModelContext(container)
            writer.autosaveEnabled = false
            let day = String(format: "2026-09-%02d", reviewIndex + 1)
            let time = try #require(DayKey.date(from: day))
            let title = "합성 사진 회고 \(reviewIndex)"
            let content = "PNG 메타데이터와 원본 바이트 보존 \(reviewIndex)"
            let review = DailyReview(id: goalAttachmentIntegrityID(1, reviewIndex),
                instanceID: goalAttachmentIntegrityID(2, reviewIndex), dayKey: day,
                title: title, weather: "맑음", mood: "좋음", content: content,
                createdAt: time, updatedAt: time.addingTimeInterval(60))
            writer.insert(review)
            var result = [goalAttachmentIntegrityReviewFields(
                id: review.id, instanceID: review.instanceID, day: day, title: title,
                weather: "맑음", mood: "좋음", content: content, files: [],
                created: time, updated: time.addingTimeInterval(60), superseded: nil)]
            let end = min(count, (reviewIndex + 1) * perReview)
            for index in (reviewIndex * perReview)..<end {
                let row: String = try autoreleasepool {
                    let png = try goalAttachmentIntegrityPNG(variant: index)
                    let metadata = try DiaryAttachmentService.inspect(png)
                    #expect(metadata.mediaType == .png)
                    #expect(metadata.byteCount == png.count)
                    #expect(metadata.sha256 == goalAttachmentIntegritySHA(png))
                    let order = Double(index % perReview) * 100
                    let name = "synthetic-\(index).png"
                    let created = time.addingTimeInterval(Double(index % perReview) + 1)
                    let updated = created.addingTimeInterval(1)
                    let attachment = DiaryAttachment(id: goalAttachmentIntegrityID(3, index),
                        instanceID: goalAttachmentIntegrityID(4, index), reviewId: review.id,
                        order: order, originalFileName: name, mimeType: metadata.mediaType.rawValue,
                        byteCount: metadata.byteCount, sha256: metadata.sha256, data: png,
                        createdAt: created, updatedAt: updated)
                    writer.insert(attachment)
                    return goalAttachmentIntegrityAttachmentFields(
                        id: attachment.id, instanceID: attachment.instanceID, reviewID: review.id,
                        order: order, name: name, mime: metadata.mediaType.rawValue,
                        bytes: png.count, storedSHA: metadata.sha256, actualSHA: metadata.sha256,
                        created: created, updated: updated, superseded: nil)
                }
                result.append(row)
            }
            try writer.save()
            #expect(!writer.hasChanges)
            return result
        }
        expectedRows.append(contentsOf: rows)
    }
    return GoalAttachmentIntegrityFixture(container: container, expectedRows: expectedRows,
        setupMs: goalAttachmentIntegrityElapsed(setupStart))
}

@MainActor
private func goalAttachmentIntegrityRead(in container: ModelContainer, count: Int) throws -> GoalAttachmentIntegrityRead {
    let reader = ModelContext(container)
    reader.autosaveEnabled = false
    let reviews = try reader.fetch(FetchDescriptor<DailyReview>()).sorted { $0.instanceID.uuidString < $1.instanceID.uuidString }
    let attachments = try reader.fetch(FetchDescriptor<DiaryAttachment>()).sorted { $0.instanceID.uuidString < $1.instanceID.uuidString }
    let perReview = DiaryAttachmentService.maximumAttachmentCount
    #expect(reviews.count == (count + perReview - 1) / perReview)
    #expect(attachments.count == count)
    #expect(Set(reviews.map(\.instanceID)).count == reviews.count)
    #expect(Set(attachments.map(\.instanceID)).count == count)
    #expect(Set(attachments.map(\.persistentModelID)).count == count)
    var valueRows = reviews.map { review in
        goalAttachmentIntegrityReviewFields(id: review.id, instanceID: review.instanceID,
            day: review.dayKey, title: review.title, weather: review.weather, mood: review.mood,
            content: review.content, files: review.imageFileNames, created: review.createdAt,
            updated: review.updatedAt, superseded: review.supersededAt)
    }
    var physicalRows = reviews.map { "review-pid|\($0.instanceID)|\(String(reflecting: $0.persistentModelID))" }
    var imageSHAs: [String] = []
    var byteCounts: [Int] = []
    for attachment in attachments {
        let values: (String, String, Int) = autoreleasepool {
            let bytes = attachment.data
            let sha = goalAttachmentIntegritySHA(bytes)
            #expect(attachment.byteCount == bytes.count)
            #expect(attachment.sha256 == sha)
            let row = goalAttachmentIntegrityAttachmentFields(
                id: attachment.id, instanceID: attachment.instanceID, reviewID: attachment.reviewId,
                order: attachment.order, name: attachment.originalFileName, mime: attachment.mimeType,
                bytes: attachment.byteCount, storedSHA: attachment.sha256, actualSHA: sha,
                created: attachment.createdAt, updated: attachment.updatedAt, superseded: attachment.supersededAt)
            return (row, sha, bytes.count)
        }
        valueRows.append(values.0)
        imageSHAs.append(values.1)
        byteCounts.append(values.2)
        physicalRows.append("attachment-pid|\(attachment.instanceID)|\(String(reflecting: attachment.persistentModelID))")
    }
    // The fixture deliberately contains only reviews and attachments. Verify all
    // other current schema model counts to detect unintended insertions by the
    // full reconcile (including activity/progress/Focus compatibility paths).
    let otherCounts = try [
        reader.fetchCount(FetchDescriptor<CalendarEvent>()), reader.fetchCount(FetchDescriptor<TaskTemplate>()),
        reader.fetchCount(FetchDescriptor<TaskTemplateItem>()), reader.fetchCount(FetchDescriptor<TemplatePlacement>()),
        reader.fetchCount(FetchDescriptor<Task>()), reader.fetchCount(FetchDescriptor<TaskChecklistItem>()),
        reader.fetchCount(FetchDescriptor<DiaryBlock>()), reader.fetchCount(FetchDescriptor<Memo>()),
        reader.fetchCount(FetchDescriptor<MemoDrawing>()), reader.fetchCount(FetchDescriptor<MemoChecklistItem>()),
        reader.fetchCount(FetchDescriptor<TaskCompletionActivity>()), reader.fetchCount(FetchDescriptor<TaskProgressEvent>()),
        reader.fetchCount(FetchDescriptor<FocusSession>())
    ]
    #expect(otherCounts.allSatisfy { $0 == 0 })
    #expect(!reader.hasChanges)
    valueRows.append("counts|reviews=\(reviews.count)|attachments=\(attachments.count)|others=\(otherCounts)|pending=0")
    let payload = valueRows.sorted().joined(separator: "\n")
    physicalRows.append(payload)
    withExtendedLifetime(container) {}
    return GoalAttachmentIntegrityRead(valuePayload: payload,
        physicalPayload: physicalRows.sorted().joined(separator: "\n"), imageSHAs: imageSHAs, byteCounts: byteCounts)
}

private func goalAttachmentIntegrityPNG(variant: Int) throws -> Data {
    let side = 1_024
    var pixels = Data(count: side * side * 4)
    pixels.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
        let bytes = buffer.bindMemory(to: UInt8.self)
        for y in 0..<side {
            for x in 0..<side {
                let offset = (y * side + x) * 4
                // Deterministic gradient/checker texture; changing real pixels
                // makes every variant distinct without invalid trailing markers.
                bytes[offset] = UInt8(truncatingIfNeeded: x * 3 + y * 5 + variant * 17)
                bytes[offset + 1] = UInt8(truncatingIfNeeded: (x / 16) * 11 + y * 2 + variant * 29)
                bytes[offset + 2] = UInt8(truncatingIfNeeded: x + (y / 8) * 7 + variant * 43)
                bytes[offset + 3] = 255
            }
        }
    }
    let provider = try #require(CGDataProvider(data: pixels as CFData))
    let image = try #require(CGImage(width: side, height: side, bitsPerComponent: 8,
        bitsPerPixel: 32, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    let png = output as Data
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(decoded.width == side && decoded.height == side)
    #expect(png.count <= DiaryAttachmentService.maximumImageSizeBytes)
    return png
}

private func goalAttachmentIntegrityReviewFields(
    id: UUID, instanceID: UUID, day: String, title: String, weather: String, mood: String,
    content: String, files: [String], created: Date, updated: Date, superseded: Date?
) -> String {
    ["review", id.uuidString, instanceID.uuidString, day, title, weather, mood, content,
     files.joined(separator: ";"), goalAttachmentIntegrityDate(created), goalAttachmentIntegrityDate(updated),
     goalAttachmentIntegrityDate(superseded)].map(goalAttachmentIntegrityField).joined(separator: "|")
}

private func goalAttachmentIntegrityAttachmentFields(
    id: UUID, instanceID: UUID, reviewID: UUID, order: Double, name: String?, mime: String,
    bytes: Int, storedSHA: String, actualSHA: String, created: Date, updated: Date, superseded: Date?
) -> String {
    ["attachment", id.uuidString, instanceID.uuidString, reviewID.uuidString, String(order.bitPattern),
     name ?? "nil", mime, String(bytes), storedSHA, actualSHA, goalAttachmentIntegrityDate(created),
     goalAttachmentIntegrityDate(updated), goalAttachmentIntegrityDate(superseded)]
        .map(goalAttachmentIntegrityField).joined(separator: "|")
}

private func goalAttachmentIntegrityCountRow(count: Int) -> String {
    let perReview = DiaryAttachmentService.maximumAttachmentCount
    let zeroCounts = Array(repeating: 0, count: 13)
    return "counts|reviews=\((count + perReview - 1) / perReview)|attachments=\(count)|others=\(zeroCounts)|pending=0"
}

private func goalAttachmentIntegrityField(_ value: String) -> String { "\(value.utf8.count):\(value)" }
private func goalAttachmentIntegrityDate(_ value: Date?) -> String { value.map { String($0.timeIntervalSinceReferenceDate.bitPattern) } ?? "nil" }
private func goalAttachmentIntegrityID(_ namespace: Int, _ index: Int) -> UUID {
    UUID(uuidString: String(format: "39000000-0000-4000-%04X-%012X", namespace, index + 1))!
}
private func goalAttachmentIntegritySHA(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}
private func goalAttachmentIntegrityElapsed(_ start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}
private func goalAttachmentIntegrityCPUms() throws -> Double {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else {
        throw NSError(domain: "GoalAttachmentIntegrity.getrusage", code: Int(errno))
    }
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1_000
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000
}
private func goalAttachmentIntegrityP50(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    return sorted[sorted.count / 2]
}
private func goalAttachmentIntegrityReport(
    source: String, count: Int, samples: [GoalAttachmentIntegritySample], setupMs: [Double], digest: String
) {
    let wall = samples.map(\.wallMs)
    let cpu = samples.map(\.processCpuMs)
    let sizes = samples.first?.byteCounts ?? []
    print("GOAL_ATTACHMENT_INTEGRITY_BENCHMARK source=\(source) harness=v1 name=full-reconcile-valid-saved-png attachments=\(count) width=1024 height=1024 store=fresh-local-file unit=ms n=\(samples.count) warmup=1 independentRepeat=1 independentFixturePerSample=true wallP50=\(goalAttachmentIntegrityP50(wall)) wallMax=\(wall.max() ?? 0) processCpuP50=\(goalAttachmentIntegrityP50(cpu)) processCpuMax=\(cpu.max() ?? 0) wallSamples=\(wall) processCpuSamples=\(cpu)")
    print("GOAL_ATTACHMENT_INTEGRITY_OUTPUT source=\(source) attachments=\(count) fullValueDigest=\(digest) fullPhysicalDigests=\(samples.map(\.physicalDigest)) physicalDigestAcrossStoresExpectedEqual=false beforeAfterPhysicalEqual=true distinctImageSHAs=\(count) originalBytesHashedOutsideTiming=true metadataAndReferencesUnchanged=true report=noChanges pending=0 encodedByteMin=\(sizes.min() ?? 0) encodedByteMax=\(sizes.max() ?? 0) encodedByteTotal=\(sizes.reduce(0, +)) encodedByteCounts=\(sizes)")
    print("GOAL_ATTACHMENT_INTEGRITY_SETUP source=\(source) attachments=\(count) includesWarmup=true unit=ms outsideReconcile=true includesContainerImageGenerationEncodeDecodeInspectionAndSave=true samples=\(setupMs)")
    print("GOAL_ATTACHMENT_INTEGRITY_LIMITS source=\(source) attachments=\(count) timed=actual-public-full-reconcile defaultsSaveAndBackfillPreserved=true conditionalSaveTimed=true noChangesExpected=true commandNotificationNotMeasured=true mainActorSynchronous=true processCpuIncludesStoreThreadsAndOtherProcessWork=true clockOverheadNotSubtracted=true n5TailEstimateNotReported=true osCacheColdAssumed=false beforeReadMayWarmFileCache=true actualFetchCount=unmeasured sqlStatements=unmeasured peakMemory=unmeasured appInputToFrame=unmeasured syntheticPNGNotRealPhoto=true generatedVariantPixelsDistinct=true noSafetyCheckSkipped=true")
}
#endif
