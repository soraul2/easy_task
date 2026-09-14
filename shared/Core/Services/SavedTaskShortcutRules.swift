import Foundation

public enum SavedTaskShortcutRules {
    public enum Failure: LocalizedError {
        case invalidAlias, duplicateAlias(String), unknownAlias, ambiguousAlias, selectionRequired

        public var errorDescription: String? {
            switch self {
            case .invalidAlias: "입력어는 문자·숫자·밑줄·하이픈으로 1~24자 입력해 주세요."
            case .duplicateAlias(let alias): "‘/\(alias)’ 입력어는 다른 작업이 사용하고 있어요."
            case .unknownAlias: "일치하는 입력어가 없어요. 입력어를 확인하거나 후보를 선택해 주세요."
            case .ambiguousAlias: "같은 입력어를 쓰는 작업이 여러 개예요. 추가할 작업을 선택하고 입력어를 수정해 주세요."
            case .selectionRequired: "추가할 작업을 선택하거나 입력어를 끝까지 입력해 주세요."
            }
        }
    }

    public static func normalizedAlias(_ value: String?) throws -> String? {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("/") { text.removeFirst() }
        text = canonical(text)
        let allowed = CharacterSet.alphanumerics.union(.nonBaseCharacters).union(CharacterSet(charactersIn: "_-"))
        guard !text.isEmpty, text.count <= 24,
              text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { throw Failure.invalidAlias }
        return text
    }

    public static func query(in input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("/") else { return nil }
        return canonical(String(text.dropFirst()))
    }

    public static func aliasKey(_ value: String?) -> String? { try? normalizedAlias(value) }

    public static func suggestions(_ entries: [SavedTaskEntry], input: String) -> [SavedTaskEntry] {
        guard let query = query(in: input) else { return [] }
        let candidates: [(entry: SavedTaskEntry, isExact: Bool)] = entries.compactMap { entry in
            let alias = query.isEmpty ? nil : aliasKey(entry.quickEntryAlias)
            guard query.isEmpty || alias?.contains(query) == true ||
                entry.draft.title.localizedStandardContains(query) else { return nil }
            return (entry, !query.isEmpty && alias == query)
        }
        return candidates.sorted {
            if $0.isExact != $1.isExact { return $0.isExact }
            if $0.entry.isFavorite != $1.entry.isFavorite { return $0.entry.isFavorite }
            let comparison = $0.entry.draft.title.localizedStandardCompare($1.entry.draft.title)
            return comparison == .orderedSame
                ? $0.entry.id.uuidString < $1.entry.id.uuidString : comparison == .orderedAscending
        }.map(\.entry)
    }

    public static func exactMatch(in entries: [SavedTaskEntry], input: String) throws -> UUID {
        guard let query = query(in: input), !query.isEmpty else { throw Failure.selectionRequired }
        let matches = entries.filter { aliasKey($0.quickEntryAlias) == query }
        guard matches.count <= 1 else { throw Failure.ambiguousAlias }
        guard let entry = matches.first else { throw Failure.unknownAlias }
        return entry.id
    }

    private static func canonical(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
