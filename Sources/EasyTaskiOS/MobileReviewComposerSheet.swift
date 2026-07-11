#if os(iOS)
import EasyTaskCore
import Foundation
import PhotosUI
import SwiftData
import SwiftUI

private struct MobileReviewAttachmentDraft: Identifiable, Sendable {
    var id: UUID
    var draft: DiaryAttachmentDraft
    var attachmentHash: String?
}

struct MobileReviewComposerSheet: View {
    var selectedDate: Date
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var reviews: [DailyReview]
    @Query private var diaryBlocks: [DiaryBlock]
    @Query private var attachments: [DiaryAttachment]
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
        guard !isImportingImages, !isSaving else { return false }
        return selectedReview != nil ||
            !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !attachmentDrafts.isEmpty
    }

    private var remainingAttachmentCount: Int {
        guard legacyImageFileNames.isEmpty else { return 0 }
        return max(DiaryAttachmentService.maximumAttachmentCount - attachmentDrafts.count, 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ReviewComposerHeader(title: $title, selectedDate: selectedDate)
                    ReviewComposerEditor(content: $content)
                    ReviewComposerImages(
                        attachmentDrafts: attachmentDrafts,
                        legacyImageFileNames: legacyImageFileNames,
                        selectedImageIndex: $selectedImageIndex,
                        allowsCanonicalDeletion: legacyImageFileNames.isEmpty,
                        onDeleteCanonical: removeCanonicalImage,
                        onDeleteLegacy: removeLegacyImages
                    )
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: max(remainingAttachmentCount, 1),
                        matching: .images
                    ) {
                        Label("이미지 추가", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                    .disabled(remainingAttachmentCount == 0 || isImportingImages || isSaving)
                    if let message {
                        Label(
                            message,
                            systemImage: messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                        )
                            .foregroundStyle(messageIsError ? .red : AppTheme.done)
                            .font(.caption.weight(.bold))
                    }
                }
                .padding(16)
            }
            .navigationTitle("회고 작성")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                    .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
            .onChange(of: selectedItems) {
                importImages()
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func load() {
        let review = selectedReview
        let orderedAttachments = review.map {
            DiaryAttachmentService.activeAttachments(for: $0.id, in: attachments)
        } ?? []

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
                attachments: attachments
            )
        } ?? []
        selectedImageIndex = 0
        message = nil
        messageIsError = false
        isImportingImages = false
        isSaving = false
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
                message = "회고를 저장하지 못했어요"
                messageIsError = true
                return
            }

            message = "회고가 저장됐어요"
            messageIsError = false
            Swift.Task { @MainActor in
                try? await Swift.Task<Never, Never>.sleep(nanoseconds: 800_000_000)
                dismiss()
            }
        } catch {
            isSaving = false
            message = error.localizedDescription
            messageIsError = true
        }
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
                        failureMessages.append("선택한 이미지 데이터를 읽을 수 없습니다.")
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
                message = failureMessages.first ?? "이미지를 가져오지 못했어요"
                messageIsError = true
                return
            }
            if failedCount > 0 {
                let detail = failureMessages.first.map { " \($0)" } ?? ""
                message = "이미지 \(accepted.count)개 추가됨, \(failedCount)개 실패.\(detail)"
                messageIsError = true
            } else {
                message = accepted.count == 1 ? "이미지 추가됨" : "이미지 \(accepted.count)개 추가됨"
                messageIsError = false
            }
        }
    }

    private func removeCanonicalImage(at index: Int) {
        guard legacyImageFileNames.isEmpty else { return }
        guard attachmentDrafts.indices.contains(index) else { return }
        attachmentDrafts.remove(at: index)
        selectedImageIndex = min(selectedImageIndex, max(attachmentDrafts.count - 1, 0))
        message = "이미지를 삭제했어요. 저장하면 반영됩니다."
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
            ? "이전 이미지를 모두 정리했어요. 저장하면 백업할 수 있습니다."
            : "이전 이미지를 삭제했어요. 저장하면 반영됩니다."
        messageIsError = false
    }
}

