import Foundation
import SwiftData

/// Value-only configuration for the quiescent startup image migration. A local
/// directory override lets diagnostics use isolated files instead of app data.
@available(watchOS 11, *)
public struct PlanBaseLegacyImageMigrationConfiguration: Sendable {
    public let appSupportFolder: String
    public let imageDirectoryURL: URL?

    public init(appSupportFolder: String, imageDirectoryURL: URL? = nil) {
        self.appSupportFolder = appSupportFolder
        self.imageDirectoryURL = imageDirectoryURL
    }
}

@available(watchOS 11, *)
public struct PlanBaseBootstrapPreparationReport: Equatable, Sendable {
    public let integrity: DataIntegrityService.Report
    public let legacyImages: LegacyDiaryAttachmentMigrationReport?

    public init(
        integrity: DataIntegrityService.Report,
        legacyImages: LegacyDiaryAttachmentMigrationReport? = nil
    ) {
        self.integrity = integrity
        self.legacyImages = legacyImages
    }
}

/// Prepares a container before any app view or external command writer is installed.
/// Only the container and a value report cross actors; the worker owns every model.
@available(watchOS 11, *)
public enum PlanBaseBootstrapService {
    public static func prepare(container: ModelContainer) async throws -> DataIntegrityService.Report {
        try await prepare(container: container, legacyImageMigration: nil).integrity
    }

    public static func prepare(
        container: ModelContainer,
        legacyImageMigration: PlanBaseLegacyImageMigrationConfiguration?
    ) async throws -> PlanBaseBootstrapPreparationReport {
        try await withWorker(container: container) { worker in
            try await worker.prepare(legacyImageMigration: legacyImageMigration)
        }
    }

    /// The app and fault-injection tests share this create-and-invoke boundary.
    /// Creating a ModelActor off main does not guarantee the physical thread of
    /// a later call; keep every worker operation inside the same detached task.
    static func withWorker<Value: Sendable>(
        container: ModelContainer,
        operation: @escaping @Sendable (PlanBaseBootstrapWorker) async throws -> Value
    ) async throws -> Value {
        let preparation = Swift.Task.detached(priority: .userInitiated) {
            let worker = PlanBaseBootstrapWorker(modelContainer: container)
            return try await operation(worker)
        }
        return try await withTaskCancellationHandler {
            try await preparation.value
        } onCancel: {
            preparation.cancel()
        }
    }
}

/// Its private context is isolated by ModelActor. The facade creates and calls
/// this worker inside one detached task to keep startup work off the UI thread.
/// This worker must finish before the UI context or other app command writers are used.
@ModelActor
@available(watchOS 11, *)
actor PlanBaseBootstrapWorker {
    private let createdOnMainThread = Thread.isMainThread

    // Capture raw values on the owning executor, independently of a caller's
    // assertion closure or Swift Testing's diagnostic expression evaluation.
    func executionProbe() -> PlanBaseBootstrapExecutionProbe {
        PlanBaseBootstrapExecutionProbe(
            createdOnMainThread: createdOnMainThread,
            executingOnMainThread: Thread.isMainThread
        )
    }

    func reconcile(
        beforeSave: @Sendable () throws -> Void = {}
    ) throws -> DataIntegrityService.Report {
        try prepare(legacyImageMigration: nil, beforeSave: beforeSave).integrity
    }

    func prepare(
        legacyImageMigration: PlanBaseLegacyImageMigrationConfiguration?,
        now: Date = Date(),
        beforeImageRead: @Sendable () throws -> Void = {},
        beforeSave: @Sendable () throws -> Void = {}
    ) throws -> PlanBaseBootstrapPreparationReport {
        modelContext.autosaveEnabled = false
        let interval = PlanBasePerformanceTrace.begin("StartupIntegrity")
        defer { PlanBasePerformanceTrace.end("StartupIntegrity", interval) }
        do {
            try Swift.Task.checkCancellation()
            // Convergence and image migration share this private context and one
            // commit, with no suspension while the model graph is being changed.
            let report = try DataIntegrityService.reconcile(
                context: modelContext,
                saveChanges: false
            )
            try Swift.Task.checkCancellation()
            let imageReport: LegacyDiaryAttachmentMigrationReport?
            if let legacyImageMigration {
                imageReport = try LegacyDiaryAttachmentMigrationService.migrateInCallerContext(
                    context: modelContext,
                    appSupportFolder: legacyImageMigration.appSupportFolder,
                    now: now,
                    imageDirectoryURL: legacyImageMigration.imageDirectoryURL,
                    saveChanges: false,
                    beforeImageRead: beforeImageRead
                )
            } else {
                imageReport = nil
            }
            try Swift.Task.checkCancellation()
            try beforeSave()
            try Swift.Task.checkCancellation()
            try modelContext.save()
            return PlanBaseBootstrapPreparationReport(integrity: report, legacyImages: imageReport)
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

struct PlanBaseBootstrapExecutionProbe: Sendable {
    let createdOnMainThread: Bool
    let executingOnMainThread: Bool
}
