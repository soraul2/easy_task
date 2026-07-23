import Foundation

public enum DailyReviewWritingPrompt: String, CaseIterable, Identifiable, Sendable {
    case memorableMoment
    case didWell
    case learned
    case nextStep

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .memorableMoment: "기억에 남는 일"
        case .didWell: "잘한 점"
        case .learned: "배운 점"
        case .nextStep: "내일의 한 걸음"
        }
    }
}

public enum DailyReviewWritingRules {
    public static func contains(
        _ prompt: DailyReviewWritingPrompt,
        in content: String
    ) -> Bool {
        content
            .components(separatedBy: .newlines)
            .contains {
                $0.trimmingCharacters(in: .whitespacesAndNewlines) == prompt.title
            }
    }

    public static func appending(
        _ prompt: DailyReviewWritingPrompt,
        to content: String
    ) -> String {
        guard !contains(prompt, in: content) else { return content }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "\(prompt.title)\n"
        }
        return "\(trimmed)\n\n\(prompt.title)\n"
    }
}
