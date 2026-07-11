#if os(iOS)
import EasyTaskCore
import Foundation
import SwiftData
import SwiftUI

struct MobileArchiveView: View {
    var onOpenBoardDate: (Date) -> Void

    @Query private var tasks: [TodoTask]
    @Query private var reviews: [DailyReview]
    @Query private var diaryBlocks: [DiaryBlock]
    @Query private var attachments: [DiaryAttachment]
    @State private var filter = ArchiveFilter()
    @State private var showingFilter = false

    private var records: [ArchiveDayRecord] {
        ArchiveQueryRules.records(tasks: tasks, reviews: reviews, filter: filter)
    }

    private var hasActiveFilterOptions: Bool {
        filter.period != .all || filter.scope != .all
    }

    var body: some View {
        let attachmentIndex = DiaryAttachmentIndex(
            attachments: attachments,
            blocks: diaryBlocks
        )

        NavigationStack {
            List {
                if records.isEmpty {
                    emptyState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 32, leading: 20, bottom: 20, trailing: 20))
                } else {
                    ForEach(records) { record in
                        MobileArchiveRecordCard(
                            record: record,
                            attachments: record.review.map {
                                attachmentIndex.activeAttachments(for: $0.id)
                            } ?? [],
                            legacyFileNames: record.review.map {
                                attachmentIndex.unresolvedLegacyImageFileNames(for: $0)
                            } ?? [],
                            onOpenBoardDate: onOpenBoardDate
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: MobileLayout.bottomTabClearance)
            }
            .searchable(text: $filter.searchText, prompt: "작업 제목, 메모, 회고 검색")
            .navigationTitle("기록")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingFilter = true } label: {
                        Image(systemName: hasActiveFilterOptions
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(hasActiveFilterOptions ? "적용된 기록 필터 변경" : "기록 필터")
                }
            }
            .sheet(isPresented: $showingFilter) {
                MobileArchiveFilterSheet(filter: $filter)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                filter.hasActiveCriteria ? "검색 결과 없음" : "보관된 기록 없음",
                systemImage: filter.hasActiveCriteria ? "magnifyingglass" : "book.pages",
                description: Text(filter.hasActiveCriteria
                    ? "기간, 키워드, 검색 대상을 조정해보세요."
                    : "완료한 작업이나 회고를 작성하면 이곳에 표시됩니다.")
            )

            if filter.hasActiveCriteria {
                Button("검색 조건 초기화") {
                    filter.reset()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

private struct MobileArchiveFilterSheet: View {
    @Binding var filter: ArchiveFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("기간") {
                    Picker("조회 기간", selection: $filter.period) {
                        ForEach(ArchivePeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }

                    if filter.period == .custom {
                        DatePicker(
                            "시작",
                            selection: $filter.customStartDate,
                            displayedComponents: .date
                        )
                        DatePicker(
                            "종료",
                            selection: $filter.customEndDate,
                            displayedComponents: .date
                        )
                    }
                }
                .listRowBackground(AppTheme.panel)

                Section("검색 대상") {
                    Picker("검색 대상", selection: $filter.scope) {
                        ForEach(ArchiveScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(AppTheme.panel)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .foregroundStyle(AppTheme.primaryText)
            .tint(AppTheme.event)
            .navigationTitle("검색 필터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("초기화") {
                        filter.reset()
                    }
                    .disabled(!filter.hasActiveCriteria)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.background)
    }
}

private struct MobileArchiveRecordCard: View {
    var record: ArchiveDayRecord
    var attachments: [DiaryAttachment]
    var legacyFileNames: [String]
    var onOpenBoardDate: (Date) -> Void

    @State private var tasksExpanded = false

    private var title: String {
        let reviewTitle = record.review?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !reviewTitle.isEmpty { return reviewTitle }
        return record.review == nil ? "작업 기록" : "하루 회고"
    }

    private var displayDate: String {
        guard let date = DayKey.date(from: record.dayKey) else { return record.dayKey }
        return DayKey.display(date)
    }

    private var summaryText: String {
        var parts: [String] = []
        if !record.tasks.isEmpty {
            parts.append("작업 \(record.tasks.count)")
        }
        if record.review != nil {
            parts.append("회고")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let review = record.review {
                reviewContent(review)
            }

            if !record.tasks.isEmpty {
                taskPreview
            }
        }
        .padding(14)
        .foregroundStyle(AppTheme.primaryText)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: record.review == nil ? "checkmark.circle" : "book.closed")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(record.review == nil ? AppTheme.done : AppTheme.event)
                .frame(width: 34, height: 34)
                .background(AppTheme.input, in: Circle())

            VStack(alignment: .leading, spacing: 7) {
                MobileArchiveTitleLine(title: title, displayDate: displayDate)

                if !summaryText.isEmpty {
                    Text(summaryText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.selectedTab.opacity(0.24), in: Capsule())
                }
            }

            Spacer(minLength: 4)

            Button {
                guard let date = DayKey.date(from: record.dayKey) else { return }
                onOpenBoardDate(date)
            } label: {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(displayDate) 칸반보드 열기")
        }
    }

    @ViewBuilder
    private func reviewContent(_ review: DailyReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let content = review.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                MobileExpandableReviewText(text: content)
            }

            if !attachments.isEmpty || !legacyFileNames.isEmpty {
                MobileArchiveImageCarousel(
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
                    tasksExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Label("그날 한 일", systemImage: "checkmark.circle")
                    Text("\(record.tasks.count)")
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppTheme.selectedTab.opacity(0.24), in: Capsule())
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(tasksExpanded ? 0 : -90))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tasksExpanded ? "그날 한 일 접기" : "그날 한 일 펼치기")

            if tasksExpanded {
                ForEach(record.tasks) { task in
                    MobileArchiveTaskRow(task: task)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                ForEach(record.tasks.prefix(3)) { task in
                    MobileArchiveTaskCompactRow(task: task)
                }
                if record.tasks.count > 3 {
                    Text("외 \(record.tasks.count - 3)개")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.leading, 2)
                }
            }
        }
    }
}

private struct MobileArchiveTitleLine: View {
    var title: String
    var displayDate: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: true, vertical: false)
                Text("›")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Text(displayDate)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                Text(displayDate)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

private struct MobileExpandableReviewText: View {
    var text: String
    @State private var expanded = false

    private var canExpand: Bool {
        text.count > 180 || text.components(separatedBy: .newlines).count > 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.subheadline)
                .lineSpacing(3)
                .lineLimit(canExpand && !expanded ? 6 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if canExpand {
                Button(expanded ? "접기" : "더 보기") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expanded.toggle()
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.event)
            }
        }
    }
}

