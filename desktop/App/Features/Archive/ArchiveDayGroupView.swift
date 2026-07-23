import AppKit
import Foundation
import PlanBaseCore
import SwiftData
import SwiftUI

struct ArchiveDayGroupView: View {
    var group: ArchiveDayRecord
    var attachments: [DiaryAttachment]
    var legacyFileNames: [String]
    var onOpenBoardDate: (Date) -> Void
    @State private var isTaskListExpanded = false

    private var presentation: ArchiveDayPresentation {
        ArchiveDayPresentation(record: group)
    }

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
        .onAppear {
            if presentation.shouldExpandTaskListForSearch {
                isTaskListExpanded = true
            }
        }
        .onChange(of: presentation.shouldExpandTaskListForSearch) { _, shouldExpand in
            if shouldExpand {
                isTaskListExpanded = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                titleLine
                if !presentation.summaryText.isEmpty || presentation.reviewMatchesSearch {
                    metadataBadges
                }
            }

            Spacer(minLength: 8)

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

    private var titleLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(presentation.title)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                Text("›")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Text(presentation.displayDate)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(2)
                Text(presentation.displayDate)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .foregroundStyle(AppTheme.primaryText)
    }

    private var metadataBadges: some View {
        HStack(spacing: 6) {
            if !presentation.summaryText.isEmpty {
                Text(presentation.summaryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.selectedTab, in: Capsule())
            }

            if presentation.reviewMatchesSearch {
                Label("회고 일치", systemImage: "magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.eventForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.event, in: Capsule())
            }
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
                        .background(AppTheme.selectedTab, in: Capsule())
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .rotationEffect(.degrees(isTaskListExpanded ? 0 : -90))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
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
                VStack(spacing: 0) {
                    ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in
                        ArchiveTaskRow(
                            task: task,
                            isSearchMatch: presentation.taskMatchesSearch(task.id),
                            matchedChecklistItemIDs: presentation.matchedChecklistItemIDs
                        )
                        if index < group.tasks.count - 1 {
                            Divider()
                                .overlay(AppTheme.border)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var timelineIcon: some View {
        VStack(spacing: 8) {
            Image(systemName: group.review == nil ? "checkmark.circle" : "book.closed")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(group.review == nil ? AppTheme.doneForeground : AppTheme.eventForeground)
                .frame(width: 36, height: 36)
                .background(group.review == nil ? AppTheme.done : AppTheme.event, in: Circle())

            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 40)
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

private struct ArchiveTaskRow: View {
    var task: Task
    var isSearchMatch: Bool
    var matchedChecklistItemIDs: Set<UUID>
    @Query private var checklistItems: [TaskChecklistItem]

    init(
        task: Task,
        isSearchMatch: Bool,
        matchedChecklistItemIDs: Set<UUID>
    ) {
        self.task = task
        self.isSearchMatch = isSearchMatch
        self.matchedChecklistItemIDs = matchedChecklistItemIDs
        _checklistItems = Query(TaskChecklistService.descriptor(taskID: task.id))
    }

    private var matchingChecklistItems: [TaskChecklistItem] {
        checklistItems.filter { matchedChecklistItemIDs.contains($0.id) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppTheme.doneForeground)
                .frame(width: 22, height: 22)
                .background(AppTheme.done, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryText)
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

                if let note = task.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
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
                }

                HStack(spacing: 8) {
                    Text(task.completedDayKey ?? task.archivedDayKey ?? task.plannedDayKey)
                    if let estimatedMinutes = task.estimatedMinutes {
                        Label(EstimatedTimeFormatter.short(estimatedMinutes), systemImage: "clock")
                    }
                    TaskChecklistProgressLabel(taskID: task.id)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .background(isSearchMatch ? AppTheme.selectedTab : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if isSearchMatch {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
        }
    }
}
