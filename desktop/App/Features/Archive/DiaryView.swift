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
        guard !isImportingImages, !isSaving else { return false }
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
        guard let initialSnapshot else { return false }
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
                    taskSummarySection
                    titleSection
                    contentSection
                    imageSection
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
            Text("저장하지 않은 회고 내용과 이미지 변경사항이 사라집니다.")
        }
    }

    private var dateNavigationHeader: some View {
        HStack(spacing: 12) {
            Button {
                requestDateChange(DayKey.addingDays(-1, to: selectedDate))
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 30, height: 30)
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
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .help("다음 날짜")

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var taskSummarySection: some View {
        DisclosureGroup(isExpanded: $isTaskSummaryExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if taskSummary.isEmpty {
                    Text("이 날짜에 등록된 작업이 없습니다")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                } else {
                    taskGroup(
                        title: "완료",
                        systemImage: "checkmark.circle.fill",
                        color: AppTheme.done,
                        items: taskSummary.completed
                    )
                    taskGroup(
                        title: "진행 중",
                        systemImage: "clock.fill",
                        color: AppTheme.doing,
                        items: taskSummary.inProgress
                    )
                    taskGroup(
                        title: "할 일",
                        systemImage: "circle",
                        color: AppTheme.todo,
                        items: taskSummary.pending
                    )
                }
            }
            .padding(.top, 14)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text("작업 요약")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)

                HStack(spacing: 8) {
                    summaryCountChip(
                        title: "완료",
                        count: taskSummary.completed.count,
                        color: AppTheme.done
                    )
                    summaryCountChip(
                        title: "진행 중",
                        count: taskSummary.inProgress.count,
                        color: AppTheme.doing
                    )
                    summaryCountChip(
                        title: "할 일",
                        count: taskSummary.pending.count,
                        color: AppTheme.todo
                    )
                }
            }
        }
        .tint(AppTheme.secondaryText)
        .padding(16)
        .background(AppTheme.input.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .accessibilityIdentifier("desktop-review-task-summary")
    }

    private func summaryCountChip(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(title) \(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(color.opacity(0.16), in: Capsule())
    }

    @ViewBuilder
    private func taskGroup(
        title: String,
        systemImage: String,
        color: Color,
        items: [DailyReviewTaskSummaryItem]
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.secondaryText)

                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color)
                            .frame(width: 16)

                        Text(item.title)
                            .font(.callout)
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        if let carryoverText = carryoverText(for: item) {
                            Text(carryoverText)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                }
            }
        }
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
        VStack(alignment: .leading, spacing: 10) {
            Text("어디서 시작할까요?")
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            Text("질문을 고르면 회고에 소제목을 만들어드려요.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(DailyReviewWritingPrompt.allCases) { prompt in
                    let isAdded = DailyReviewWritingRules.contains(
                        prompt,
                        in: content
                    )
                    Button {
                        addWritingPrompt(prompt)
                    } label: {
                        Label(
                            prompt.title,
                            systemImage: isAdded ? "checkmark" : "plus"
                        )
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAdded)
                    .accessibilityLabel(
                        isAdded
                            ? "\(prompt.title) 항목 추가됨"
                            : "\(prompt.title) 항목 추가"
                    )
                    .accessibilityHint(
                        isAdded
                            ? ""
                            : "회고 본문에 소제목을 추가하고 입력을 시작합니다"
                    )
                }
            }
        }
        .padding(12)
        .background(AppTheme.input.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .accessibilityIdentifier("desktop-review-writing-prompts")
    }

    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("이미지")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)

                if hasImages {
                    Text("\(selectedImageIndex + 1)/\(displayedImages.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                Button(action: addImages) {
                    if isImportingImages {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("이미지 추가", systemImage: "photo.badge.plus")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(
                    isImportingImages ||
                        isSaving ||
                        hasLegacyImageReferences ||
                        attachmentDrafts.count >= DiaryAttachmentService.maximumAttachmentCount
                )
                .help(hasLegacyImageReferences ? "이전 이미지를 정리한 뒤 추가할 수 있습니다" : "이미지 추가")
            }

            if hasImages {
                inlineImagePreview
            }
        }
    }

    private var inlineImagePreview: some View {
        ZStack {
            if let image = displayedImages[safe: selectedImageIndex] {
                DiaryImageView(request: image.request)
                    .id(image.id)
            }

            VStack {
                HStack {
                    Spacer()

                    if canRemoveSelectedImage {
                        Button(role: .destructive, action: removeSelectedImage) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 30, height: 30)
                                .background(.black.opacity(0.52), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .help("현재 이미지 삭제")
                    }
                }

                Spacer()
            }
            .padding(10)

            HStack {
                if selectedImageIndex > 0 {
                    carouselButton(systemName: "chevron.left") {
                        moveImageSelection(-1)
                    }
                }

                Spacer()

                if selectedImageIndex < displayedImages.count - 1 {
                    carouselButton(systemName: "chevron.right") {
                        moveImageSelection(1)
                    }
                }
            }
            .padding(.horizontal, 10)

            if displayedImages.count > 1 {
                VStack {
                    Spacer()
                    carouselDots
                }
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 10, contentMode: .fit)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    private var carouselDots: some View {
        HStack(spacing: 6) {
            ForEach(displayedImages.indices, id: \.self) { index in
                Circle()
                    .fill(
                        index == selectedImageIndex
                            ? AppTheme.primaryText
                            : AppTheme.secondaryText.opacity(0.45)
                    )
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.floatingBar.opacity(0.86), in: Capsule())
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
                    .foregroundStyle(messageIsError ? .red : AppTheme.done)
                    .lineLimit(2)
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
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.selectedTab)
                .disabled(!canSave)
                .keyboardShortcut("s", modifiers: .command)
                .help("회고 저장 (Command-S)")
                .accessibilityIdentifier("desktop-review-save-button")
            }
        }
    }

    private func carouselButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.46), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func moveImageSelection(_ offset: Int) {
        guard hasImages else { return }
        let nextIndex = selectedImageIndex + offset
        selectedImageIndex = min(max(nextIndex, 0), displayedImages.count - 1)
    }

    private func loadSelectedReview() {
        do {
            reviews = try modelContext.fetch(
                BoundedQueryService.dailyReviewsDescriptor(dayKey: selectedDayKey)
            )
            selectedDayTasks = try modelContext.fetch(
                BoundedQueryService.boardTasksDescriptor(selectedDayKey: selectedDayKey)
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
            message = "회고를 불러오지 못했어요. 잠시 후 다시 열어 주세요."
            messageIsError = true
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
            message = "기존 이미지를 정리한 뒤 새 이미지를 추가할 수 있습니다."
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
                message = "이미지는 최대 \(DiaryAttachmentService.maximumAttachmentCount)개까지 추가할 수 있습니다."
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
                message = "이미지 \(accepted.count)개 추가됨, 최대 개수를 초과한 이미지는 제외했습니다."
                messageIsError = true
            } else {
                message = accepted.count == 1
                    ? "이미지를 추가했습니다. 저장하면 반영됩니다."
                    : "이미지 \(accepted.count)개를 추가했습니다. 저장하면 반영됩니다."
                messageIsError = false
            }
        } catch {
            message = "이미지 추가 실패: \(error.localizedDescription)"
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
                ? "이전 이미지를 모두 정리했습니다. 저장하면 새 이미지를 추가할 수 있습니다."
                : "이전 이미지를 삭제했습니다. 저장하면 반영됩니다."
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
        message = "이미지를 삭제했습니다. 저장하면 반영됩니다."
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

    private func carryoverText(for item: DailyReviewTaskSummaryItem) -> String? {
        guard item.isCarryover,
              let date = DayKey.date(from: item.plannedDayKey) else { return nil }
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return nil }
        return "\(month)월 \(day)일에서 이월"
    }

    private func normalizedFileName(_ fileName: String?) -> String? {
        guard let value = fileName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }
}
