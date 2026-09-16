#if os(iOS)
import PlanBaseCore
import Foundation
import PhotosUI
import SwiftData
import SwiftUI

struct MobileReviewAttachmentDraft: Identifiable, Sendable {
    var id: UUID
    var draft: DiaryAttachmentDraft
    var attachmentHash: String?
}

private struct MobileReviewComposerSnapshot: Equatable {
    var title: String
    var content: String
    var attachmentIDs: [UUID]
    var legacyImageFileNames: [String]
}

struct MobileReviewComposerSheet: View {
    var selectedDate: Date
    var onSaved: (String) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var reviews: [DailyReview]
    @Query private var selectedDayTaskRows: [TodoTask]
    @Query private var completedAtTaskRows: [TodoTask]
    @Query private var archivedFallbackTaskRows: [TodoTask]
    @Query private var carryoverTaskRows: [TodoTask]
    @State private var title = ""
    @State private var content = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var attachmentDrafts: [MobileReviewAttachmentDraft] = []
    @State private var legacyImageFileNames: [String] = []
    @State private var selectedImageIndex = 0
    @State private var message: String?
    @State private var messageIsError = false
    @State private var isImportingImages = false
    @State private var isSaving = false
    @State private var hasLoaded = false
    @State private var loadFailure: String?
#if DEBUG
    @State private var didSimulateLoadFailure = false
#endif
    @State private var initialSnapshot: MobileReviewComposerSnapshot?
    @State private var showsDiscardConfirmation = false
    @FocusState private var focusedField: MobileReviewComposerField?

    init(
        selectedDate: Date,
        onSaved: @escaping (String) -> Void = { _ in }
    ) {
        self.selectedDate = selectedDate
        self.onSaved = onSaved
        let dayKey = DayKey.key(for: selectedDate)
        _reviews = Query(BoundedQueryService.dailyReviewsDescriptor(dayKey: dayKey))
        _selectedDayTaskRows = Query(
            BoundedQueryService.boardTasksDescriptor(selectedDayKey: dayKey)
        )
        _completedAtTaskRows = Query(
            BoundedQueryService.dailyReviewCompletedAtTasksDescriptor(dayKey: dayKey)
        )
        _archivedFallbackTaskRows = Query(
            BoundedQueryService.dailyReviewArchivedFallbackTasksDescriptor(dayKey: dayKey)
        )
        _carryoverTaskRows = Query(
            BoundedQueryService.carryoverTasksDescriptor(before: dayKey)
        )
    }

    private var dayKey: String { DayKey.key(for: selectedDate) }

