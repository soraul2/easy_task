#if os(iOS)
import PlanBaseCore
import Foundation
import SwiftData
import SwiftUI

struct MobileArchiveRecordCard: View {
    var record: ArchiveDayRecord
    var attachments: [DiaryAttachment]
    var legacyFileNames: [String]
    var onOpenBoardDate: (Date) -> Void

    @State private var tasksExpanded = false

    private var presentation: ArchiveDayPresentation {
        ArchiveDayPresentation(record: record)
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
        .padding(16)
        .foregroundStyle(AppTheme.primaryText)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .onAppear {
            if presentation.shouldExpandTaskListForSearch {
                tasksExpanded = true
            }
        }
        .onChange(of: presentation.shouldExpandTaskListForSearch) { _, shouldExpand in
            if shouldExpand {
                tasksExpanded = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(presentation.displayDate, systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)

                Spacer(minLength: 4)

                if presentation.reviewMatchesSearch {
                    Label("회고 일치", systemImage: "magnifyingglass")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.eventForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.event, in: Capsule())
                }

                detailButton
            }

            HStack(alignment: .center, spacing: 10) {
                Image(systemName: record.review == nil ? "checkmark.circle" : "book.closed")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(
                        record.review == nil
                            ? AppTheme.doneForeground
                            : AppTheme.eventForeground
                    )
                    .frame(width: 40, height: 40)
                    .background(record.review == nil ? AppTheme.done : AppTheme.event, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title)
                        .font(.headline)
                        .lineLimit(2)

                    if !presentation.summaryText.isEmpty {
                        Text(presentation.summaryText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }

                Spacer(minLength: 0)
            }
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
                tasksExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Label("그날 한 일", systemImage: "checkmark.circle")
                    Text("\(record.tasks.count)")
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppTheme.selectedTab, in: Capsule())
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(tasksExpanded ? 0 : -90))
                        .animation(.snappy(duration: 0.18), value: tasksExpanded)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tasksExpanded ? "그날 한 일 접기" : "그날 한 일 펼치기")

            if tasksExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(record.tasks.enumerated()), id: \.element.id) { index, task in
                        MobileArchiveTaskRow(
                            task: task,
                            isSearchMatch: presentation.taskMatchesSearch(task.id),
                            matchedChecklistItemIDs: presentation.matchedChecklistItemIDs
                        )
                        if index < record.tasks.count - 1 {
                            Divider()
                                .overlay(AppTheme.border)
                        }
                    }
                }
            }
        }
    }

    private var detailButton: some View {
        Button {
            guard let date = DayKey.date(from: record.dayKey) else { return }
            onOpenBoardDate(date)
        } label: {
            Text("상세보기")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("\(presentation.displayDate) 칸반보드 열기")
        .accessibilityHint("이 날짜의 작업 보드로 이동합니다")
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
                .foregroundStyle(AppTheme.primaryText)
            }
        }
    }
}

private struct MobileArchiveImageCarousel: View {
    var attachments: [DiaryAttachment]
    var legacyFileNames: [String]
    @State private var selectedIndex = 0
    @State private var viewerStartIndex = 0
    @State private var showingViewer = false
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
                .contentShape(Rectangle())
                .onTapGesture {
                    viewerStartIndex = safeIndex
                    showingViewer = true
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("두 번 탭하여 전체 화면으로 보기")

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
        .fullScreenCover(isPresented: $showingViewer) {
            MobileArchiveImageViewer(
                items: items,
                initialIndex: viewerStartIndex
            )
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

private struct MobileArchiveImageViewer: View {
    var items: [MobileArchiveImageItem]
    @State private var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(items: [MobileArchiveImageItem], initialIndex: Int) {
        self.items = items
        _selectedIndex = State(initialValue: min(max(initialIndex, 0), max(items.count - 1, 0)))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                TabView(selection: $selectedIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        MobileAsyncThumbnailImage(
                            request: item.thumbnailRequest,
                            placeholderMessage: "이미지를 불러올 수 없음",
                            minHeight: 240,
                            accessibilityLabel: "회고 이미지 \(index + 1)"
                        )
                        .background(Color.black)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if items.count > 1 {
                    Text("\(selectedIndex + 1) / \(items.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.64), in: Capsule())
                        .padding(.bottom, 20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.58), in: Circle())
                    }
                    .accessibilityLabel("전체 화면 이미지 닫기")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
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

private struct MobileArchiveTaskRow: View {
    var task: TodoTask
    var isSearchMatch: Bool
    var matchedChecklistItemIDs: Set<UUID>
    @Query private var checklistItems: [TaskChecklistItem]

    init(
        task: TodoTask,
        isSearchMatch: Bool,
        matchedChecklistItemIDs: Set<UUID>
    ) {
        self.task = task
        self.isSearchMatch = isSearchMatch
        self.matchedChecklistItemIDs = matchedChecklistItemIDs
        _checklistItems = Query(TaskChecklistService.descriptor(taskID: task.id))
    }

    private var checklistProgress: ChecklistProgress {
        TaskChecklistService.progress(in: checklistItems)
    }

    private var matchingChecklistItems: [TaskChecklistItem] {
        checklistItems.filter { matchedChecklistItemIDs.contains($0.id) }
    }

    private var displayDate: String {
        let key = ArchiveQueryRules.dayKey(for: task)
        guard let date = DayKey.date(from: key) else { return key }
        return DayKey.display(date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.doneForeground)
                .frame(width: 24, height: 24)
                .background(AppTheme.done, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if isSearchMatch {
                        Text("일치")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.eventForeground)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.event, in: Capsule())
                    }
                }

                if let note = task.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(3)
                }

                if !matchingChecklistItems.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(matchingChecklistItems.prefix(3))) { item in
                            Label("체크리스트: \(item.title)", systemImage: "magnifyingglass")
                                .lineLimit(2)
                        }
                        if matchingChecklistItems.count > 3 {
                            Text("외 \(matchingChecklistItems.count - 3)개 일치")
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .accessibilityIdentifier("archive-checklist-search-match")
                }

                HStack(spacing: 10) {
                    Text(displayDate)
                    if let estimatedMinutes = task.estimatedMinutes {
                        Label(EstimatedTimeFormatter.short(estimatedMinutes), systemImage: "clock")
                    }
                    Spacer(minLength: 4)
                    MobileChecklistProgressChip(progress: checklistProgress)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSearchMatch ? AppTheme.selectedTab : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if isSearchMatch {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
        }
    }
}
#endif
