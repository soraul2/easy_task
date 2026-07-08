import AppKit
import SwiftData
import SwiftUI

private struct ArchiveDayGroup: Identifiable {
    var dayKey: String
    var tasks: [Task]
    var review: DailyReview?

    var id: String { dayKey }
}

private enum ArchiveSearchPeriod: String, CaseIterable, Identifiable {
    case all
    case last7Days
    case last30Days
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "전체"
        case .last7Days: "최근 7일"
        case .last30Days: "최근 30일"
        case .custom: "직접 설정"
        }
    }
}

private enum ArchiveSearchScope: String, CaseIterable, Identifiable {
    case all
    case tasks
    case reviews

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "전체"
        case .tasks: "작업"
        case .reviews: "회고"
        }
    }

    var includesTasks: Bool {
        self == .all || self == .tasks
    }

    var includesReviews: Bool {
        self == .all || self == .reviews
    }
}

struct ArchiveView: View {
    var onOpenBoardDate: (Date) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [Task]
    @Query private var reviews: [DailyReview]
    @State private var searchText = ""
    @State private var searchPeriod: ArchiveSearchPeriod = .all
    @State private var searchScope: ArchiveSearchScope = .all
    @State private var customStartDate = DayKey.addingDays(-30, to: DayKey.startOfDay(for: Date()))
    @State private var customEndDate = DayKey.startOfDay(for: Date())
    @State private var message: String?

    private var completedTasks: [Task] {
        tasks
            .filter { $0.status == TaskStatus.done.rawValue }
            .sorted { ($0.completedAt ?? $0.archivedAt ?? .distantPast) > ($1.completedAt ?? $1.archivedAt ?? .distantPast) }
    }

