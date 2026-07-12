#if os(iOS)
import EasyTaskCore
import Foundation
import SwiftUI

struct ReviewComposerHeader: View {
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

struct ReviewComposerEditor: View {
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

struct ReviewComposerImages: View {
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
