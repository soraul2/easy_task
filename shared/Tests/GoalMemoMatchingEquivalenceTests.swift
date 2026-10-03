import Foundation
import Testing
@testable import EasyTaskCore

/// Freeze the current folding/join/trim semantics before changing the matcher.
/// The optional range probe reports differences; it does not require that candidate to match.
@Test
@MainActor
func goalMemoMatchingPreservesFrozenSearchSemantics() throws {
    try goalMemoMatchingCompare(probeEnabled: false)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PLANBASE_GOAL_MEMO_MATCHING_PROBE"] == "1"))
@MainActor
func goalMemoMatchingRangeProbe() throws {
    try goalMemoMatchingCompare(probeEnabled: true)
}

@MainActor
private func goalMemoMatchingCompare(probeEnabled: Bool) throws {
    var currentLocaleComparisons = 0
    var rangeComparisons = 0
    var rangeDifferenceCount = 0
    var examples: [[String: Any]] = []

    for fixture in goalMemoMatchingFixtures {
        let memo = Memo(content: fixture.content, preferredMode: fixture.mode)
        for query in fixture.queries {
            let expected = goalMemoFrozenMatches(
                memo, checklistTitles: fixture.checklistTitles, query: query, locale: .current
            )
            let actual = MemoRules.matches(memo, checklistTitles: fixture.checklistTitles, query: query)
            #expect(actual == expected, "Frozen matcher differs: \(fixture.name), query=\(String(reflecting: query))")
            currentLocaleComparisons += 1

            guard probeEnabled else { continue }
            // Explicit locale probes are test-only: the product still uses Locale.current.
            for locale in [Locale.current, Locale(identifier: "en_US_POSIX"),
                           Locale(identifier: "tr_TR"), Locale(identifier: "de_DE")] {
                let reference = goalMemoFrozenMatches(
                    memo, checklistTitles: fixture.checklistTitles, query: query, locale: locale
                )
                let candidate = goalMemoRangeProbeMatches(
                    memo, checklistTitles: fixture.checklistTitles, query: query, locale: locale
                )
                rangeComparisons += 1
                guard reference != candidate else { continue }
                rangeDifferenceCount += 1
                if examples.count < 24 {
                    examples.append([
                        "fixture": fixture.name, "locale": locale.identifier,
                        "query": query, "content": fixture.content,
                        "checklistTitles": fixture.checklistTitles,
                        "preferredMode": fixture.mode.rawValue,
                        "frozenMatches": reference, "rangeMatches": candidate,
                    ])
                }
            }
        }
    }

    if probeEnabled {
        let report: [String: Any] = [
            "currentLocale": Locale.current.identifier,
            "productionReferenceComparisons": currentLocaleComparisons,
            "rangeProbeComparisons": rangeComparisons,
            "rangeDifferenceCount": rangeDifferenceCount,
            "maximumExamples": 24,
            "examples": examples,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print("GOAL_MEMO_MATCHING_RANGE_PROBE \(String(decoding: data, as: UTF8.self))")
    }
}

private struct GoalMemoMatchingFixture: Sendable {
    let name: String
    let content: String
    let mode: MemoEditorMode
    let checklistTitles: [String]
    let queries: [String]

    init(_ name: String, content: String, mode: MemoEditorMode = .text,
         checklist: [String] = [], queries: [String]) {
        self.name = name
        self.content = content
        self.mode = mode
        checklistTitles = checklist
        self.queries = queries
    }
}

private let goalMemoMatchingFixtures: [GoalMemoMatchingFixture] = [
    .init("composed-decomposed-accents",
          content: "\n Café 준비 \nCafe\u{301} 원두\nÅngström · A\u{30A}ngstro\u{308}m",
          queries: ["CAFE", "café", "Cafe\u{301}", " 준비 ", "angstrom", "ÅNGSTRÖM",
                    "\u{301}", "없는말", "", " \t\r\n"]),
    .init("full-width-katakana",
          content: "ＡＢＣ １２３\nｶﾀｶﾅ · カタカナ\n전각 Ｆｏｃｕｓ",
          queries: ["abc", "ＡＢＣ", "123", "１２３", "ｶﾀｶﾅ", "カタカナ", "focus", "ＦＯＣＵＳ"]),
    .init("ligatures-sharp-s",
          content: "Straße · STRAẞE\nﬁle · ﬂow · oﬃce\nœuvre · æther",
          queries: ["strasse", "straße", "STRAẞE", "ss", "ß", "ẞ", "file", "ﬁle",
                    "flow", "ﬂow", "office", "oﬃce", "oeuvre", "œuvre", "aether", "æther"]),
    .init("turkish-case",
          content: "İstanbul\nIĞDIR · ı · i · I · İ\nışık · İZMİR",
          queries: ["istanbul", "İSTANBUL", "Istanbul", "ıstanbul", "igdir", "ığdır",
                    "I", "i", "ı", "İ", "isik", "ışık", "izmir", "İZMİR"]),
    .init("greek-sigma",
          content: "Σίσυφος\nΟΣ · ος · οσ · Σ · ς · σ",
          queries: ["σισυφος", "ΣΊΣΥΦΟΣ", "ος", "οσ", "ΟΣ", "σ", "ς", "Σ"]),
    .init("korean-composition",
          content: "감사 계획\n감사 계획\n한글 · 한글",
          queries: ["감사", "감사", "계획", "한글", "한글", "감", "감", "ᄀ"]),
    .init("emoji-grapheme-parts",
          content: "가족 👨‍👩‍👧‍👦\n👍🏽 · 👩‍💻 · 🏳️‍🌈 · 🇰🇷 · ❤️",
          queries: ["👨‍👩‍👧‍👦", "👩", "👧", "\u{200D}", "👍🏽", "👍", "🏽",
                    "👩‍💻", "💻", "🏳️‍🌈", "🏳", "\u{FE0F}", "🇰🇷", "🇰", "❤️", "❤"]),
    .init("newline-field-boundaries",
          content: "Head\nTail", checklist: ["Check One", "Check Two"],
          queries: ["head\ntail", "tail\nhead", "head\ncheck one", "one\ncheck two",
                    "head\nhead", "head tail", "tail\ncheck", "check one\ncheck two",
                    " \nTail\nHead\t ", "\n", "Tail\nHead\nCheck One"]),
    .init("crlf-other-newlines",
          content: "\r\n\t Title \u{000B}Body\u{2028}Last\u{2029}End\r\n",
          checklist: ["Child\r\nPart"],
          queries: ["title", "body", "last", "end", "child\r\npart", "child\npart",
                    "title \u{000B}body", "last\u{2029}end", "\u{2028}", "\u{000B}"]),
    .init("query-trim",
          content: "\u{00A0}제목\u{00A0}\n 본문 끝 \t", checklist: ["  체크 항목  "],
          queries: [" 제목 ", "\t본문 끝\n", "\u{00A0}체크 항목\u{00A0}",
                    "본문  끝", "체크\t항목", "\u{200B}", "", "\u{00A0}", " \n\t"]),
    .init("auto-title-empty-text", content: " \r\n\t",
          queries: ["빈 메모", "메모", "필기", "", " \n"]),
    .init("auto-title-empty-drawing", content: "\n", mode: .drawing,
          queries: ["필기 메모", "빈 메모", "메모", "필기", "", "\t"]),
    .init("auto-title-empty-checklist", content: " \n", mode: .checklist,
          checklist: ["Only Café Child", "두 번째 항목"],
          queries: ["체크리스트", "빈 메모", "only cafe child", "두 번째", "child\n두",
                    "체크리스트\nonly", " \n "]),
    .init("text-title-overrides-preference", content: "제목\n본문", mode: .drawing,
          checklist: ["체크 전용"],
          queries: ["제목", "필기 메모", "체크 전용", "본문\n제목", "제목\n체크"]),
    .init("literal-empty-title-sentinel", content: "빈 메모\n본문", mode: .drawing,
          checklist: ["자식"],
          queries: ["빈 메모", "필기 메모", "본문\n필기 메모", "필기 메모\n자식"]),
    .init("blank-checklist-fields", content: "", mode: .checklist,
          checklist: ["", " \t", "마지막"],
          queries: ["체크리스트", "마지막", "리스트\n\n \t\n마", "리스트\n마",
                    "", "\t", "없는말"]),
]

private func goalMemoFrozenSearchText(_ value: String, locale: Locale) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Intentionally independent of MemoRules.displayTitle and normalizedSearchText.
private func goalMemoFrozenTitle(_ memo: Memo) -> String {
    var remaining = memo.content[...]
    var title = "빈 메모"
    while !remaining.isEmpty {
        let end = remaining.firstIndex(where: \.isNewline) ?? remaining.endIndex
        let line = remaining[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        remaining = end == remaining.endIndex ? remaining[end...] : remaining[remaining.index(after: end)...]
        if !line.isEmpty {
            title = line
            break
        }
    }
    guard title == "빈 메모" else { return title }
    switch MemoEditorMode(rawValue: memo.preferredModeRawValue) ?? .text {
    case .text: return "빈 메모"
    case .drawing: return "필기 메모"
    case .checklist: return "체크리스트"
    }
}

private func goalMemoFrozenMatches(_ memo: Memo, checklistTitles: [String], query: String,
                                   locale: Locale) -> Bool {
    let normalizedQuery = goalMemoFrozenSearchText(query, locale: locale)
    guard !normalizedQuery.isEmpty else { return true }
    let searchableText = ([memo.content, goalMemoFrozenTitle(memo)] + checklistTitles)
        .joined(separator: "\n")
    return goalMemoFrozenSearchText(searchableText, locale: locale).contains(normalizedQuery)
}

private func goalMemoRangeProbeMatches(_ memo: Memo, checklistTitles: [String], query: String,
                                     locale: Locale) -> Bool {
    let normalizedQuery = goalMemoFrozenSearchText(query, locale: locale)
    guard !normalizedQuery.isEmpty else { return true }
    let searchableText = ([memo.content, goalMemoFrozenTitle(memo)] + checklistTitles)
        .joined(separator: "\n")
    return searchableText.range(
        of: normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: locale
    ) != nil
}
