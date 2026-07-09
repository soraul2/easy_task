import Foundation
import SwiftData

public enum DailyReviewService {
    @discardableResult
    public static func save(
        review existingReview: DailyReview?,
        dayKey: String,
        title: String = "",
        weather: String = "",
        mood: String = "",
        content: String,
        imageFileNames: [String] = [],
        in context: ModelContext,
        forceCreate: Bool = false,
        now: Date = Date()
    ) -> DailyReview? {
        guard let date = DayKey.date(from: dayKey), DayKey.key(for: date) == dayKey else {
            return nil
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWeather = weather.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMood = mood.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedImageFileNames = imageFileNames.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let reusableReview: DailyReview?
        if let existingReview, existingReview.supersededAt == nil {
            reusableReview = existingReview
        } else {
            let descriptor = FetchDescriptor<DailyReview>(
                predicate: #Predicate {
                    $0.dayKey == dayKey && $0.supersededAt == nil
                }
            )
            reusableReview = try? context.fetch(descriptor).min {
                $0.instanceID.uuidString < $1.instanceID.uuidString
            }
        }

        guard reusableReview != nil || forceCreate || DailyReviewRules.hasContent(
            title: trimmedTitle,
            weather: trimmedWeather,
            mood: trimmedMood,
            content: trimmedContent,
            imageFileNames: normalizedImageFileNames
        ) else {
            return nil
        }

        let review: DailyReview
        if let reusableReview {
            review = reusableReview
        } else {
            review = DailyReview(dayKey: dayKey, content: "")
            context.insert(review)
        }

        review.dayKey = dayKey
        review.title = trimmedTitle
        review.weather = trimmedWeather
        review.mood = trimmedMood
        review.content = trimmedContent
        review.imageFileNames = normalizedImageFileNames
        review.updatedAt = now
        syncBlocks(for: review, in: context)
        return review
    }

    public static func blocks(for review: DailyReview, in blocks: [DiaryBlock]) -> [DiaryBlock] {
        blocks
            .filter { $0.supersededAt == nil && $0.reviewId == review.id }
            .sorted { $0.order < $1.order }
    }

    @discardableResult
    public static func migrateBlockSummaryIfNeeded(
        for review: DailyReview,
        blocks: [DiaryBlock],
        now: Date = Date()
    ) -> Bool {
        let reviewBlocks = self.blocks(for: review, in: blocks)
        guard !reviewBlocks.isEmpty else { return false }

        let blockContent = reviewBlocks
            .filter { $0.type == DiaryBlockType.text.rawValue }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let blockImageFileNames = reviewBlocks
            .filter { $0.type == DiaryBlockType.image.rawValue }
            .compactMap(\.imageFileName)

        var didMigrate = false
        if review.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !blockContent.isEmpty {
            review.content = blockContent
            didMigrate = true
        }
        if review.imageFileNames.isEmpty, !blockImageFileNames.isEmpty {
            review.imageFileNames = blockImageFileNames
            didMigrate = true
        }
        if didMigrate {
            review.updatedAt = now
        }
        return didMigrate
    }

    public static func syncBlocks(for review: DailyReview, in context: ModelContext) {
        let existingBlocks = (try? context.fetch(FetchDescriptor<DiaryBlock>())) ?? []
        for block in existingBlocks where block.reviewId == review.id {
            context.delete(block)
        }

        var nextOrder: Double = 100
        let trimmedContent = review.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContent.isEmpty {
            context.insert(DiaryBlock(
                reviewId: review.id,
                dayKey: review.dayKey,
                type: .text,
                text: trimmedContent,
                order: nextOrder
            ))
            nextOrder += 100
        }

        for fileName in review.imageFileNames {
            context.insert(DiaryBlock(
                reviewId: review.id,
                dayKey: review.dayKey,
                type: .image,
                imageFileName: fileName,
                order: nextOrder
            ))
            nextOrder += 100
        }
    }
}
