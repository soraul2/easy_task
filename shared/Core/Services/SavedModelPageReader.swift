import Foundation
import SwiftData

struct SavedModelPage<Model: PersistentModel> {
    let rows: [Model]
    // Store offsets count saved identifiers, including excluded pending rows.
    let fetchedCount: Int
}

/// Reads a bounded saved page without refreshing objects that carry pending edits.
/// SwiftData's model fetch with includePendingChanges=false can reload a registered
/// dirty object before a caller gets the chance to exclude its identifier.
@MainActor
enum SavedModelPageReader {
    static func read<Model: PersistentModel>(
        _ source: FetchDescriptor<Model>,
        in context: ModelContext,
        excluding identifiers: Set<PersistentIdentifier> = []
    ) throws -> SavedModelPage<Model> {
        var descriptor = source
        descriptor.includePendingChanges = false
        let deleted = Set(context.deletedModelsArray.compactMap {
            ($0 as? Model)?.persistentModelID
        })
        let excluded = identifiers.union(deleted)

        // A clean context has no editor state for a saved-model fetch to overwrite.
        // Keep its original batched fetch cost; a dirty context uses IDs only.
        if !context.hasChanges {
            let fetched = try context.fetch(descriptor)
            return SavedModelPage(
                rows: fetched.filter { !excluded.contains($0.persistentModelID) },
                fetchedCount: fetched.count
            )
        }

        let savedIDs = try context.fetchIdentifiers(descriptor)
        let pendingIDs = Set((context.insertedModelsArray + context.changedModelsArray)
            .compactMap { ($0 as? Model)?.persistentModelID })
        let cleanIDs = savedIDs.filter {
            !excluded.contains($0) && !pendingIDs.contains($0)
        }
        if !cleanIDs.isEmpty {
            // ID enumeration does not refresh an already registered clean model
            // after another context saves. Hydrate only this saved page's clean
            // objects; dirty objects must never enter a saved-only model fetch.
            var hydration = descriptor
            hydration.predicate = #Predicate<Model> { cleanIDs.contains($0.persistentModelID) }
            hydration.fetchOffset = nil
            hydration.fetchLimit = cleanIDs.count
            hydration.sortBy = []
            _ = try context.fetch(hydration)
        }
        let rows: [Model] = savedIDs.compactMap { identifier in
            guard !excluded.contains(identifier) else { return nil }
            let registered: Model? = context.registeredModel(for: identifier)
            return registered ?? (context.model(for: identifier) as? Model)
        }
        return SavedModelPage(rows: rows, fetchedCount: savedIDs.count)
    }
}
