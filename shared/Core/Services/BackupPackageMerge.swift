import CryptoKit
import Foundation
import SwiftData

public struct LegacyJSONMergeReport: Equatable, Sendable {
    public var merge: BackupPackageMergeReport
    public var referencedImageFileNames: [String]

    public init(
        merge: BackupPackageMergeReport,
        referencedImageFileNames: [String]
    ) {
        self.merge = merge
        self.referencedImageFileNames = referencedImageFileNames
    }
}
public extension BackupPackageCodec {
    @MainActor
    @discardableResult
    static func restoreMerging(
        _ contents: BackupPackageContents,
        into context: ModelContext
    ) throws -> BackupPackageMergeReport {
        try restoreMerging(contents, into: context, beforeFinalSave: {})
    }

    @MainActor
    @discardableResult
    static func restoreLegacyJSONMerging(
        _ source: BackupPayload,
        into context: ModelContext
    ) throws -> LegacyJSONMergeReport {
        let payload = try normalizedLegacyPayload(source)
        try BackupCodec.validate(payload)
        try context.save()
        var report = BackupPackageMergeReport()
        do {
            _ = try DataIntegrityService.reconcile(context: context, saveChanges: false)
            try mergeEvents(payload.calendarEvents, context: context, report: &report)
            try mergeTemplates(payload.taskTemplates, context: context, report: &report)
            try mergeTemplateItems(payload.taskTemplateItems, context: context, report: &report)
            try mergePlacements(payload.templatePlacements ?? [], context: context, report: &report)
            try mergeTasks(
                payload.tasks,
                sourceFormatVersion: nil,
                context: context,
                report: &report
            )
            try mergeChecklistItems(
                payload.taskChecklistItems ?? [],
                context: context,
                report: &report
            )
            try mergeReviews(
                payload.dailyReviews ?? [],
                context: context,
                report: &report,
                preserveLegacyImages: true
            )
            try mergeDiaryBlocks(
                payload.diaryBlocks ?? [],
                context: context,
                report: &report,
                preserveLegacyImages: true
            )
            try mergeMemos(payload.memos ?? [], context: context, report: &report)
            _ = try DataIntegrityService.reconcile(context: context, saveChanges: false)
            try validateFinalAttachmentCounts(context: context)
            try context.save()

            let reviewNames = (payload.dailyReviews ?? []).flatMap { $0.imageFileNames ?? [] }
            let blockNames = (payload.diaryBlocks ?? []).compactMap(\.imageFileName)
            return LegacyJSONMergeReport(
                merge: report,
                referencedImageFileNames: Array(Set(reviewNames + blockNames)).sorted()
            )
        } catch {
            context.rollback()
            throw error
        }
    }
}

extension BackupPackageCodec {
    @MainActor
    @discardableResult
    static func restoreMerging(
        _ contents: BackupPackageContents,
        into context: ModelContext,
        beforeFinalSave: () throws -> Void
    ) throws -> BackupPackageMergeReport {
        try validate(contents)
        // Persist pending edits as the rollback baseline before package mutations begin.
        try context.save()
        var report = BackupPackageMergeReport()
        do {
            _ = try DataIntegrityService.reconcile(context: context, saveChanges: false)
            let payload = contents.records.payload
            try mergeEvents(payload.calendarEvents, context: context, report: &report)
            try mergeTemplates(payload.taskTemplates, context: context, report: &report)
            try mergeTemplateItems(payload.taskTemplateItems, context: context, report: &report)
            try mergePlacements(payload.templatePlacements ?? [], context: context, report: &report)
            try mergeTasks(
                payload.tasks,
                sourceFormatVersion: contents.records.formatVersion,
                context: context,
                report: &report
            )
            try mergeChecklistItems(
                payload.taskChecklistItems ?? [],
                context: context,
                report: &report
            )
            try mergeReviews(payload.dailyReviews ?? [], context: context, report: &report)
            try mergeDiaryBlocks(payload.diaryBlocks ?? [], context: context, report: &report)
            try mergeMemos(payload.memos ?? [], context: context, report: &report)
            try mergeAttachments(contents, context: context, report: &report)
            _ = try DataIntegrityService.reconcile(context: context, saveChanges: false)
            try validateImportedAttachmentRelativeOrder(contents, context: context)
            try validateFinalAttachmentCounts(context: context)
            try beforeFinalSave()
            try context.save()
            return report
        } catch {
            context.rollback()
            throw error
        }
    }
}
