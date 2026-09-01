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
                Text("이미지")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)

                if !images.isEmpty {
                    Text("\(selectedImageIndex + 1)/\(images.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                Button(action: onAddImages) {
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
                        attachmentDraftCount >= DiaryAttachmentService.maximumAttachmentCount
                )
                .help(hasLegacyImageReferences ? "이전 이미지를 정리한 뒤 추가할 수 있습니다" : "이미지 추가")
            }

            if !images.isEmpty {
                imagePreview
            }
        }
    }

    private var imagePreview: some View {
        ZStack {
            if let image = images[safe: selectedImageIndex] {
                DiaryImageView(request: image.request)
                    .id(image.id)
            }

            VStack {
                HStack {
                    Spacer()

                    if canRemoveSelectedImage {
                        Button(role: .destructive, action: onRemoveSelectedImage) {
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

                if selectedImageIndex < images.count - 1 {
                    carouselButton(systemName: "chevron.right") {
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
        guard !images.isEmpty else { return }
        let nextIndex = selectedImageIndex + offset
        selectedImageIndex = min(max(nextIndex, 0), images.count - 1)
    }
}
