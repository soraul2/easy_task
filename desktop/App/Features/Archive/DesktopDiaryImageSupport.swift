import AppKit
import PlanBaseCore
import SwiftUI

struct DiaryImageItem: Identifiable {
    var id: String
    var source: DiaryImageSource
    var request: DiaryPreviewImageRequest
    var normalizedFileName: String?
    var legacyIndexes: [Int]
}

enum DiaryImageSource {
    case attachment(index: Int)
    case legacyFileName(index: Int, fileName: String)
}

struct DiaryImageView: View {
    var request: DiaryPreviewImageRequest
    @State private var image: NSImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoading {
                ProgressView()
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.input)
                    .accessibilityLabel("이미지 불러오는 중")
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28, weight: .semibold))
                    Text("이미지를 불러올 수 없습니다.")
                        .font(.callout)
                }
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.input)
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

extension View {
    func diaryTextFieldStyle() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppTheme.primaryText)
            .padding(12)
            .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
