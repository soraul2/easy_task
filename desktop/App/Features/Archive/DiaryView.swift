import AppKit
import PlanBaseCore
import SwiftData
import SwiftUI

private struct DiaryComposerSnapshot: Equatable {
    var title: String
    var content: String
    var attachmentCacheKeys: [String]
    var legacyImageFileNames: [String]
}

private enum DesktopReviewField: Hashable {
    case title
    case content
}

struct DiaryView: View {
    private let composerMaxWidth: CGFloat = 600
    private let showsHeader: Bool
    private let onDirtyChange: (Bool) -> Void
    private let onSaved: (String) -> Void
    private let onSavingChange: (Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var reviews: [DailyReview] = []
    @State private var diaryBlocks: [DiaryBlock] = []
    @State private var attachments: [DiaryAttachment] = []
    @State private var selectedDayTasks: [Task] = []
    @State private var carryoverTasks: [Task] = []

    @State private var selectedDate: Date
    @State private var reviewTitle = ""
    @State private var content = ""
    @State private var attachmentDrafts: [DiaryAttachmentDraft] = []
    @State private var attachmentPreviewCacheKeys: [String] = []
    @State private var legacyImageFileNames: [String] = []
    @State private var selectedImageIndex = 0
    @State private var message: String?
    @State private var messageIsError = false
    @State private var isImportingImages = false
    @State private var isSaving = false
    @State private var loadedDayKey: String?
    @State private var loadFailure: String?
    @State private var initialSnapshot: DiaryComposerSnapshot?
    @State private var isTaskSummaryExpanded = true
    @State private var pendingDate: Date?
    @State private var showsDateChangeConfirmation = false
    @FocusState private var focusedField: DesktopReviewField?

    init(
        initialDate: Date = DayKey.startOfDay(for: Date()),
        showsHeader: Bool = true,
        onDirtyChange: @escaping (Bool) -> Void = { _ in },
        onSaved: @escaping (String) -> Void = { _ in },
        onSavingChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.showsHeader = showsHeader
        self.onDirtyChange = onDirtyChange
        self.onSaved = onSaved
        self.onSavingChange = onSavingChange
        _selectedDate = State(initialValue: DayKey.startOfDay(for: initialDate))
    }

    private var selectedDayKey: String {
        DayKey.key(for: selectedDate)
    }

    private var selectedReview: DailyReview? {
        reviews
            .filter { $0.supersededAt == nil && $0.dayKey == selectedDayKey }
            .max {
                if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt < $1.updatedAt
                }
                return $0.instanceID.uuidString < $1.instanceID.uuidString
            }
    }

    private var selectedAttachments: [DiaryAttachment] {
        guard let selectedReview else { return [] }
        return DiaryAttachmentService.activeAttachments(
            for: selectedReview.id,
            in: attachments
        )
    }

    private var taskSummary: DailyReviewTaskSummary {
        var tasks = selectedDayTasks
        if selectedDayKey == DayKey.today {
            tasks.append(contentsOf: carryoverTasks)
        }
        return DailyReviewTaskSummaryRules.summary(
            from: tasks,
            selectedDayKey: selectedDayKey,
            includeCarryoverOnToday: true
        )
    }

    private var displayedImages: [DiaryImageItem] {
        var images = attachmentDrafts.enumerated().map { index, draft in
            let cacheKey = attachmentPreviewCacheKeys[safe: index] ??
                "diary-attachment-fallback-\(draft.instanceID?.uuidString ?? String(index))-\(draft.data.count)"
            return DiaryImageItem(
                id: cacheKey,
                source: .attachment(index: index),
                request: DiaryPreviewImageRequest(
                    cacheKey: cacheKey,
                    source: .data(draft.data)
                ),
                normalizedFileName: normalizedFileName(draft.originalFileName),
                legacyIndexes: []
            )
        }

        for (index, fileName) in legacyImageFileNames.enumerated() {
            let fileNameKey = normalizedFileName(fileName)
            if let existingIndex = images.firstIndex(where: {
                fileNameKey != nil && $0.normalizedFileName == fileNameKey
            }) {
                images[existingIndex].legacyIndexes.append(index)
                continue
            }
            let fileURL = DiaryImageStore.imageURL(for: fileName)
            let cacheKey = DiaryImageStore.filePreviewCacheKey(for: fileURL)
            images.append(DiaryImageItem(
                id: "\(cacheKey)-\(index)",
                source: .legacyFileName(index: index, fileName: fileName),
                request: DiaryPreviewImageRequest(
                    cacheKey: cacheKey,
                    source: .file(fileURL)
                ),
                normalizedFileName: fileNameKey,
                legacyIndexes: [index]
            ))
        }
        return images
    }

    private var hasImages: Bool {
        !displayedImages.isEmpty
    }

