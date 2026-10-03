#if DEBUG
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// Local synthetic export preparation; does not measure file dialogs or disk publication.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_BACKUP_PERFORMANCE"] == "1"))
@MainActor
func goalBackupExportPerformance() throws {
    let reference = Date(timeIntervalSince1970: 1_790_000_000)
    for scale in [10, 100, 1_000] {
        let container = try PlanBaseContainerFactory.makeInMemory()
        let context = container.mainContext
        for index in 0..<scale {
            let templateID = goalBackupID(index * 100 + 1)
            let placementID = goalBackupID(index * 100 + 3)
            context.insert(TaskTemplate(id: templateID, instanceID: goalBackupID(index * 100 + 2),
                name: "루틴 \(index)", createdAt: reference, updatedAt: reference))
            context.insert(TemplatePlacement(id: placementID, instanceID: goalBackupID(index * 100 + 4),
                sourceTemplateId: templateID, templateName: "루틴 \(index)",
                dayKey: DayKey.key(for: reference), createdAt: reference, updatedAt: reference))
            for child in 0..<10 {
                context.insert(Task(id: goalBackupID(index * 100 + 10 + child * 2),
                    instanceID: goalBackupID(index * 100 + 11 + child * 2),
                    title: "작업 \(index)-\(child)", plannedAt: reference, order: Double(child / 2),
                    templatePlacementId: placementID, createdAt: reference, updatedAt: reference))
            }
            let review = DailyReview(id: goalBackupID(index * 100 + 40),
                instanceID: goalBackupID(index * 100 + 41),
                dayKey: DayKey.key(for: DayKey.addingDays(-index, to: reference)), content: "회고 \(index)",
                createdAt: reference, updatedAt: reference)
            context.insert(review)
            for child in 0..<5 {
                context.insert(DiaryBlock(id: goalBackupID(index * 100 + 50 + child * 2),
                    instanceID: goalBackupID(index * 100 + 51 + child * 2),
                    reviewId: review.id, dayKey: review.dayKey, type: .text,
                    text: "블록 \(child)", order: Double(child), createdAt: reference, updatedAt: reference))
            }
        }
        try context.save()
        let warmup = try BackupPackageCodec.makeContents(context: context, exportedAt: reference)
        #expect(warmup.records.payload.tasks.count == scale * 10)
        #expect(warmup.records.payload.templatePlacements?.allSatisfy { $0.taskIds.count == 10 } == true)
        let expected = try goalBackupDigest(warmup)
        let count = scale == 1_000 ? 5 : 30
        var samples: [Double] = []
        for _ in 0..<count {
            let start = DispatchTime.now().uptimeNanoseconds
            let contents = try BackupPackageCodec.makeContents(context: context, exportedAt: reference)
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            #expect(try goalBackupDigest(contents) == expected)
            #expect(!context.hasChanges)
        }
        let sorted = samples.sorted()
        print("GOAL_BENCHMARK name=backup-export parents=\(scale) tasks=\(scale * 10) unit=ms n=\(count) p50=\(sorted[count / 2]) p95=\(sorted[Int(ceil(Double(count) * 0.95)) - 1]) max=\(sorted.last!) digest=\(expected) samples=\(samples)")
        withExtendedLifetime(container) {}
    }
}

private func goalBackupID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(value + 1)))!
}

private func goalBackupDigest(_ contents: BackupPackageContents) throws -> String {
    // Fetch order is not contractual; canonicalize parent/child array order for cross-process comparison.
    var payload = contents.records.payload
    payload.tasks.sort { $0.id.uuidString < $1.id.uuidString }
    payload.taskTemplates.sort { $0.id.uuidString < $1.id.uuidString }
    payload.templatePlacements?.sort { $0.id.uuidString < $1.id.uuidString }
    payload.dailyReviews?.sort { $0.id.uuidString < $1.id.uuidString }
    payload.diaryBlocks?.sort { $0.id.uuidString < $1.id.uuidString }
    return SHA256.hash(data: try BackupCodec.encode(payload)).map { String(format: "%02x", $0) }.joined()
}
#endif
