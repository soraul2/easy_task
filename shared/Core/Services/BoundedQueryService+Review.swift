import Foundation
import SwiftData

extension BoundedQueryService {
    public static func dailyReviewsDescriptor(
        dayKey: String
    ) -> FetchDescriptor<DailyReview> {
        FetchDescriptor(
            predicate: #Predicate<DailyReview> { review in
                review.supersededAt == nil && review.dayKey == dayKey
            },
            sortBy: [
                SortDescriptor(\DailyReview.updatedAt, order: .reverse),
                SortDescriptor(\DailyReview.instanceID, order: .reverse)
            ]
        )
    }

    public static func dailyReviewDescriptor(
        id: UUID
    ) -> FetchDescriptor<DailyReview> {
        var descriptor = FetchDescriptor<DailyReview>(
            predicate: #Predicate<DailyReview> { review in
                review.supersededAt == nil && review.id == id
            }
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    public static func diaryBlocksDescriptor(
        reviewID: UUID
    ) -> FetchDescriptor<DiaryBlock> {
        FetchDescriptor(
            predicate: #Predicate<DiaryBlock> { block in
                block.supersededAt == nil && block.reviewId == reviewID
            },
            sortBy: [SortDescriptor(\DiaryBlock.order)]
        )
    }

    public static func diaryAttachmentsDescriptor(
        reviewID: UUID
    ) -> FetchDescriptor<DiaryAttachment> {
        FetchDescriptor(
            predicate: #Predicate<DiaryAttachment> { attachment in
                attachment.supersededAt == nil && attachment.reviewId == reviewID
            },
            sortBy: [SortDescriptor(\DiaryAttachment.order)]
        )
    }
}
