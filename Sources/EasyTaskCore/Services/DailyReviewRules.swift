import Foundation

public enum DailyReviewRules {
    public static func hasContent(_ review: DailyReview) -> Bool {
        hasContent(
            title: review.title,
            weather: review.weather,
            mood: review.mood,
            content: review.content,
            imageFileNames: review.imageFileNames
        )
    }

    public static func hasContent(
        title: String,
        weather: String = "",
        mood: String = "",
        content: String,
        imageFileNames: [String]
    ) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !weather.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !mood.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !imageFileNames.isEmpty
    }
}
