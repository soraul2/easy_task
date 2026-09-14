import Foundation

public enum MemoRules {
    public static let emptyTitle = "빈 메모"

    public static func mode(for memo: Memo) -> MemoEditorMode {
        MemoEditorMode(rawValue: memo.preferredModeRawValue) ?? .text
    }

    public static func displayTitle(for memo: Memo) -> String {
        let textTitle = displayTitle(for: memo.content)
        guard textTitle == emptyTitle else { return textTitle }
        switch mode(for: memo) {
        case .text:
            return emptyTitle
        case .drawing:
            return "필기 메모"
        case .checklist:
            return "체크리스트"
        }
    }

    public static func systemImage(for memo: Memo) -> String {
        mode(for: memo).systemImage
    }

    public static func displayTitle(for content: String) -> String {
        nonemptyLines(in: content).next() ?? emptyTitle
    }

    /// List previews are bounded independently of the full searchable/editable body.
    public static func preview(for content: String, maximumLength: Int = 240) -> String {
        guard maximumLength > 0 else { return "" }
        let lines = nonemptyLines(in: content)
        guard let title = lines.next() else { return "" }
        var line = lines.next() ?? title
        var result = ""
        while true {
            let prefix = line.prefix(maximumLength - result.count)
            result.append(contentsOf: prefix)
            if prefix.endIndex != line.endIndex { return result + "…" }
            guard let next = lines.next() else { return result }
            guard result.count + 1 < maximumLength else { return result + "…" }
            result += " "
            line = next
        }
    }

    private static func nonemptyLines(in content: String) -> AnyIterator<String> {
        var remaining = content[...]
        return AnyIterator {
            while !remaining.isEmpty {
                let end = remaining.firstIndex(where: \.isNewline) ?? remaining.endIndex
                let line = remaining[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
                remaining = end == remaining.endIndex ? remaining[end...] : remaining[remaining.index(after: end)...]
                if !line.isEmpty { return line }
            }
            return nil
        }
    }

    public static func updatedAtText(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .year()
                .month()
                .day()
                .hour()
                .minute()
                .locale(Locale(identifier: "ko_KR"))
        )
    }

    public static func isBlank(_ content: String) -> Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func matches(_ memo: Memo, query: String) -> Bool {
        matches(memo, checklistTitles: [], query: query)
    }

    public static func matches(
        _ memo: Memo,
        checklistTitles: [String],
        query: String
    ) -> Bool {
        matches(memo, checklistTitles: checklistTitles, normalizedQuery: normalizedSearchText(query))
    }

    static func matches(_ memo: Memo, checklistTitles: [String], normalizedQuery: String) -> Bool {
        guard !normalizedQuery.isEmpty else { return true }
        let searchableText = ([memo.content, displayTitle(for: memo)] + checklistTitles)
            .joined(separator: "\n")
        return normalizedSearchText(searchableText).contains(normalizedQuery)
    }

    public static func sorted(_ memos: [Memo]) -> [Memo] {
        memos
            .filter { $0.supersededAt == nil }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.instanceID.uuidString < $1.instanceID.uuidString
            }
    }

    public static func normalizedSearchText(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
