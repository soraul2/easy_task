import Foundation
import SwiftData

extension BoundedQueryService {
static func deduplicated<Model, Key: Hashable>(
        _ models: [Model],
        by keyPath: KeyPath<Model, Key>
    ) -> [Model] {
        var seen: Set<Key> = []
        return models.filter { seen.insert($0[keyPath: keyPath]).inserted }
    }

    @MainActor
    static func fetchInBatches<Model: PersistentModel>(
        _ sourceDescriptor: FetchDescriptor<Model>,
        in context: ModelContext,
        isCancelled: () -> Bool
    ) throws -> [Model] {
        var offset = 0
        var results: [Model] = []

        while true {
            if isCancelled() { throw CancellationError() }
            var descriptor = sourceDescriptor
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = taskHistoryStatisticsBatchSize
            let batch = try context.fetch(descriptor)
            results.append(contentsOf: batch)
            guard batch.count == taskHistoryStatisticsBatchSize else { break }
            offset += batch.count
        }
        return results
    }
}