    private var hasLegacyImageReferences: Bool {
        !legacyImageFileNames.isEmpty
    }

    private var canSave: Bool {
        guard loadedDayKey == selectedDayKey, !isImportingImages, !isSaving else { return false }
        return selectedReview != nil || DailyReviewRules.hasContent(
            title: reviewTitle,
            content: content,
            imageFileNames: hasImages ? ["attachment"] : []
        )
    }

    private var currentSnapshot: DiaryComposerSnapshot {
        DiaryComposerSnapshot(
            title: reviewTitle,
            content: content,
            attachmentCacheKeys: attachmentPreviewCacheKeys,
            legacyImageFileNames: legacyImageFileNames
        )
    }

    private var hasUnsavedChanges: Bool {
        guard loadedDayKey == selectedDayKey, let initialSnapshot else { return false }
        return currentSnapshot != initialSnapshot
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                dateNavigationHeader
                Divider()
                    .overlay(AppTheme.border)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let loadFailure {
                        Label(loadFailure, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("다시 시도", action: loadSelectedReview)
                            .buttonStyle(PlanBaseButtonStyle())
                    } else {
                    taskSummarySection
                    titleSection
                    contentSection
                    imageSection
                    }
                }
                .frame(maxWidth: composerMaxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, showsHeader ? 28 : 24)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }

