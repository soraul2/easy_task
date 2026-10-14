import Foundation
import Observation
import SwiftData

/// Owns one startup across app scenes. No UI or command writer receives the
/// container until its background integrity and image transaction has committed.
@MainActor
@Observable
@available(watchOS 11, *)
public final class PlanBaseStartupSession {
    public enum State {
        case opening
        case ready(ModelContainer, ModelContext)
        case failed(String)
    }

    public private(set) var state: State = .opening
    public private(set) var attempt = 0
    public private(set) var legacyImageMigrationReport: LegacyDiaryAttachmentMigrationReport?
    public private(set) var pendingOpenURLRevision = 0
    @ObservationIgnored private var pendingOpenURLs: [URL] = []
    @ObservationIgnored private var inFlight: Swift.Task<Void, Never>?
    @ObservationIgnored private var importObserver: StartupImportObserver?
    @ObservationIgnored private var importRevision = 0
    @ObservationIgnored private var reconciledImportRevision = 0
    @ObservationIgnored private var latestImport: CloudKitSyncEventSummary?
    @ObservationIgnored private let prepareContainer:
        @MainActor (ModelContainer, PlanBaseLegacyImageMigrationConfiguration?) async throws
            -> PlanBaseBootstrapPreparationReport

    public init() {
        prepareContainer = { container, configuration in
            try await PlanBaseBootstrapService.prepare(
                container: container, legacyImageMigration: configuration
            )
        }
    }

    init(prepare: @escaping @MainActor (
        ModelContainer, PlanBaseLegacyImageMigrationConfiguration?
    ) async throws -> PlanBaseBootstrapPreparationReport) {
        prepareContainer = prepare
    }

    public func load(
        open: @escaping @MainActor () async throws -> ModelContainer,
        // Explicit diagnostic probes supply their own integrity sequencing.
        performIntegrity: Bool = true,
        legacyImageMigration: PlanBaseLegacyImageMigrationConfiguration? = nil,
        onReady: @escaping @MainActor (ModelContainer, ModelContext) -> Void = { _, _ in }
    ) async {
        if let inFlight {
            await inFlight.value
            return
        }
        guard case .opening = state else { return }
        observeImports()
        let startup = Swift.Task { @MainActor in
            defer { inFlight = nil }
            do {
                let container = try await open()
                var imageReport: LegacyDiaryAttachmentMigrationReport?
                if performIntegrity {
                    repeat {
                        let revision = importRevision
                        let report = try await prepareContainer(container, legacyImageMigration)
                        if let latest = report.legacyImages {
                            // Imports can add new legacy references during startup.
                            // Count every committed import, retaining only the last
                            // pass's current unresolved files for the root warning.
                            imageReport = LegacyDiaryAttachmentMigrationReport(
                                importedCount: (imageReport?.importedCount ?? 0) + latest.importedCount,
                                missingFileNames: latest.missingFileNames,
                                rejectedFileNames: latest.rejectedFileNames,
                                deferredFileNames: latest.deferredFileNames
                            )
                        }
                        reconciledImportRevision = revision
                    } while importRevision != reconciledImportRevision
                }
                legacyImageMigrationReport = imageReport
                // Legacy restore may have registered models in mainContext. A
                // new UI context starts from the committed bootstrap graph.
                let context = ModelContext(container)
                context.autosaveEnabled = true
                onReady(container, context)
                state = .ready(container, context)
            } catch {
                importObserver = nil
                legacyImageMigrationReport = nil
                state = .failed(error.localizedDescription)
            }
        }
        inFlight = startup
        await startup.value
    }

    public func retry() {
        guard inFlight == nil else { return }
        importObserver = nil
        latestImport = nil
        importRevision = 0
        reconciledImportRevision = 0
        legacyImageMigrationReport = nil
        state = .opening
        attempt &+= 1
    }

    /// The app's always-mounted handler preserves routes across opening,
    /// recovery, and the ready/view handoff. Only URL values enter this buffer.
    public func recordOpenURL(_ url: URL) {
        pendingOpenURLs.append(url)
        pendingOpenURLRevision &+= 1
    }

    /// A ready root drains each route once. Cancelled scene tasks and retries
    /// do not discard routes before the prepared model context is available.
    public func takePendingOpenURLs() -> [URL] {
        guard case .ready = state else { return [] }
        defer { pendingOpenURLs.removeAll() }
        return pendingOpenURLs
    }

    /// Called by the root's task after its import listener is installed. Events
    /// during the ready/view handoff are handled directly, without reposting them.
    public func takePendingImport() -> CloudKitSyncEventSummary? {
        importObserver = nil
        defer { latestImport = nil }
        return importRevision != reconciledImportRevision ? latestImport : nil
    }

    func recordImport(_ summary: CloudKitSyncEventSummary) {
        guard CloudKitSyncService.shouldReconcile(after: summary) else { return }
        importRevision &+= 1
        latestImport = summary
    }

    private func observeImports() {
        guard importObserver == nil else { return }
        let token = NotificationCenter.default.addObserver(
            forName: CloudKitSyncService.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] notification in
            nonisolated(unsafe) let mainNotification = notification
            MainActor.assumeIsolated {
                guard let self,
                      let summary = CloudKitSyncService.summary(from: mainNotification) else { return }
                self.recordImport(summary)
            }
        }
        importObserver = StartupImportObserver(token)
    }
}

private final class StartupImportObserver: @unchecked Sendable {
    private let token: any NSObjectProtocol
    init(_ token: any NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}
