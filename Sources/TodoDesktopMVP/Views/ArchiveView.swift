import AppKit
import Combine
import SwiftData
import SwiftUI
import EasyTaskCore

struct ArchiveView: View {
    var onOpenBoardDate: (Date) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var filter = ArchiveFilter()
    @State private var message: String?
    @State private var querySession: ArchiveQuerySession?

    var body: some View {
        let attachmentIndex = DiaryAttachmentIndex(
            attachments: querySession?.attachments ?? [],
            blocks: querySession?.blocks ?? []
        )
        let archiveGroups = querySession?.records ?? []

        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 12)

            ArchiveDetailedSearchPanel(
                text: $filter.searchText,
                period: $filter.period,
                scope: $filter.scope,
                startDate: $filter.customStartDate,
                endDate: $filter.customEndDate,
                onReset: resetSearch
            )
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.bottom, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let message {
                        ArchiveMessageView(message: message)
                    }

                    if querySession?.isLoading == true && archiveGroups.isEmpty {
                        ProgressView("기록 불러오는 중")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else if archiveGroups.isEmpty {
                        emptyState
                    } else {
                        ForEach(archiveGroups) { group in
                            ArchiveDayGroupView(
                                group: group,
                                attachments: group.review.map {
                                    attachmentIndex.activeAttachments(for: $0.id)
                                } ?? [],
                                legacyFileNames: group.review.map {
                                    attachmentIndex.unresolvedLegacyImageFileNames(for: $0)
                                } ?? [],
                                onOpenBoardDate: onOpenBoardDate
                            )
                        }

                        if querySession?.hasMore == true {
                            Button {
                                querySession?.loadNextPage()
                            } label: {
                                if querySession?.isLoading == true {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("이전 기록 더 보기", systemImage: "chevron.down")
                                }
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .disabled(querySession?.isLoading == true)
                        }
                    }

                    if let errorMessage = querySession?.errorMessage {
                        VStack(spacing: 8) {
                            Text(errorMessage)
                                .font(.callout)
                                .foregroundStyle(AppTheme.secondaryText)
                            Button("다시 시도") {
                                querySession?.retry()
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .task {
            guard querySession == nil else { return }
            let session = ArchiveQuerySession(context: modelContext)
            querySession = session
            session.apply(filter, debounceSearch: false)
        }
        .onChange(of: filter) { oldFilter, newFilter in
            querySession?.apply(
                newFilter,
                debounceSearch: shouldDebounceSearch(
                    from: oldFilter,
                    to: newFilter
                )
            )
        }
        .onReceive(NotificationCenter.default.publisher(
            for: PersistenceCommandService.dataChangedNotification
        )) { notification in
            guard let sourceContext = notification.object as? ModelContext,
                  sourceContext === modelContext else { return }
            querySession?.refreshPreservingDepth()
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
            Image(systemName: filter.hasActiveCriteria ? "magnifyingglass" : "book.pages")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Text(filter.hasActiveCriteria ? "검색 결과 없음" : "보관된 기록 없음")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
            Text(filter.hasActiveCriteria ? "기간, 키워드, 검색 대상을 조정해보세요." : "완료한 작업이나 회고를 작성하면 이곳에 표시됩니다.")
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

    private func resetSearch() {
        filter.reset()
    }

    private func shouldDebounceSearch(
        from oldFilter: ArchiveFilter,
        to newFilter: ArchiveFilter
    ) -> Bool {
        oldFilter.searchText != newFilter.searchText &&
            oldFilter.period == newFilter.period &&
            oldFilter.scope == newFilter.scope &&
            oldFilter.customStartDate == newFilter.customStartDate &&
            oldFilter.customEndDate == newFilter.customEndDate
    }

    private func exportBackup() {
        do {
            switch try BackupService.exportPackage(context: modelContext) {
            case .completed(let completionMessage):
                message = completionMessage
            case .cancelled:
                message = nil
            }
        } catch {
            message = "내보내기 실패: \(error.localizedDescription)"
        }
    }

    private func importBackup() {
        do {
            switch try BackupService.importBackup(context: modelContext) {
            case .completed(let completionMessage):
                message = completionMessage
                querySession?.refreshPreservingDepth()
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
    @Binding var period: ArchivePeriod
    @Binding var scope: ArchiveScope
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
                ForEach(ArchivePeriod.allCases) { period in
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
                ForEach(ArchiveScope.allCases) { scope in
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
    var group: ArchiveDayRecord
    var attachments: [DiaryAttachment]
    var legacyFileNames: [String]
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

            if !attachments.isEmpty || !legacyFileNames.isEmpty {
                ArchiveReviewImagePreview(
                    attachments: attachments,
                    legacyFileNames: legacyFileNames
                )
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
    var attachments: [DiaryAttachment]
    var legacyFileNames: [String]
    @State private var selectedIndex = 0
    @State private var resolvedLegacyItems: [ArchiveReviewImageItem] = []

    var body: some View {
        let items = canonicalImageItems + resolvedLegacyItems
        let safeIndex = items.indices.contains(selectedIndex) ? selectedIndex : 0

        ZStack(alignment: .bottomTrailing) {
            if items.indices.contains(safeIndex) {
                let item = items[safeIndex]
                ArchiveReviewAsyncImage(request: item.request)
                    .id(item.id)
            } else {
                ArchiveReviewMissingImage()
            }

            if items.count > 1 {
                HStack {
                    if safeIndex > 0 {
                        navigationButton(systemImage: "chevron.left", label: "이전 이미지") {
                            selectedIndex = safeIndex - 1
                        }
                    }
                    Spacer()
                    if safeIndex < items.count - 1 {
                        navigationButton(systemImage: "chevron.right", label: "다음 이미지") {
                            selectedIndex = safeIndex + 1
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 10)
            }

            if items.count > 1 {
                Text("\(safeIndex + 1)/\(items.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.52), in: Capsule())
                    .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: items.count) { _, count in
            if selectedIndex >= count {
                selectedIndex = 0
            }
        }
        .task(id: legacyResolutionID) {
            await resolveLegacyItems()
        }
    }

    private var canonicalImageItems: [ArchiveReviewImageItem] {
        attachments.enumerated().map { index, attachment in
            let cacheKey = DiaryImageStore.attachmentPreviewCacheKey(
                instanceID: attachment.instanceID,
                sha256: attachment.sha256
            )
            return ArchiveReviewImageItem(
                id: "canonical-\(cacheKey)-\(index)",
                request: DiaryPreviewImageRequest(
                    cacheKey: cacheKey,
                    source: .data(attachment.data)
                )
            )
        }
    }

    private var legacyResolutionID: ArchiveLegacyResolutionID {
        ArchiveLegacyResolutionID(
            attachmentInstanceIDs: attachments.map(\.instanceID),
            attachmentHashes: attachments.map(\.sha256),
            attachmentFileNames: attachments.map { $0.originalFileName ?? "" },
            legacyFileNames: legacyFileNames
        )
    }

    @MainActor
    private func resolveLegacyItems() async {
        resolvedLegacyItems = []
        guard !legacyFileNames.isEmpty else { return }
        let canonicalFileNames = Set(attachments.compactMap {
            normalizedFileName($0.originalFileName)
        })
        let canonicalHashes = Set(attachments.map(\.sha256).filter { !$0.isEmpty })
        let resolved = await DiaryImageStore.resolveLegacyImages(
            fileNames: legacyFileNames,
            canonicalFileNames: canonicalFileNames,
            canonicalHashes: canonicalHashes
        )
        guard !Swift.Task.isCancelled else { return }

        resolvedLegacyItems = resolved.map { image in
            ArchiveReviewImageItem(
                id: "legacy-\(image.normalizedFileName)-\(image.index)",
                request: DiaryPreviewImageRequest(
                    cacheKey: DiaryImageStore.filePreviewCacheKey(for: image.fileURL),
                    source: .file(image.fileURL)
                )
            )
        }
        selectedIndex = min(
            selectedIndex,
            max(attachments.count + resolvedLegacyItems.count - 1, 0)
        )
    }

    private func normalizedFileName(_ fileName: String?) -> String? {
        guard let value = fileName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }

    private func navigationButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.black.opacity(0.52), in: Circle())
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

private struct ArchiveReviewImageItem: Identifiable {
    var id: String
    var request: DiaryPreviewImageRequest
}

private struct ArchiveLegacyResolutionID: Equatable {
    var attachmentInstanceIDs: [UUID]
    var attachmentHashes: [String]
    var attachmentFileNames: [String]
    var legacyFileNames: [String]
}

private struct ArchiveReviewAsyncImage: View {
    var request: DiaryPreviewImageRequest
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 420)
                    .background(AppTheme.input)
            } else {
                ArchiveReviewMissingImage()
            }
        }
        .task(id: request.cacheKey) {
            image = nil
            let loadedImage = await DiaryImageStore.previewImage(for: request)
            guard !Swift.Task.isCancelled else { return }
            image = loadedImage
        }
    }
}

private struct ArchiveReviewMissingImage: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.input)
            .frame(height: 160)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
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
                .layoutPriority(1)
            Spacer()
            TaskChecklistProgressLabel(taskID: task.id)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
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
                    TaskChecklistProgressLabel(taskID: task.id)
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