    private var selectedReview: DailyReview? {
        reviews
            .filter { $0.supersededAt == nil && $0.dayKey == dayKey }
            .max {
                if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt < $1.updatedAt
                }
                return $0.instanceID.uuidString < $1.instanceID.uuidString
            }
    }

    private var canSave: Bool {
        guard hasLoaded, !isImportingImages, !isSaving else { return false }
        return selectedReview != nil ||
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !attachmentDrafts.isEmpty
    }

    private var remainingAttachmentCount: Int {
        guard legacyImageFileNames.isEmpty else { return 0 }
        return max(DiaryAttachmentService.maximumAttachmentCount - attachmentDrafts.count, 0)
    }

    private var attachmentCount: Int {
        attachmentDrafts.count + legacyImageFileNames.count
    }

    private var taskSummary: DailyReviewTaskSummary {
        var rows = selectedDayTaskRows
        rows.append(contentsOf: completedAtTaskRows)
        rows.append(contentsOf: archivedFallbackTaskRows)
        if dayKey == DayKey.today {
            rows.append(contentsOf: carryoverTaskRows)
        }
        return DailyReviewTaskSummaryRules.summary(
            from: rows,
            selectedDayKey: dayKey,
            includeCarryoverOnToday: true
        )
    }

    private var currentSnapshot: MobileReviewComposerSnapshot {
        MobileReviewComposerSnapshot(
            title: title,
            content: content,
            attachmentIDs: attachmentDrafts.map(\.id),
            legacyImageFileNames: legacyImageFileNames
        )
    }

    private var hasUnsavedChanges: Bool {
        guard let initialSnapshot else { return false }
        return currentSnapshot != initialSnapshot
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let loadFailure {
                        MobileNoticeBanner(message: loadFailure, tone: .error)
                        Button("다시 시도", action: load)
                            .buttonStyle(PlanBaseButtonStyle())
                            .accessibilityIdentifier("review-load-retry")
                    } else {
                    ReviewComposerHeader(
                        title: $title,
                        selectedDate: selectedDate,
                        focusedField: $focusedField
                    )
                    ReviewComposerPromptPicker(
                        content: content,
                        onSelect: addWritingPrompt
                    )
                    ReviewComposerEditor(
                        content: $content,
                        focusedField: $focusedField
                    )
                    ReviewComposerTaskSummary(
                        summary: taskSummary,
                        selectedDate: selectedDate
                    )
                    mediaSection
                    statusMessage
                    saveGuidance
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(selectedReview == nil ? "회고 작성" : "회고 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: requestDismiss)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .accessibilityLabel("회고 저장 중")
                    } else {
                        Button("저장", action: save)
                            .disabled(!canSave)
                            .accessibilityIdentifier("review-save-button")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("키보드 닫기") {
                        focusedField = nil
                    }
                }
            }
            .onAppear(perform: load)
            .onChange(of: selectedItems) {
                importImages()
            }
        }
        .planBaseDiscardConfirmation(
            isPresented: $showsDiscardConfirmation,
            hasUnsavedChanges: hasUnsavedChanges,
            isSaving: isSaving,
            message: "저장하지 않은 회고 내용과 사진 변경사항이 사라집니다.",
            onDiscard: discardAndDismiss
        )
        // Keep a stable status-bar preference while the editor and keyboard
        // rotate together; implicit child preferences can cycle on iOS 26.5.
        .statusBarHidden(false)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("사진", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.primaryText)

                Spacer()

                Text("\(attachmentCount)/\(DiaryAttachmentService.maximumAttachmentCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityLabel("첨부한 사진")
                    .accessibilityValue("\(attachmentCount)장, 최대 \(DiaryAttachmentService.maximumAttachmentCount)장")
            }

            Text("기억하고 싶은 장면이 있다면 함께 남겨보세요.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            ReviewComposerImages(
                attachmentDrafts: attachmentDrafts,
                legacyImageFileNames: legacyImageFileNames,
                selectedImageIndex: $selectedImageIndex,
                allowsCanonicalDeletion: legacyImageFileNames.isEmpty,
                onDeleteCanonical: removeCanonicalImage,
                onDeleteLegacy: removeLegacyImages
            )

            imagePicker

            if legacyImageFileNames.isEmpty,
               attachmentDrafts.count >= DiaryAttachmentService.maximumAttachmentCount {
                Text("사진은 최대 \(DiaryAttachmentService.maximumAttachmentCount)장까지 추가할 수 있어요.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .accessibilityIdentifier("review-media-section")
    }

    private var imagePicker: some View {
        let importingImages = isImportingImages
        return PhotosPicker(
            selection: $selectedItems,
            maxSelectionCount: max(remainingAttachmentCount, 1),
            matching: .images
        ) {
            HStack(spacing: 8) {
                if importingImages {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "photo")
                }
                Text(importingImages ? "사진 추가 중" : "사진 추가")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlanBaseButtonStyle(.secondary))
        .disabled(remainingAttachmentCount == 0 || isImportingImages || isSaving)
        .accessibilityIdentifier("review-add-image-button")
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let message {
            MobileNoticeBanner(message: message, tone: messageIsError ? .error : .success)
            .accessibilityIdentifier("review-status-message")
        }
    }

    @ViewBuilder
    private var saveGuidance: some View {
        if selectedReview == nil,
           !canSave,
           !isImportingImages,
           !isSaving {
            Label(
                "글이나 사진을 하나만 남겨도 저장할 수 있어요.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("review-save-guidance")
        }
    }

    private func load() {
        guard !hasLoaded else { return }
        let review = selectedReview
        let orderedAttachments: [DiaryAttachment]
        let diaryBlocks: [DiaryBlock]
        do {
#if DEBUG
            if review != nil, !didSimulateLoadFailure,
               ProcessInfo.processInfo.arguments.contains("--ui-testing"),
               ProcessInfo.processInfo.arguments.contains("--ui-testing-review-load-failure-once") {
                didSimulateLoadFailure = true
                throw CocoaError(.fileReadUnknown)
            }
#endif
            if let review {
                orderedAttachments = try modelContext.fetch(
                    BoundedQueryService.diaryAttachmentsDescriptor(
                        reviewID: review.id
                    )
                )
                diaryBlocks = try modelContext.fetch(
                    BoundedQueryService.diaryBlocksDescriptor(reviewID: review.id)
                )
            } else {
                orderedAttachments = []
                diaryBlocks = []
            }
        } catch {
            hasLoaded = false
            loadFailure = "회고를 불러오지 못했어요. 다시 시도해 주세요."
            return
        }

        title = review?.title ?? ""
        content = review?.content ?? ""
        attachmentDrafts = orderedAttachments.map { attachment in
            MobileReviewAttachmentDraft(
                id: attachment.instanceID,
                draft: DiaryAttachmentDraft(attachment: attachment),
                attachmentHash: attachment.sha256
            )
        }
        legacyImageFileNames = review.map {
            DiaryAttachmentService.unresolvedLegacyImageFileNames(
                for: $0,
                blocks: diaryBlocks,
                attachments: orderedAttachments
            )
        } ?? []
        selectedImageIndex = 0
        message = nil
        messageIsError = false
        isImportingImages = false
        isSaving = false
        hasLoaded = true
        loadFailure = nil
        initialSnapshot = currentSnapshot
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        message = nil

        do {
            let savedReview: DailyReview?
            if legacyImageFileNames.isEmpty {
                savedReview = try DiaryAttachmentService.saveReview(
                    review: selectedReview,
                    dayKey: dayKey,
                    title: title,
                    content: content,
                    attachments: attachmentDrafts.map(\.draft),
                    in: modelContext
                )
            } else {
                savedReview = try saveLegacyReview()
            }
            guard savedReview != nil else {
                isSaving = false
                message = "저장하지 못했어요. 입력한 내용은 그대로예요. 잠시 후 다시 시도해 주세요."
                messageIsError = true
                return
            }

            let successMessage = "회고가 저장됐어요"
            message = successMessage
            messageIsError = false
            isSaving = false
            initialSnapshot = currentSnapshot
            focusedField = nil
            onSaved(successMessage)
            dismiss()
        } catch {
            isSaving = false
            message = "저장하지 못했어요. 입력한 내용은 그대로예요. 잠시 후 다시 시도해 주세요."
            messageIsError = true
        }
    }

    private func addWritingPrompt(_ prompt: DailyReviewWritingPrompt) {
        content = DailyReviewWritingRules.appending(prompt, to: content)
        focusedField = .content
    }

    private func saveLegacyReview() throws -> DailyReview? {
        try PersistenceCommandService.perform(in: modelContext) {
            DailyReviewService.save(
                review: selectedReview,
                dayKey: dayKey,
                title: title,
                content: content,
                imageFileNames: legacyImageFileNames,
                in: modelContext
            )
        }
    }

    private func importImages() {
        let items = selectedItems
        selectedItems = []
        guard !items.isEmpty else { return }
        isImportingImages = true

        Swift.Task {
            var imported: [MobileReviewAttachmentDraft] = []
            var failureMessages: [String] = []
            for item in items {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        failureMessages.append("선택한 사진 데이터를 읽을 수 없습니다.")
                        continue
                    }
                    let metadata = try await Swift.Task.detached(priority: .userInitiated) {
                        try DiaryAttachmentService.inspect(data)
                    }.value
                    imported.append(MobileReviewAttachmentDraft(
                        id: UUID(),
                        draft: DiaryAttachmentDraft(data: data),
                        attachmentHash: metadata.sha256
                    ))
                } catch {
                    failureMessages.append(error.localizedDescription)
                }
            }

            let accepted = Array(imported.prefix(remainingAttachmentCount))
            let overflowCount = imported.count - accepted.count
            if overflowCount > 0 {
                failureMessages.append(
                    DiaryAttachmentServiceError.tooManyAttachments(
                        actual: attachmentDrafts.count + imported.count,
                        maximum: DiaryAttachmentService.maximumAttachmentCount
                    ).localizedDescription
                )
            }

            let firstImportedIndex = attachmentDrafts.count
            attachmentDrafts.append(contentsOf: accepted)
            if !accepted.isEmpty {
                selectedImageIndex = firstImportedIndex
            }

            let failedCount = failureMessages.count + max(overflowCount - 1, 0)
            isImportingImages = false
            guard !accepted.isEmpty else {
                message = failureMessages.first ?? "사진을 가져오지 못했어요"
                messageIsError = true
                return
            }
            if failedCount > 0 {
                let detail = failureMessages.first.map { " \($0)" } ?? ""
                message = "사진 \(accepted.count)장 추가됨, \(failedCount)장 실패.\(detail)"
                messageIsError = true
            } else {
                message = accepted.count == 1 ? "사진을 추가했어요. 저장하면 반영됩니다." : "사진 \(accepted.count)장을 추가했어요. 저장하면 반영됩니다."
                messageIsError = false
            }
        }
    }

    private func removeCanonicalImage(at index: Int) {
        guard legacyImageFileNames.isEmpty else { return }
        guard attachmentDrafts.indices.contains(index) else { return }
        attachmentDrafts.remove(at: index)
        selectedImageIndex = min(selectedImageIndex, max(attachmentDrafts.count - 1, 0))
        message = "사진을 삭제했어요. 저장하면 반영됩니다."
        messageIsError = false
    }

    private func removeLegacyImages(at indexes: [Int]) {
        let validIndexes = indexes
            .filter(legacyImageFileNames.indices.contains)
            .sorted(by: >)
        guard !validIndexes.isEmpty else { return }
        for index in validIndexes {
            legacyImageFileNames.remove(at: index)
        }
        selectedImageIndex = min(
            selectedImageIndex,
            max(attachmentDrafts.count + legacyImageFileNames.count - 1, 0)
        )
        message = legacyImageFileNames.isEmpty
            ? "이전 사진을 모두 정리했어요. 저장하면 백업할 수 있습니다."
            : "이전 사진을 삭제했어요. 저장하면 반영됩니다."
        messageIsError = false
    }

    private func requestDismiss() {
        focusedField = nil
        if hasUnsavedChanges {
            showsDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func discardAndDismiss() {
        initialSnapshot = currentSnapshot
        focusedField = nil
        dismiss()
    }
}

#endif
