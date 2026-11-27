#if DEBUG
import Foundation
import SwiftData

/// Opt-in, isolated local stores let UI tests verify a real process restart.
/// This path is never used by a normal launch and never enables CloudKit.
@available(watchOS 11, *)
public enum MemoUITestSupport {
    @MainActor
    public static func makeContainer(arguments: [String]) throws -> ModelContainer {
        let container: ModelContainer
        let prefix = "--ui-testing-memo-store="
        if arguments.contains("--ui-testing"),
           let argument = arguments.first(where: { $0.hasPrefix(prefix) }),
           let id = UUID(uuidString: String(argument.dropFirst(prefix.count))) {
            let directory = URL.cachesDirectory.appendingPathComponent("PlanBaseMemoUITests")
                .appendingPathComponent(id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            container = try PlanBaseContainerFactory.makePersistent(
                storeURL: directory.appendingPathComponent("memo.store"), mode: .local
            )
        } else {
            container = try PlanBaseContainerFactory.makeInMemory()
        }
        if arguments.contains("--ui-testing"), arguments.contains("--ui-testing-legacy-memo") {
            try seedLegacyMemo(in: container.mainContext)
        }
        if arguments.contains("--ui-testing"), arguments.contains("--ui-testing-legacy-drawing-only") {
            try seedLegacyDrawingMemo(in: container.mainContext)
        }
        return container
    }

    @MainActor
    static func seedLegacyMemo(in context: ModelContext) throws {
        // Identify the fixture by a stable ID, not editable content. Relaunching
        // the same isolated store must preserve edits without inserting a copy.
        let id = UUID(uuidString: "653C16A4-EC27-4E12-92B4-74B050DDA0E1")!
        var descriptor = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }
        try PersistenceCommandService.perform(in: context) {
            context.insert(Memo(id: id, content: "기존 복합 메모"))
            context.insert(MemoChecklistItem(memoId: id, title: "기존 체크 항목", order: 100))
            context.insert(MemoDrawing(memoId: id, drawingData: legacyDrawingData))
        }
    }

    @MainActor
    static func seedLegacyDrawingMemo(in context: ModelContext) throws {
        let id = UUID(uuidString: "1B12AE03-748E-4F76-A1E9-7DF4C524E48B")!
        var descriptor = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }
        try PersistenceCommandService.perform(in: context) {
            context.insert(Memo(id: id, content: "", preferredMode: .drawing))
            context.insert(MemoDrawing(memoId: id, drawingData: legacyDrawingData))
        }
    }

    // A real, four-point PencilKit pen stroke. Keeping the encoded fixture here
    // avoids adding PencilKit to the shared package or requiring a writable canvas.
    private static let legacyDrawingData = Data(base64Encoded:
        "d3Jk8AEACAASEAAAAAAAAAAAAAAAAAAAAAASEAfaeTDhk0GjiucvizFDvcoaBggAEAAYABoGCAEQARgBIjQKFA0AAAAAFYmICD8dAACAPyUAAIA/EhFjb20uYXBwbGUuaW5rLnBlbhgDQQAAAAAAAAAAKrMBChB7N88vBeBF5rQswFN5DUAVEgYIABABGAEaBggAEAEYACAAKnAKEMn7TNZCGUFdqx8uelK09owRAAAAQOQnzcEYBCADKPwfMhoAAKBA6AMAAOgD/38AAP9/AACgQAAAAAAAADowAADwQQAANEIAAAAAAADIQgAAyELNzMw9AAA+QwAAXELNzEw+AACCQwAA8EKamZk+MhQNAADQQRUAACRCHQAAbkMlAACmQkCAybKvwQU6BggAEAAYAEIQQ3OWLcdmQvOpUwC5Ptn5eg=="
    )!
}
#endif
