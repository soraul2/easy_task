import Foundation
import SwiftData

enum MemoReadInvalidated: Error { case changed }

/// Values only; neither revisions nor pending edits are inferred from row IDs alone.
struct MemoReadVersion: Equatable {
    let revision: Int
    let additionalRevision: Int
    let locale: String
    let pending: [PersistentIdentifier: MemoPendingReadValue]
}

struct MemoPendingReadValue: Equatable {
    let roles: Int
    let kind: Int
    let id: UUID
    let instanceID: UUID
    let memoID: UUID?
    let text: String
    let mode: String
    let pinned: Bool
    let completed: Bool
    let orderBits: UInt64
    let completedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let supersededAt: Date?
}

@MainActor
final class MemoReadValidity {
    private let context: ModelContext
    private let changes: PersistenceViewRevision
    private let additionalRevision: @MainActor () -> Int

    init(context: ModelContext, additionalRevision: @escaping @MainActor () -> Int = { 0 }) {
        self.context = context
        changes = PersistenceViewRevision(context: context, domains: .memos)
        self.additionalRevision = additionalRevision
    }

    func capture() -> MemoReadVersion {
        var roles: [PersistentIdentifier: Int] = [:]
        let groups = [(context.insertedModelsArray, 1), (context.changedModelsArray, 2),
                      (context.deletedModelsArray, 4)]
        for (models, role) in groups {
            for model in models {
                roles[model.persistentModelID, default: 0] |= role
            }
        }
        var pending: [PersistentIdentifier: MemoPendingReadValue] = [:]
        for (models, _) in groups {
            for model in models {
                let role = roles[model.persistentModelID] ?? 0
                let value: MemoPendingReadValue
                switch model {
                case let memo as Memo:
                    value = MemoPendingReadValue(roles: role, kind: 0, id: memo.id,
                        instanceID: memo.instanceID, memoID: nil, text: memo.content,
                        mode: memo.preferredModeRawValue, pinned: memo.isPinned, completed: false,
                        orderBits: 0, completedAt: nil, createdAt: memo.createdAt,
                        updatedAt: memo.updatedAt, supersededAt: memo.supersededAt)
                case let item as MemoChecklistItem:
                    value = MemoPendingReadValue(roles: role, kind: 1, id: item.id,
                        instanceID: item.instanceID, memoID: item.memoId, text: item.title,
                        mode: "", pinned: false, completed: item.isCompleted,
                        orderBits: item.order.bitPattern, completedAt: item.completedAt,
                        createdAt: item.createdAt, updatedAt: item.updatedAt, supersededAt: item.supersededAt)
                case let drawing as MemoDrawing:
                    // The list uses drawing existence/revision, never its original canvas bytes.
                    value = MemoPendingReadValue(roles: role, kind: 2, id: drawing.id,
                        instanceID: drawing.instanceID, memoID: drawing.memoId, text: "", mode: "",
                        pinned: false, completed: false, orderBits: 0, completedAt: nil,
                        createdAt: drawing.createdAt, updatedAt: drawing.updatedAt, supersededAt: drawing.supersededAt)
                default: continue
                }
                pending[model.persistentModelID] = value
            }
        }
        return MemoReadVersion(revision: changes.value, additionalRevision: additionalRevision(),
                               locale: Locale.current.identifier, pending: pending)
    }
}

@MainActor
struct MemoReadCheckpoint {
    let body: @MainActor () async throws -> Void
    func callAsFunction() async throws { try await body() }
}

typealias MemoCooperativePageLoader = @MainActor (
    ModelContext, String, MemoQueryCursor?, MemoReadCheckpoint
) async throws -> MemoQueryPage

@MainActor
struct MemoCooperativeReadResult {
    var memos: [Memo]
    var summaries: [UUID: MemoListSummary]
    var nextCursor: MemoQueryCursor?
    var hasMore: Bool
    var depth: Int
    var version: MemoReadVersion
}

@MainActor
enum MemoCooperativeRead {
    static func run(context: ModelContext, query: String, targetDepth: Int,
                    appendTo published: MemoCooperativeReadResult?, validity: MemoReadValidity,
                    loader: MemoCooperativePageLoader) async throws -> MemoCooperativeReadResult {
        while true {
            try Swift.Task.checkCancellation()
            let version = validity.capture()
            let checkpoint = MemoReadCheckpoint {
                try Swift.Task.checkCancellation()
                await Swift.Task.yield()
                try Swift.Task.checkCancellation()
                guard validity.capture() == version else { throw MemoReadInvalidated.changed }
            }
            // A cursor belongs to the whole published read version, including unsaved values.
            let canAppend = published?.version == version
            var rows = canAppend ? (published?.memos ?? []) : []
            var summaries = canAppend ? (published?.summaries ?? [:]) : [:]
            var cursor = canAppend ? published?.nextCursor : nil
            var pages = canAppend ? (published?.depth ?? 0) : 0
            var more = true
            var seen = Set(rows.map(\.instanceID))
            do {
                for _ in 0..<(canAppend ? 1 : targetDepth) {
                    try await checkpoint()
                    let page = try await loader(context, query, cursor, checkpoint)
                    try await checkpoint()
                    rows += page.memos.filter { seen.insert($0.instanceID).inserted }
                    summaries.merge(page.summaries) { _, new in new }
                    cursor = page.nextCursor
                    more = page.hasMore
                    pages += 1
                    if !more { break }
                }
                try await checkpoint()
                return MemoCooperativeReadResult(memos: rows, summaries: summaries, nextCursor: cursor,
                    hasMore: more, depth: pages, version: version)
            } catch is MemoReadInvalidated {
                // Discard every accumulated page/offset and re-normalize the raw query.
                continue
            } catch {
                try Swift.Task.checkCancellation()
                // An error from a superseded snapshot must not hide a current successful read.
                if validity.capture() != version { continue }
                throw error
            }
        }
    }
}