            footer
                .frame(maxWidth: composerMaxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, showsHeader ? 28 : 24)
                .padding(.bottom, 20)
        }
        .background(AppTheme.panel)
        .onAppear(perform: loadSelectedReview)
        .onChange(of: selectedDayKey) {
            loadSelectedReview()
        }
        .onChange(of: currentSnapshot) {
            onDirtyChange(hasUnsavedChanges)
        }
        .onChange(of: displayedImages.count) {
            selectedImageIndex = min(selectedImageIndex, max(displayedImages.count - 1, 0))
        }
        .alert(
            "변경사항을 버리고 날짜를 이동할까요?",
            isPresented: $showsDateChangeConfirmation
        ) {
            Button("변경사항 버리기", role: .destructive, action: confirmDateChange)
            Button("계속 작성", role: .cancel) {
                pendingDate = nil
            }
        } message: {
            Text("저장하지 않은 회고 내용과 사진 변경사항이 사라집니다.")
        }
    }

    private var dateNavigationHeader: some View {
        HStack(spacing: 12) {
            Button {
                requestDateChange(DayKey.addingDays(-1, to: selectedDate))
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .help("이전 날짜")

            Text(DayKey.display(selectedDate))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppTheme.primaryText)
                .frame(minWidth: 210, alignment: .leading)

            Button("오늘") {
                requestDateChange(DayKey.startOfDay(for: Date()))
            }
            .buttonStyle(.bordered)

            Button {
                requestDateChange(DayKey.addingDays(1, to: selectedDate))
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .help("다음 날짜")

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var taskSummarySection: some View {
        DesktopDiaryTaskSummarySection(
            summary: taskSummary,
            selectedDayKey: selectedDayKey,
            isExpanded: $isTaskSummaryExpanded
        )
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("제목 (선택)")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            TextField("하루 회고", text: $reviewTitle)
                .focused($focusedField, equals: .title)
                .diaryTextFieldStyle()
                .accessibilityIdentifier("desktop-review-title-field")
                .onSubmit {
                    focusedField = .content
                }
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("자유 기록")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)

            writingPromptPicker

            ZStack(alignment: .topLeading) {
                TextEditor(text: $content)
                    .focused($focusedField, equals: .content)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.primaryText)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 160, idealHeight: 220, maxHeight: 360)
                    .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppTheme.border, lineWidth: 1)
                    }
                    .accessibilityIdentifier("desktop-review-content-field")

                if content.isEmpty {
                    Text("오늘 하루를 자유롭게 기록해 보세요")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var writingPromptPicker: some View {
        DesktopDiaryWritingPromptPicker(
            content: content,
            onSelect: addWritingPrompt
        )
    }

    private var imageSection: some View {
        DesktopDiaryAttachmentSection(
            images: displayedImages,
            selectedImageIndex: $selectedImageIndex,
            isImportingImages: isImportingImages,
            isSaving: isSaving,
            hasLegacyImageReferences: hasLegacyImageReferences,
            attachmentDraftCount: attachmentDrafts.count,
            canRemoveSelectedImage: canRemoveSelectedImage,
            onAddImages: addImages,
            onRemoveSelectedImage: removeSelectedImage
        )
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Divider()
                .overlay(AppTheme.border)

            HStack(spacing: 12) {
                if let message {
                    Label(
                        message,
                        systemImage: messageIsError
                            ? "exclamationmark.triangle.fill"
                            : "checkmark.circle.fill"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("desktop-review-status-message")
                }

                Spacer()

                Button(action: save) {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isSaving ? "저장 중" : "저장")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                }
                .buttonStyle(PlanBaseButtonStyle())
                .disabled(!canSave)
                .keyboardShortcut("s", modifiers: .command)
                .help("회고 저장 (Command-S)")
                .accessibilityIdentifier("desktop-review-save-button")
            }
        }
    }

    private func loadSelectedReview() {
        guard loadedDayKey != selectedDayKey else { return }
        loadedDayKey = nil
        do {
            reviews = try modelContext.fetch(
                BoundedQueryService.dailyReviewsDescriptor(dayKey: selectedDayKey)
            )
            selectedDayTasks = try BoundedQueryService.dailyReviewTasks(
                dayKey: selectedDayKey,
                in: modelContext
            )
            carryoverTasks = selectedDayKey == DayKey.today
                ? try modelContext.fetch(
                    BoundedQueryService.carryoverTasksDescriptor(before: selectedDayKey)
                )
                : []

            if let review = selectedReview {
                diaryBlocks = try modelContext.fetch(
                    BoundedQueryService.diaryBlocksDescriptor(reviewID: review.id)
                )
                attachments = try modelContext.fetch(
                    BoundedQueryService.diaryAttachmentsDescriptor(reviewID: review.id)
                )
            } else {
                diaryBlocks = []
                attachments = []
            }
        } catch {
            reviews = []
            diaryBlocks = []
            attachments = []
            selectedDayTasks = []
            carryoverTasks = []
            loadFailure = "회고를 불러오지 못했어요. 다시 시도해 주세요."
            return
        }

        if let review = selectedReview {
            DailyReviewService.migrateBlockSummaryIfNeeded(
                for: review,
                blocks: diaryBlocks
            )
        }

        let review = selectedReview
        reviewTitle = review?.title ?? ""
        content = review?.content ?? ""
        let activeAttachments = selectedAttachments
        attachmentDrafts = activeAttachments.map { DiaryAttachmentDraft(attachment: $0) }
        attachmentPreviewCacheKeys = activeAttachments.map {
            DiaryImageStore.attachmentPreviewCacheKey(
                instanceID: $0.instanceID,
                sha256: $0.sha256
            )
        }
        legacyImageFileNames = review.map {
            DiaryAttachmentService.unresolvedLegacyImageFileNames(
                for: $0,
                blocks: diaryBlocks,
                attachments: attachments
            )
        } ?? []
        selectedImageIndex = 0
        isTaskSummaryExpanded = true
        message = nil
        messageIsError = false
        isSaving = false
        loadedDayKey = selectedDayKey
        loadFailure = nil
        initialSnapshot = currentSnapshot
        onSavingChange(false)
        onDirtyChange(false)
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        onSavingChange(true)
        message = nil

        defer {
            isSaving = false
            onSavingChange(false)
        }

        do {
            let savedReview: DailyReview?
            if hasLegacyImageReferences {
                savedReview = try PersistenceCommandService.perform(in: modelContext) {
                    DailyReviewService.save(
                        review: selectedReview,
                        dayKey: selectedDayKey,
                        title: reviewTitle,
                        content: content,
                        imageFileNames: legacyImageFileNames,
                        in: modelContext
                    )
                }
            } else {
                savedReview = try DiaryAttachmentService.saveReview(
                    review: selectedReview,
                    dayKey: selectedDayKey,
                    title: reviewTitle,
                    content: content,
                    attachments: attachmentDrafts,
                    in: modelContext
                )
            }

            guard let savedReview else {
                message = "저장하지 못했어요. 입력한 내용은 그대로예요. 잠시 후 다시 시도해 주세요."
                messageIsError = true
                return
            }

            reviews = try modelContext.fetch(
                BoundedQueryService.dailyReviewsDescriptor(dayKey: selectedDayKey)
            )
            diaryBlocks = try modelContext.fetch(
                BoundedQueryService.diaryBlocksDescriptor(reviewID: savedReview.id)
            )
            attachments = try modelContext.fetch(
                BoundedQueryService.diaryAttachmentsDescriptor(reviewID: savedReview.id)
            )
            if !hasLegacyImageReferences {
                let activeAttachments = DiaryAttachmentService.activeAttachments(
                    for: savedReview.id,
                    in: attachments
                )
                attachmentDrafts = activeAttachments.map {
                    DiaryAttachmentDraft(attachment: $0)
                }
                attachmentPreviewCacheKeys = activeAttachments.map {
                    DiaryImageStore.attachmentPreviewCacheKey(
                        instanceID: $0.instanceID,
                        sha256: $0.sha256
                    )
                }
            }

            let successMessage = "회고가 저장됐어요"
            message = successMessage
            messageIsError = false
            initialSnapshot = currentSnapshot
            focusedField = nil
            onDirtyChange(false)
            onSaved(successMessage)
        } catch {
            modelContext.rollback()
            message = "저장하지 못했어요. 입력한 내용은 그대로예요. 잠시 후 다시 시도해 주세요."
            messageIsError = true
        }
    }

    private func addWritingPrompt(_ prompt: DailyReviewWritingPrompt) {
        content = DailyReviewWritingRules.appending(prompt, to: content)
        focusedField = .content
    }

    private func addImages() {
        Swift.Task { @MainActor in
            await chooseAndAddImages()
        }
    }

    @MainActor
    private func chooseAndAddImages() async {
        guard !isImportingImages else { return }
        guard !hasLegacyImageReferences else {
            message = "기존 사진을 정리한 뒤 새 사진을 추가할 수 있습니다."
            messageIsError = true
            return
        }

        isImportingImages = true
        defer { isImportingImages = false }
        let targetDayKey = selectedDayKey
        do {
            let newDrafts = try await DiaryImageStore.chooseImageDrafts()
            guard selectedDayKey == targetDayKey else { return }
            guard !newDrafts.isEmpty else { return }
            let availableCount = max(
                DiaryAttachmentService.maximumAttachmentCount - attachmentDrafts.count,
                0
            )
            guard availableCount > 0 else {
                message = "사진은 최대 \(DiaryAttachmentService.maximumAttachmentCount)장까지 추가할 수 있어요."
                messageIsError = true
                return
            }
            let accepted = Array(newDrafts.prefix(availableCount))
            let firstNewIndex = attachmentDrafts.count
            attachmentDrafts.append(contentsOf: accepted)
            attachmentPreviewCacheKeys.append(contentsOf: accepted.map { _ in
                "diary-draft-\(UUID().uuidString)"
            })
            selectedImageIndex = firstNewIndex
            if accepted.count < newDrafts.count {
                message = "사진 \(accepted.count)장 추가됨, 최대 개수를 초과한 사진은 제외했어요."
                messageIsError = true
            } else {
                message = accepted.count == 1
                    ? "사진을 추가했어요. 저장하면 반영됩니다."
                    : "사진 \(accepted.count)장을 추가했어요. 저장하면 반영됩니다."
                messageIsError = false
            }
        } catch {
            message = "사진 추가 실패: \(error.localizedDescription)"
            messageIsError = true
        }
    }

    private func removeSelectedImage() {
        guard let image = displayedImages[safe: selectedImageIndex] else { return }
        if !image.legacyIndexes.isEmpty {
            for legacyIndex in image.legacyIndexes
                .filter(legacyImageFileNames.indices.contains)
                .sorted(by: >) {
                legacyImageFileNames.remove(at: legacyIndex)
            }
            selectedImageIndex = min(selectedImageIndex, max(displayedImages.count - 1, 0))
            message = legacyImageFileNames.isEmpty
                ? "이전 사진을 모두 정리했습니다. 저장하면 새 사진을 추가할 수 있습니다."
                : "이전 사진을 삭제했습니다. 저장하면 반영됩니다."
            messageIsError = false
            return
        }

        guard !hasLegacyImageReferences,
              case .attachment(let draftIndex) = image.source,
              attachmentDrafts.indices.contains(draftIndex) else { return }
        attachmentDrafts.remove(at: draftIndex)
        if attachmentPreviewCacheKeys.indices.contains(draftIndex) {
            attachmentPreviewCacheKeys.remove(at: draftIndex)
        }
        selectedImageIndex = min(selectedImageIndex, max(displayedImages.count - 1, 0))
        message = "사진을 삭제했어요. 저장하면 반영됩니다."
        messageIsError = false
    }

    private var canRemoveSelectedImage: Bool {
        guard let image = displayedImages[safe: selectedImageIndex] else { return false }
        if !image.legacyIndexes.isEmpty { return true }
        switch image.source {
        case .attachment:
            return !hasLegacyImageReferences
        case .legacyFileName:
            return true
        }
    }

    private func requestDateChange(_ date: Date) {
        focusedField = nil
        guard DayKey.key(for: date) != selectedDayKey else { return }
        if hasUnsavedChanges {
            pendingDate = date
            showsDateChangeConfirmation = true
        } else {
            selectedDate = DayKey.startOfDay(for: date)
        }
    }

    private func confirmDateChange() {
        guard let pendingDate else { return }
        initialSnapshot = currentSnapshot
        onDirtyChange(false)
        self.pendingDate = nil
        selectedDate = DayKey.startOfDay(for: pendingDate)
    }

    private func normalizedFileName(_ fileName: String?) -> String? {
        guard let value = fileName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }
}
