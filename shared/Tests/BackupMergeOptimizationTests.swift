import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

/// End-to-end local package merge timing. Source generation/export is outside the samples.
/// Each insertion starts with a fresh destination; replay samples start from the same saved content.
@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_BACKUP_MERGE_PERFORMANCE"] == "1"))
@MainActor
func backupMergeOptimizationPerformance() throws {
    for scale in [10, 100] {
        let source = try makeBackupOptimizationFixture(scale: scale)
        let contents = try BackupPackageCodec.makeContents(
            context: source.mainContext,
            exportedAt: Date(timeIntervalSince1970: 1_790_000_000)
        )
        let expectedCount = scale * 19
        var insertionSamples: [Double] = []
        var replaySamples: [Double] = []
        for iteration in 0..<6 {
            let destination = try PlanBaseContainerFactory.makeInMemory()
            let context = destination.mainContext
            let start = DispatchTime.now().uptimeNanoseconds
            let inserted = try BackupPackageCodec.restoreMerging(contents, into: context)
            let insertedAt = DispatchTime.now().uptimeNanoseconds
            let replayed = try BackupPackageCodec.restoreMerging(contents, into: context)
            let replayedAt = DispatchTime.now().uptimeNanoseconds
            #expect(inserted.insertedRecords == expectedCount)
            #expect(replayed.insertedRecords == 0)
            #expect(replayed.updatedRecords == 0)
            #expect(replayed.preservedLocalRecords == expectedCount)
            #expect(!context.hasChanges)
            if iteration > 0 {
                insertionSamples.append(Double(insertedAt - start) / 1_000_000)
                replaySamples.append(Double(replayedAt - insertedAt) / 1_000_000)
            }
            withExtendedLifetime(destination) {}
        }
        print("BACKUP_MERGE_BENCHMARK scale=\(scale) records=\(expectedCount) unit=ms operation=insert n=5 samples=\(insertionSamples)")
        print("BACKUP_MERGE_BENCHMARK scale=\(scale) records=\(expectedCount) unit=ms operation=replay n=5 samples=\(replaySamples)")
        withExtendedLifetime(source) {}
    }
}

@MainActor
private func makeBackupOptimizationFixture(scale: Int) throws -> ModelContainer {
    let container = try PlanBaseContainerFactory.makeInMemory()
    let context = container.mainContext
    let reference = Date(timeIntervalSince1970: 1_785_000_000)
    for index in 0..<scale {
        let template = TaskTemplate(name: "루틴 \(index)", createdAt: reference, updatedAt: reference)
        context.insert(template)
        for child in 0..<3 {
            context.insert(TaskTemplateItem(templateId: template.id, title: "항목 \(child)",
                order: Double(child + 1) * 100, createdAt: reference, updatedAt: reference))
        }
        for taskIndex in 0..<3 {
            let task = Task(title: "작업 \(index)-\(taskIndex)", plannedAt: reference,
                order: Double(index * 3 + taskIndex + 1) * 100,
                createdAt: reference, updatedAt: reference)
            context.insert(task)
            for child in 0..<3 {
                context.insert(TaskChecklistItem(taskId: task.id, title: "체크 \(child)",
                    order: Double(child + 1) * 100, createdAt: reference, updatedAt: reference))
            }
        }
        let date = DayKey.addingDays(-index, to: reference)
        let review = DailyReview(dayKey: DayKey.key(for: date), content: "회고 \(index)",
            createdAt: reference, updatedAt: reference)
        context.insert(review)
        for child in 0..<2 {
            context.insert(DiaryBlock(reviewId: review.id, dayKey: review.dayKey,
                type: .text, text: "블록 \(child)", order: Double(child + 1) * 100,
                createdAt: reference, updatedAt: reference))
        }
    }
    try context.save()
    return container
}
