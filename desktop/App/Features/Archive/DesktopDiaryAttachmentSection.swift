import PlanBaseCore
import SwiftUI

struct DesktopDiaryAttachmentSection: View {
    let images: [DiaryImageItem]
    @Binding var selectedImageIndex: Int
    let isImportingImages: Bool
    let isSaving: Bool
    let hasLegacyImageReferences: Bool
    let attachmentDraftCount: Int
    let canRemoveSelectedImage: Bool
    let onAddImages: () -> Void
    let onRemoveSelectedImage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("사진")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)

                if !images.isEmpty {
                    Text("\(selectedImageIndex + 1)/\(images.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .accessibilityLabel("사진 위치")
                        .accessibilityValue("\(images.count)장 중 \(selectedImageIndex + 1)번째")
                }

                Spacer()

                Button(action: onAddImages) {
                    HStack(spacing: 8) {
                        if isImportingImages {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "photo.badge.plus")
                        }
                        Text(isImportingImages ? "사진 추가 중" : "사진 추가")
                    }
                }
                .buttonStyle(PlanBaseButtonStyle(.secondary))
                .disabled(
                    isImportingImages ||
                        isSaving ||
                        hasLegacyImageReferences ||
                        attachmentDraftCount >= DiaryAttachmentService.maximumAttachmentCount
                )
                .help(hasLegacyImageReferences ? "이전 사진을 정리한 뒤 추가할 수 있습니다" : "사진 추가")
            }

            if !images.isEmpty {
                imagePreview
            }

            if !hasLegacyImageReferences,
               attachmentDraftCount >= DiaryAttachmentService.maximumAttachmentCount {
                Text("사진은 최대 \(DiaryAttachmentService.maximumAttachmentCount)장까지 추가할 수 있어요.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var imagePreview: some View {
        ZStack {
            if let image = images[safe: selectedImageIndex] {
                DiaryImageView(request: image.request, accessibilityLabel: "회고 사진 \(selectedImageIndex + 1)")
                    .id(image.id)
            }

            VStack {
                HStack {
                    Spacer()

                    if canRemoveSelectedImage {
                        Button(role: .destructive, action: onRemoveSelectedImage) {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 34, height: 34)
                                .background(.black.opacity(0.52), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .accessibilityLabel("회고 사진 \(selectedImageIndex + 1) 삭제")
                        .accessibilityHint("저장하면 삭제가 반영됩니다")
                        .help("현재 사진 삭제")
                    }
                }

                Spacer()
            }
            .padding(10)

            HStack {
                if selectedImageIndex > 0 {
                    carouselButton(systemName: "chevron.left", label: "이전 사진") {
                        moveImageSelection(-1)
                    }
                }

                Spacer()

                if selectedImageIndex < images.count - 1 {
                    carouselButton(systemName: "chevron.right", label: "다음 사진") {
                        moveImageSelection(1)
                    }
                }
            }
            .padding(.horizontal, 10)

            if images.count > 1 {
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
            ForEach(images.indices, id: \.self) { index in
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
        .accessibilityHidden(true)
    }

    private func carouselButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.46), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .accessibilityLabel(label)
        .help(label)
    }

    private func moveImageSelection(_ offset: Int) {
        guard !images.isEmpty else { return }
        let nextIndex = selectedImageIndex + offset
        selectedImageIndex = min(max(nextIndex, 0), images.count - 1)
    }
}