    private var nonEmptyReviews: [DailyReview] {
        reviews.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !$0.imageFileNames.isEmpty
        }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var archiveGroups: [ArchiveDayGroup] {
        let periodTasks = completedTasks.filter { dayKeyMatchesPeriod(archiveDayKey(for: $0)) }
        let periodReviews = nonEmptyReviews.filter { dayKeyMatchesPeriod($0.dayKey) }
        let tasksByDay = Dictionary(grouping: periodTasks, by: archiveDayKey)
        let reviewsByDay = Dictionary(grouping: periodReviews, by: \.dayKey)
            .mapValues { reviews in
                reviews.sorted { $0.updatedAt > $1.updatedAt }.first
            }
        let searchableTasks = searchScope.includesTasks ? periodTasks : []
        let searchableReviews = searchScope.includesReviews ? periodReviews : []

        let dayKeys: Set<String>
        if normalizedSearchText.isEmpty {
            let taskKeys = searchScope.includesTasks ? Set(tasksByDay.keys) : Set<String>()
            let reviewKeys = searchScope.includesReviews ? Set(reviewsByDay.keys) : Set<String>()
            dayKeys = taskKeys.union(reviewKeys)
        } else {
            let matchedTaskKeys = searchableTasks
                .filter { taskMatchesSearch($0) }
                .map(archiveDayKey)
            let matchedReviewKeys = searchableReviews
                .filter { reviewMatchesSearch($0) }
                .map(\.dayKey)
            dayKeys = Set(matchedTaskKeys).union(matchedReviewKeys)
        }

        return dayKeys
            .sorted(by: >)
            .map { dayKey in
                ArchiveDayGroup(
                    dayKey: dayKey,
                    tasks: (tasksByDay[dayKey] ?? []).sorted {
                        ($0.completedAt ?? $0.archivedAt ?? .distantPast) > ($1.completedAt ?? $1.archivedAt ?? .distantPast)
                    },
                    review: reviewsByDay[dayKey] ?? nil
                )
            }
            .filter { !$0.tasks.isEmpty || $0.review != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 12)

            ArchiveDetailedSearchPanel(
                text: $searchText,
                period: $searchPeriod,
                scope: $searchScope,
                startDate: $customStartDate,
                endDate: $customEndDate,
                onReset: resetSearch
            )
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let message {
                        ArchiveMessageView(message: message)
                    }

                    if archiveGroups.isEmpty {
                        emptyState
                    } else {
                        ForEach(archiveGroups) { group in
                            ArchiveDayGroupView(
                                group: group,
                                onOpenBoardDate: onOpenBoardDate
                            )
                        }
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("기록")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                Text("날짜별 회고와 그날 한 일을 함께 봅니다.")
                    .font(.callout)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()

            Button {
                exportBackup()
            } label: {
                Label("내보내기", systemImage: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .calendarToolbarButtonBackground()
            }
            .buttonStyle(.plain)

            Button {
                importBackup()
            } label: {
                Label("가져오기", systemImage: "square.and.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .calendarToolbarButtonBackground()
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: hasActiveSearch ? "magnifyingglass" : "book.pages")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Text(hasActiveSearch ? "검색 결과 없음" : "보관된 기록 없음")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
            Text(hasActiveSearch ? "기간, 키워드, 검색 대상을 조정해보세요." : "완료한 작업이나 회고를 작성하면 이곳에 표시됩니다.")
                .font(.callout)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private func archiveDayKey(for task: Task) -> String {
        task.completedDayKey ?? task.archivedDayKey ?? task.plannedDayKey
    }

    private var hasActiveSearch: Bool {
        !normalizedSearchText.isEmpty ||
            searchPeriod != .all ||
            searchScope != .all
    }

    private func dayKeyMatchesPeriod(_ dayKey: String) -> Bool {
        let today = DayKey.startOfDay(for: Date())
        let todayKey = DayKey.key(for: today)

        switch searchPeriod {
        case .all:
            return true
        case .last7Days:
            let startKey = DayKey.key(for: DayKey.addingDays(-6, to: today))
            return startKey <= dayKey && dayKey <= todayKey
        case .last30Days:
            let startKey = DayKey.key(for: DayKey.addingDays(-29, to: today))
            return startKey <= dayKey && dayKey <= todayKey
        case .custom:
            let start = min(customStartDate, customEndDate)
            let end = max(customStartDate, customEndDate)
            let startKey = DayKey.key(for: start)
            let endKey = DayKey.key(for: end)
            return startKey <= dayKey && dayKey <= endKey
        }
    }

    private func taskMatchesSearch(_ task: Task) -> Bool {
        guard !normalizedSearchText.isEmpty else { return true }

        return containsSearch(task.title) ||
            containsSearch(task.note) ||
            containsSearch(task.completedDayKey) ||
            containsSearch(task.archivedDayKey) ||
            containsSearch(task.plannedDayKey)
    }

    private func reviewMatchesSearch(_ review: DailyReview) -> Bool {
        guard !normalizedSearchText.isEmpty else { return true }

        return containsSearch(review.content) ||
            containsSearch(review.title) ||
            containsSearch(review.dayKey)
    }

    private func containsSearch(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.range(
            of: normalizedSearchText,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    private func resetSearch() {
        searchText = ""
        searchPeriod = .all
        searchScope = .all
        customStartDate = DayKey.addingDays(-30, to: DayKey.startOfDay(for: Date()))
        customEndDate = DayKey.startOfDay(for: Date())
    }

    private func exportBackup() {
        do {
            switch try BackupService.exportJSON(context: modelContext) {
            case .completed:
                message = "백업을 내보냈습니다."
            case .cancelled:
                message = nil
            }
        } catch {
            message = "내보내기 실패: \(error.localizedDescription)"
        }
    }

    private func importBackup() {
        do {
            switch try BackupService.importReplacingAll(context: modelContext) {
            case .completed:
                message = "백업을 가져왔습니다."
            case .cancelled:
                message = nil
            }
        } catch {
            message = "가져오기 실패: \(error.localizedDescription)"
        }
    }
}

private struct ArchiveDetailedSearchPanel: View {
    @Binding var text: String
    @Binding var period: ArchiveSearchPeriod
    @Binding var scope: ArchiveSearchScope
    @Binding var startDate: Date
    @Binding var endDate: Date
    var onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ArchiveSearchField(text: $text)

                Button {
                    onReset()
                } label: {
                    Label("초기화", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .calendarToolbarButtonBackground()
                }
                .buttonStyle(.plain)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    periodPicker
                    scopePicker
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 12) {
                    periodPicker
                    scopePicker
                }
            }

            if period == .custom {
                HStack(spacing: 12) {
                    DatePicker("시작", selection: $startDate, displayedComponents: .date)
                    DatePicker("종료", selection: $endDate, displayedComponents: .date)
                    Spacer(minLength: 0)
                }
                .datePickerStyle(.compact)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(14)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var periodPicker: some View {
        FilterPicker(title: "기간") {
            Picker("기간", selection: $period) {
                ForEach(ArchiveSearchPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
        }
    }

    private var scopePicker: some View {
        FilterPicker(title: "검색 대상") {
            Picker("검색 대상", selection: $scope) {
                ForEach(ArchiveSearchScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
        }
    }
}

private struct FilterPicker<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 56, alignment: .leading)
            content
        }
    }
}

private struct ArchiveSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)

            TextField("작업 제목, 메모, 회고 검색", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.primaryText)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 44)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

private struct ArchiveMessageView: View {
    var message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(AppTheme.secondaryText)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.columnTodo, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
    }
}

private struct ArchiveDayGroupView: View {
    var group: ArchiveDayGroup
    var onOpenBoardDate: (Date) -> Void
    @State private var isTaskListExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            timelineIcon

            VStack(alignment: .leading, spacing: 12) {
                header

                if let review = group.review {
                    reviewContent(review)
                }

                if !group.tasks.isEmpty {
                    taskPreview
                }
            }
        }
        .padding(18)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(recordTitle)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)

            Text("›")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)

