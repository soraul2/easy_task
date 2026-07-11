#if os(iOS)
import EasyTaskCore
import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct MobileReviewComposerSheet: View {
    var selectedDate: Date
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var reviews: [DailyReview]
    @Query private var attachments: [DiaryAttachment]
    @State private var title = ""
    @State private var content = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var attachmentDrafts: [DiaryAttachmentDraft] = []
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
                        onDelete: removeImage
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
        attachmentDrafts = orderedAttachments.map {
            DiaryAttachmentDraft(attachment: $0)
        }
        legacyImageFileNames = review?.imageFileNames ?? []
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
                    attachments: attachmentDrafts,
                    in: modelContext
                )
            } else {
                savedReview = DailyReviewService.save(
                    review: selectedReview,
                    dayKey: dayKey,
                    title: title,
                    content: content,
                    imageFileNames: legacyImageFileNames,
                    in: modelContext
                )
                try modelContext.save()
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

    private func importImages() {
        let items = selectedItems
        selectedItems = []
        guard !items.isEmpty else { return }
        isImportingImages = true

        Swift.Task {
            var imported: [DiaryAttachmentDraft] = []
            var failureMessages: [String] = []
            for item in items {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        failureMessages.append("선택한 이미지 데이터를 읽을 수 없습니다.")
                        continue
                    }
                    _ = try DiaryAttachmentService.inspect(data)
                    imported.append(DiaryAttachmentDraft(data: data))
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

    private func removeImage(at index: Int) {
        guard attachmentDrafts.indices.contains(index) else { return }
        attachmentDrafts.remove(at: index)
        selectedImageIndex = min(selectedImageIndex, max(attachmentDrafts.count - 1, 0))
        message = "이미지를 삭제했어요. 저장하면 반영됩니다."
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
    var attachmentDrafts: [DiaryAttachmentDraft]
    var legacyImageFileNames: [String]
    @Binding var selectedImageIndex: Int
    var onDelete: (Int) -> Void

    var body: some View {
        if !attachmentDrafts.isEmpty {
            TabView(selection: $selectedImageIndex) {
                ForEach(Array(attachmentDrafts.enumerated()), id: \.offset) { index, draft in
                    MobileReviewImagePreview(
                        imageData: draft.data,
                        placeholderMessage: "이미지를 불러올 수 없음",
                        onDelete: { onDelete(index) }
                    )
                    .tag(index)
                }
            }
            .frame(height: 260)
            .tabViewStyle(.page)
        } else if !legacyImageFileNames.isEmpty {
            TabView(selection: $selectedImageIndex) {
                ForEach(Array(legacyImageFileNames.enumerated()), id: \.offset) { index, fileName in
                    MobileReviewImagePreview(
                        imageData: legacyImageData(for: fileName),
                        placeholderMessage: "이전 이미지를 불러올 수 없음"
                    )
                    .tag(index)
                }
            }
            .frame(height: 260)
            .tabViewStyle(.page)
        }
    }

    private func legacyImageData(for fileName: String) -> Data? {
        try? Data(
            contentsOf: DiaryImageFileStore.imageURL(
                for: fileName,
                appSupportFolder: MobileImageStorage.appSupportFolder
            ),
            options: [.mappedIfSafe]
        )
    }
}

private struct MobileReviewImagePreview: View {
    var imageData: Data?
    var placeholderMessage: String
    var onDelete: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.input)
            } else {
                MobileMissingImagePlaceholder(message: placeholderMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