private struct MobileArchiveImageCarousel: View {
    var attachments: [DiaryAttachment]
    var legacyFileNames: [String]
    @State private var selectedIndex = 0
    @State private var imageAspectRatios: [String: CGFloat] = [:]
    @State private var legacyResolution = MobileLegacyImageResolution()

    var body: some View {
        let items = mixedImageItems
        let safeIndex = items.indices.contains(selectedIndex) ? selectedIndex : 0
        let selectedAspectRatio = items.indices.contains(safeIndex)
            ? imageAspectRatios[items[safeIndex].id] ?? 4.0 / 3.0
            : 4.0 / 3.0

        ZStack(alignment: .bottomTrailing) {
            if isResolvingLegacyImages {
                MobileImageLoadingPlaceholder(minHeight: 160)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
            } else {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        MobileAsyncThumbnailImage(
                            request: item.thumbnailRequest,
                            placeholderMessage: "이미지를 불러올 수 없음",
                            minHeight: 160,
                            accessibilityLabel: "회고 이미지 \(index + 1)",
                            onAspectRatioChange: { aspectRatio in
                                let ratio = constrainedAspectRatio(aspectRatio)
                                if imageAspectRatios[item.id] != ratio {
                                    imageAspectRatios[item.id] = ratio
                                }
                            }
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .aspectRatio(selectedAspectRatio, contentMode: .fit)
                .animation(.easeInOut(duration: 0.2), value: selectedAspectRatio)

                if items.count > 1 {
                    Text("\(safeIndex + 1)/\(items.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.58), in: Capsule())
                        .padding(9)
                        .accessibilityLabel("이미지 \(safeIndex + 1) / \(items.count)")
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .onChange(of: items.count) { _, newImageCount in
            if selectedIndex >= newImageCount {
                selectedIndex = 0
            }
        }
        .task(id: legacyFileNames) {
            let resolution = await MobileLegacyImageResolver.resolve(
                fileNames: legacyFileNames
            )
            guard !Swift.Task<Never, Never>.isCancelled else { return }
            legacyResolution = resolution
        }
    }

    private var mixedImageItems: [MobileArchiveImageItem] {
        var items = attachments.enumerated().map { index, attachment in
            MobileArchiveImageItem(
                id: "canonical-\(attachment.id.uuidString)-\(index)",
                data: attachment.data,
                attachmentHash: attachment.sha256
            )
        }
        let canonicalFileNames = Set(attachments.compactMap {
            normalizedFileName($0.originalFileName)
        })
        let canonicalHashes = Set(attachments.map(\.sha256).filter { !$0.isEmpty })
        var seenLegacyFileNames: Set<String> = []
        var seenLegacyHashes: Set<String> = []

        for legacyImage in resolvedLegacyImages {
            let fileNameKey = legacyImage.normalizedFileName
            let hash = legacyImage.attachmentHash
            let duplicatesCanonical = canonicalFileNames.contains(fileNameKey) ||
                hash.map(canonicalHashes.contains) == true
            let duplicatesLegacy = !seenLegacyFileNames.insert(fileNameKey).inserted ||
                hash.map { !seenLegacyHashes.insert($0).inserted } == true
            guard !duplicatesCanonical, !duplicatesLegacy else { continue }

            items.append(MobileArchiveImageItem(
                id: "legacy-\(fileNameKey)-\(legacyImage.sourceIndex)",
                data: legacyImage.data,
                attachmentHash: hash
            ))
        }
        return items
    }

    private var resolvedLegacyImages: [MobileResolvedLegacyImage] {
        guard legacyResolution.fileNames == legacyFileNames else { return [] }
        return legacyResolution.images
    }

    private var isResolvingLegacyImages: Bool {
        !legacyFileNames.isEmpty && legacyResolution.fileNames != legacyFileNames
    }

    private func constrainedAspectRatio(_ aspectRatio: CGFloat) -> CGFloat {
        min(max(aspectRatio, 0.82), 2.0)
    }

    private func normalizedFileName(_ fileName: String?) -> String? {
        guard let value = fileName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }
}

private struct MobileArchiveImageItem: Identifiable {
    var id: String
    var data: Data?
    var attachmentHash: String?

    var thumbnailRequest: MobileImageThumbnailRequest? {
        guard let data else { return nil }
        return MobileImageThumbnailRequest(
            data: data,
            attachmentHash: attachmentHash,
            dataIdentity: id
        )
    }
}

private struct MobileArchiveTaskCompactRow: View {
    var task: TodoTask

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.done)
            Text(task.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MobileArchiveTaskRow: View {
    var task: TodoTask

    private var displayDate: String {
        let key = ArchiveQueryRules.dayKey(for: task)
        guard let date = DayKey.date(from: key) else { return key }
        return DayKey.display(date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            if let note = task.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(3)
            }

            HStack(spacing: 10) {
                Text(displayDate)
                if let estimatedMinutes = task.estimatedMinutes {
                    Label(EstimatedTimeFormatter.short(estimatedMinutes), systemImage: "clock")
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.cardMutedText)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.done.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}
#endif
