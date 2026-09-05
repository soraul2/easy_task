#if os(iOS) || os(macOS)
import SwiftUI

public struct DailyActivityTaskList: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let entries: [DailyActivityEntry]
    private let dayKey: String
    private let matchedTaskIDs: Set<UUID>
    private let onOpenTask: (UUID) -> Void
    private let showsExpansionControl: Bool
    @Binding private var expanded: Bool
    @ScaledMetric(relativeTo: .caption) private var symbolSize: CGFloat = 26

    public init(
        entries: [DailyActivityEntry],
        dayKey: String,
        matchedTaskIDs: Set<UUID>,
        expanded: Binding<Bool>,
        onOpenTask: @escaping (UUID) -> Void,
        showsExpansionControl: Bool = true
    ) {
        self.entries = entries
        self.dayKey = dayKey
        self.matchedTaskIDs = matchedTaskIDs
        _expanded = expanded
        self.onOpenTask = onOpenTask
        self.showsExpansionControl = showsExpansionControl
    }

    private var visibleEntries: [DailyActivityEntry] {
        expanded ? entries : Array(entries.prefix(3))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                Button {
                    onOpenTask(entry.id)
                } label: {
                    row(entry)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("archive-task-\(entry.id.uuidString)")
                .accessibilityLabel("\(entry.title), \(entry.evidence.summary)")
                .accessibilityHint(
                    entry.canOpenTask
                        ? "작업의 생성 시각과 활동 기록을 엽니다"
                        : "현재 작업 정보 없이 남아 있는 활동 기록을 엽니다"
                )
                if index < visibleEntries.count - 1 { Divider().overlay(AppTheme.border) }
            }
            if entries.count > 3 && showsExpansionControl {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) { expanded.toggle() }
                } label: {
                    Label(
                        expanded ? "간략히 보기" : "작업 \(entries.count - 3)개 더 보기",
                        systemImage: expanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.secondaryText)
                .accessibilityIdentifier("archive-task-disclosure-\(dayKey)")
            }
            if entries.contains(where: { $0.evidence.focusSessionCount > 0 }) {
                Text("집중 시간은 이날 종료한 세션 기준이에요.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.top, 8)
            }
        }
    }

    private func highlighted(_ text: String, query: String) -> AttributedString {
        var value = AttributedString(text)
        guard !query.isEmpty else { return value }
        var remainder = value.startIndex..<value.endIndex
        while let range = value[remainder].range(
            of: query, options: [.caseInsensitive, .diacriticInsensitive])
        {
            value[range].underlineStyle = .single
            value[range].inlinePresentationIntent = .stronglyEmphasized
            remainder = range.upperBound..<value.endIndex
        }
        return value
    }

    private func row(_ entry: DailyActivityEntry) -> some View {
        let completed = entry.evidence.completed || entry.evidence.legacyCompletion
        let symbol =
            !entry.canOpenTask
            ? "questionmark"
            : completed ? "checkmark" : (entry.evidence.focusSessionCount > 0 ? "timer" : "play.fill")
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(completed ? AppTheme.doneForeground : AppTheme.primaryText)
                .frame(width: symbolSize, height: symbolSize)
                .background(completed ? AppTheme.done : AppTheme.selectedTab, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(highlighted(entry.title, query: entry.searchQuery))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.evidence.summary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if matchedTaskIDs.contains(entry.id) {
                    if let note = entry.note, !note.isEmpty {
                        Text(highlighted(note, query: entry.searchQuery)).font(.caption).lineLimit(3)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    ForEach(Array(entry.matchingChecklistTitles.prefix(3).enumerated()), id: \.offset) {
                        _, title in
                        Label {
                            Text(highlighted(title, query: entry.searchQuery))
                        } icon: {
                            Image(systemName: "magnifyingglass")
                        }
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(
            matchedTaskIDs.contains(entry.id) ? AppTheme.selectedTab : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
    }
}

#endif
