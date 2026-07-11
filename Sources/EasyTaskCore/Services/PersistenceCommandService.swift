import Foundation
import SwiftData

public enum PersistenceCommandService {
    public static let dataChangedNotification = Notification.Name(
        "EasyTaskPersistenceDataChanged"
    )

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
            NotificationCenter.default.post(
                name: dataChangedNotification,
                object: context
            )
            return result
        } catch {
            context.rollback()
            throw error
        }
    }
}