            Text(displayDate)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)

            Spacer()

            Text(summaryText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.selectedTab.opacity(0.22), in: Capsule())

            Button {
                openBoard()
            } label: {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 28)
                    .calendarToolbarButtonBackground()
            }
            .buttonStyle(.plain)
            .help("\(group.dayKey) 칸반보드로 이동")
        }
    }

    private func reviewContent(_ review: DailyReview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !review.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(review.content)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if !review.imageFileNames.isEmpty {
                ArchiveReviewImagePreview(fileNames: review.imageFileNames)
            }
        }
    }

    private var taskPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isTaskListExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Label("그날 한 일", systemImage: "checkmark.circle")
                    Text("\(group.tasks.count)")
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppTheme.selectedTab.opacity(0.22), in: Capsule())
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(isTaskListExpanded ? 0 : -90))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .help(isTaskListExpanded ? "그날 한 일 접기" : "그날 한 일 펼치기")

            if isTaskListExpanded {
                ForEach(group.tasks) { task in
                    ArchiveTaskRow(task: task)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                ForEach(group.tasks.prefix(3)) { task in
                    ArchiveTaskCompactRow(task: task)
                }
                if group.tasks.count > 3 {
                    Text("외 \(group.tasks.count - 3)개")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.top, 2)
                }
            }
        }
    }

    private var timelineIcon: some View {
        VStack(spacing: 8) {
            Image(systemName: group.review == nil ? "checkmark.circle" : "book.closed")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(group.review == nil ? AppTheme.done : AppTheme.event)
                .frame(width: 36, height: 36)

            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 40)
    }

    private var displayDate: String {
        guard let date = DayKey.date(from: group.dayKey) else { return group.dayKey }
        return DayKey.display(date)
    }

    private var recordTitle: String {
        let title = group.review?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty {
            return title
        }
        return group.review == nil ? "작업 기록" : "하루 회고"
    }

    private var summaryText: String {
        var parts: [String] = []
        if !group.tasks.isEmpty {
            parts.append("작업 \(group.tasks.count)")
        }
        if group.review != nil {
            parts.append("회고")
        }
        return parts.joined(separator: " · ")
    }

    private func openBoard() {
        guard let date = DayKey.date(from: group.dayKey) else { return }
        onOpenBoardDate(date)
    }
}

private struct ArchiveReviewImagePreview: View {
    var fileNames: [String]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let fileName = fileNames.first,
               let image = NSImage(contentsOf: DiaryImageStore.imageURL(for: fileName)) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 420)
                    .background(AppTheme.input)
            } else {
                Rectangle()
                    .fill(AppTheme.input)
                    .frame(height: 160)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
            }

            if fileNames.count > 1 {
                Text("1/\(fileNames.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.52), in: Capsule())
                    .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ArchiveTaskCompactRow: View {
    var task: Task

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.done)
            Text(task.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ArchiveTaskRow: View {
    var task: Task

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .lineLimit(2)

                if let note = task.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text(task.completedDayKey ?? task.archivedDayKey ?? task.plannedDayKey)
                    if let estimatedMinutes = task.estimatedMinutes {
                        Label(EstimatedTimeFormatter.short(estimatedMinutes), systemImage: "clock")
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.cardMutedText)
            }

            Spacer()
        }
        .padding(12)
        .background(AppTheme.done.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}
