import SwiftData

public enum PersistenceCommandService {
    @MainActor
    @discardableResult
    public static func perform<Result>(
        in context: ModelContext,
        _ mutation: () throws -> Result
    ) throws -> Result {
        // Preserve unrelated pending edits before establishing this command's rollback point.
        try context.save()

        do {
            let result = try mutation()
            try context.save()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }
}