private struct ReviewComposerHeader: View {
    @Binding var title: String
    var selectedDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(DayKey.display(selectedDate), systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("하루 회고", text: $title)
                .font(.headline)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct ReviewComposerEditor: View {
    @Binding var content: String

    var body: some View {
        TextEditor(text: $content)
            .frame(minHeight: 120)
            .padding(8)
            .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topLeading) {
                if content.isEmpty {
                    Text("오늘 하루는 어땠나요?")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct ReviewComposerImages: View {
    var attachmentDrafts: [MobileReviewAttachmentDraft]
    var legacyImageFileNames: [String]
    @Binding var selectedImageIndex: Int
    var allowsCanonicalDeletion: Bool
    var onDeleteCanonical: (Int) -> Void
    var onDeleteLegacy: ([Int]) -> Void
    @State private var legacyResolution = MobileLegacyImageResolution()

    var body: some View {
        let items = mixedImageItems
        VStack(alignment: .leading, spacing: 8) {
            if isResolvingLegacyImages {
                MobileImageLoadingPlaceholder()
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if !items.isEmpty {
                TabView(selection: $selectedImageIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        MobileReviewImagePreview(
                            request: item.thumbnailRequest,
                            placeholderMessage: item.isLegacy
                                ? "이전 이미지를 불러올 수 없음"
                                : "이미지를 불러올 수 없음",
                            accessibilityLabel: "회고 이미지 \(index + 1)",
                            onDelete: deletionAction(for: item)
                        )
                        .tag(index)
                    }
                }
                .frame(height: 260)
                .tabViewStyle(.page)
                .onChange(of: items.count) { _, count in
                    if selectedImageIndex >= count {
                        selectedImageIndex = 0
                    }
                }
            }

            if !allowsCanonicalDeletion, !legacyImageFileNames.isEmpty {
                Label("이전 이미지를 정리하면 새 이미지 추가와 저장된 이미지 삭제를 사용할 수 있어요.", systemImage: "lock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: legacyImageFileNames) {
            let resolution = await MobileLegacyImageResolver.resolve(
                fileNames: legacyImageFileNames
            )
            guard !Swift.Task<Never, Never>.isCancelled else { return }
            legacyResolution = resolution
        }
    }

    private var mixedImageItems: [ReviewComposerImageItem] {
        var items: [ReviewComposerImageItem] = []

        for (index, attachmentDraft) in attachmentDrafts.enumerated() {
            let draft = attachmentDraft.draft
            items.append(ReviewComposerImageItem(
                id: "canonical-\(attachmentDraft.id.uuidString)",
                data: draft.data,
                canonicalIndex: index,
                legacyIndexes: [],
                normalizedFileName: normalizedFileName(draft.originalFileName),
                sha256: attachmentDraft.attachmentHash,
                isLegacy: false
            ))
        }

        for legacyImage in resolvedLegacyImages {
            let normalizedFileName = legacyImage.normalizedFileName
            let hash = legacyImage.attachmentHash
            if let existingIndex = items.firstIndex(where: {
                $0.normalizedFileName == normalizedFileName ||
                    (hash != nil && $0.sha256 == hash)
            }) {
                items[existingIndex].legacyIndexes.append(legacyImage.sourceIndex)
                continue
            }

            items.append(ReviewComposerImageItem(
                id: "legacy-\(normalizedFileName)-\(legacyImage.sourceIndex)",
                data: legacyImage.data,
                canonicalIndex: nil,
                legacyIndexes: [legacyImage.sourceIndex],
                normalizedFileName: normalizedFileName,
                sha256: hash,
                isLegacy: true
            ))
        }
        return items
    }

    private var resolvedLegacyImages: [MobileResolvedLegacyImage] {
        guard legacyResolution.fileNames == legacyImageFileNames else { return [] }
        return legacyResolution.images
    }

    private var isResolvingLegacyImages: Bool {
        !legacyImageFileNames.isEmpty && legacyResolution.fileNames != legacyImageFileNames
    }

    private func deletionAction(for item: ReviewComposerImageItem) -> (() -> Void)? {
        if !item.legacyIndexes.isEmpty {
            return { onDeleteLegacy(item.legacyIndexes) }
        }
        guard allowsCanonicalDeletion, let index = item.canonicalIndex else { return nil }
        return { onDeleteCanonical(index) }
    }

    private func normalizedFileName(_ fileName: String?) -> String? {
        guard let value = fileName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }
}

private struct ReviewComposerImageItem: Identifiable {
    var id: String
    var data: Data?
    var canonicalIndex: Int?
    var legacyIndexes: [Int]
    var normalizedFileName: String?
    var sha256: String?
    var isLegacy: Bool

    var thumbnailRequest: MobileImageThumbnailRequest? {
        guard let data else { return nil }
        return MobileImageThumbnailRequest(
            data: data,
            attachmentHash: sha256,
            dataIdentity: id
        )
    }
}

private struct MobileReviewImagePreview: View {
    var request: MobileImageThumbnailRequest?
    var placeholderMessage: String
    var accessibilityLabel: String
    var onDelete: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MobileAsyncThumbnailImage(
                request: request,
                placeholderMessage: placeholderMessage,
                accessibilityLabel: accessibilityLabel,
                onAspectRatioChange: nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(8)
                        .background(.black.opacity(0.5), in: Circle())
                        .foregroundStyle(.white)
                }
                .padding(10)
                .accessibilityLabel("이미지 삭제")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
#endif
