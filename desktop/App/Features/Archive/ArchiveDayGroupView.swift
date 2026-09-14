import AppKit
import Foundation
import PlanBaseCore
import SwiftData
import SwiftUI

struct ArchiveDayGroupView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var group: ArchiveDayRecord
    var dateBasis: TaskHistoryDateBasis
    var attachments: [DiaryAttachment]
    var legacyFileNames: [String]
    var onOpenDay: () -> Void
    var onOpenTask: (UUID) -> Void
    var onEditReview: () -> Void
    @Binding var isTaskListExpanded: Bool
    @Binding var reviewExpanded: Bool

    private var presentation: ArchiveDayPresentation {
        ArchiveDayPresentation(record: group)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let entries = group.activityEntries {
                DailyActivityTaskList(
                    entries: entries, dayKey: group.dayKey,
                    matchedTaskIDs: group.matchedTaskIDs,
                    expanded: $isTaskListExpanded, onOpenTask: onOpenTask)
            } else if !group.tasks.isEmpty {
                taskPreview
            }
            Divider().overlay(AppTheme.border)
            if let review = group.review {
                DisclosureGroup(isExpanded: $reviewExpanded) {
                    reviewContent(review).padding(.top, 8)
                    Button("회고 수정", action: onEditReview)
                        .buttonStyle(PlanBaseButtonStyle(.secondary))
                        .padding(.top, 8)
                } label: {
                    Label(
                        review.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "이날의 회고" : review.title, systemImage: "text.book.closed"
                    )
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .foregroundStyle(AppTheme.secondaryText)
                }
            } else {
                Button(action: onEditReview) {
                    Label("회고 남기기", systemImage: "square.and.pencil")
                }
                .buttonStyle(PlanBaseButtonStyle(.secondary))
                .accessibilityIdentifier("archive-add-review-\(group.dayKey)")
            }
        }
        .padding(20)
        .foregroundStyle(AppTheme.primaryText)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border, lineWidth: 1) }
        .onAppear { revealSearchMatches() }
        .onChange(of: presentation) { _, _ in revealSearchMatches() }
    }

    private func revealSearchMatches() {
        if presentation.shouldExpandTaskListForSearch { isTaskListExpanded = true }
        if presentation.reviewMatchesSearch { reviewExpanded = true }
    }

    private var header: some View {
        Button(action: onOpenDay) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(presentation.displayDate)
                        .font(.system(size: 17, weight: .bold))
                    Text(presentation.summaryText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("archive-open-day-\(presentation.dayKey)")
        .accessibilityLabel("\(presentation.displayDate), \(presentation.summaryText)")
        .accessibilityHint("이 날짜의 전체 활동 기록을 엽니다")
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

    private var previewTasks: [Task] {
        let ordered = group.tasks.sorted { lhs, rhs in
            let leftMatch = presentation.taskMatchesSearch(lhs.id)
            let rightMatch = presentation.taskMatchesSearch(rhs.id)
            if leftMatch != rightMatch { return leftMatch }
            return false
        }
        return isTaskListExpanded ? ordered : Array(ordered.prefix(3))
    }

    private var taskPreview: some View {
        VStack(spacing: 0) {
            ForEach(Array(previewTasks.enumerated()), id: \.element.id) { index, task in
                Button {
                    onOpenTask(task.id)
                } label: {
                    ArchiveTaskRow(
                        task: task,
                        isSearchMatch: presentation.taskMatchesSearch(task.id),
                        matchedChecklistItemIDs: presentation.matchedChecklistItemIDs
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("archive-task-\(task.id.uuidString)")
                .accessibilityLabel("\(task.title), \(TaskHistoryDatePresentation(task: task).text)")
                .accessibilityHint("작업의 생성 시각과 활동 기록을 엽니다")
                if index < previewTasks.count - 1 { Divider().overlay(AppTheme.border) }
            }
            if group.tasks.count > 3 {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) { isTaskListExpanded.toggle() }
                } label: {
                    Label(
                        isTaskListExpanded ? "간략히 보기" : "작업 \(group.tasks.count - 3)개 더 보기",
                        systemImage: isTaskListExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.secondaryText)
                .accessibilityIdentifier("archive-task-disclosure-\(group.dayKey)")
            }
        }
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
                ArchiveReviewAsyncImage(request: item.request, accessibilityLabel: "회고 사진 \(safeIndex + 1)")
                    .id(item.id)
            } else {
                ArchiveReviewMissingImage()
            }

            if items.count > 1 {
                HStack {
                    if safeIndex > 0 {
                        navigationButton(systemImage: "chevron.left", label: "이전 사진") {
                            selectedIndex = safeIndex - 1
                        }
                    }
                    Spacer()
                    if safeIndex < items.count - 1 {
                        navigationButton(systemImage: "chevron.right", label: "다음 사진") {
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
                    .accessibilityLabel("사진 위치")
                    .accessibilityValue("\(items.count)장 중 \(safeIndex + 1)번째")
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
        let canonicalFileNames = Set(
            attachments.compactMap {
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
            !value.isEmpty
        else {
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
        .accessibilityLabel(label)
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
    var accessibilityLabel: String
    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 420)
                    .background(AppTheme.input)
                    .accessibilityLabel(accessibilityLabel)
            } else if isLoading {
                ProgressView("사진 불러오는 중")
                    .tint(AppTheme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .background(AppTheme.input)
            } else {
                ArchiveReviewMissingImage()
            }
        }
        .task(id: request.cacheKey) {
            image = nil
            isLoading = true
            let loadedImage = await DiaryImageStore.previewImage(for: request)
            guard !Swift.Task.isCancelled else { return }
            image = loadedImage
            isLoading = false
        }
    }
}

private struct ArchiveReviewMissingImage: View {
    var body: some View {
        Rectangle()
            .fill(AppTheme.input)
            .frame(height: 160)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("사진을 불러올 수 없습니다.")
                        .font(.callout)
                }
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

    private var datePresentation: TaskHistoryDatePresentation {
        TaskHistoryDatePresentation(task: task)
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
                        .fixedSize(horizontal: false, vertical: true)
                    if isSearchMatch {
                        Text("일치")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.onAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.accentFill, in: Capsule())
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
                    Text(datePresentation.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(datePresentation.accessibilityLabel)
                        .accessibilityHint(datePresentation.bestEffortExplanation ?? "")
                    TaskChecklistProgressLabel(taskID: task.id)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.horizontal, 2)
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
