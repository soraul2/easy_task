#if os(iOS)
import EasyTaskCore
import Foundation
import ImageIO
import SwiftUI

typealias TodoTask = EasyTaskCore.Task

enum MobileImageStorage {
    static let appSupportFolder = "EasyTask"
}

enum MobileLayout {
    static let bottomTabClearance: CGFloat = 96
}

struct MobileChecklistProgressChip: View {
    var progress: ChecklistProgress

    var body: some View {
        if !progress.isEmpty {
            Label(
                "\(progress.completedCount)/\(progress.totalCount)",
                systemImage: progress.isComplete ? "checkmark.circle.fill" : "checklist"
            )
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(AppTheme.cardMutedText)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(AppTheme.panel.opacity(0.52), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("checklist-progress")
            .accessibilityLabel("체크리스트 진행률")
            .accessibilityValue(
                "\(progress.completedCount)개 완료, 전체 \(progress.totalCount)개"
            )
        }
    }
}

struct MobileThemeButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "paintpalette")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("테마 선택")
    }
}

struct MobileImageThumbnailRequest: Sendable {
    let data: Data
    let attachmentHash: String?
    let dataIdentity: String

    init(data: Data, attachmentHash: String?, dataIdentity: String) {
        self.data = data
        self.attachmentHash = attachmentHash?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfEmpty
        self.dataIdentity = dataIdentity
    }

    var loadID: String {
        "\(dataIdentity)|\(attachmentHash ?? "unhashed")|\(data.count)"
    }
}

struct MobileResolvedLegacyImage: Sendable {
    let sourceIndex: Int
    let normalizedFileName: String
    let data: Data?
    let attachmentHash: String?
}

struct MobileLegacyImageResolution: Sendable {
    var fileNames: [String] = []
    var images: [MobileResolvedLegacyImage] = []
}

enum MobileLegacyImageResolver {
    static func resolve(fileNames: [String]) async -> MobileLegacyImageResolution {
        let worker = Swift.Task.detached(priority: .utility) {
            var images: [MobileResolvedLegacyImage] = []
            images.reserveCapacity(fileNames.count)

            for (index, fileName) in fileNames.enumerated() {
                guard !Swift.Task<Never, Never>.isCancelled else { break }
                guard let normalizedFileName = mobileNormalizedImageFileName(fileName) else {
                    continue
                }

                let image = autoreleasepool {
                    let data = try? Data(
                        contentsOf: DiaryImageFileStore.imageURL(
                            for: fileName,
                            appSupportFolder: MobileImageStorage.appSupportFolder
                        ),
                        options: [.mappedIfSafe]
                    )
                    let attachmentHash = data.flatMap {
                        (try? DiaryAttachmentService.inspect($0))?.sha256
                    }
                    return MobileResolvedLegacyImage(
                        sourceIndex: index,
                        normalizedFileName: normalizedFileName,
                        data: data,
                        attachmentHash: attachmentHash
                    )
                }
                images.append(image)
            }

            return MobileLegacyImageResolution(fileNames: fileNames, images: images)
        }

        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}

private let mobileThumbnailMaximumPixelSize = 1_280

struct MobileImageThumbnail: @unchecked Sendable {
    let cgImage: CGImage
    let aspectRatio: CGFloat
    let memoryCost: Int
}

private final class MobileImageThumbnailCacheEntry: NSObject {
    let thumbnail: MobileImageThumbnail?

    init(_ thumbnail: MobileImageThumbnail?) {
        self.thumbnail = thumbnail
    }
}

actor MobileImageThumbnailLoader {
    static let shared = MobileImageThumbnailLoader()

    private let cache = NSCache<NSString, MobileImageThumbnailCacheEntry>()
    private var inFlight: [String: Swift.Task<MobileImageThumbnail?, Never>] = [:]

    private init() {
        cache.countLimit = 20
        cache.totalCostLimit = 24 * 1_024 * 1_024
    }

    func thumbnail(for request: MobileImageThumbnailRequest) async -> MobileImageThumbnail? {
        let cacheKey = cacheKey(for: request)
        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached.thumbnail
        }
        if let existingTask = inFlight[cacheKey] {
            return await existingTask.value
        }

        let data = request.data
        let task = Swift.Task.detached(priority: .userInitiated) {
            autoreleasepool {
                mobileDownsampledThumbnail(from: data)
            }
        }
        inFlight[cacheKey] = task

        let thumbnail = await task.value
        inFlight[cacheKey] = nil
        cache.setObject(
            MobileImageThumbnailCacheEntry(thumbnail),
            forKey: cacheKey as NSString,
            cost: thumbnail?.memoryCost ?? 1
        )
        return thumbnail
    }

    private func cacheKey(for request: MobileImageThumbnailRequest) -> String {
        if let attachmentHash = request.attachmentHash {
            return "sha256:\(attachmentHash)"
        }
        return "data-identity:\(request.dataIdentity)|bytes:\(request.data.count)"
    }
}

struct MobileAsyncThumbnailImage: View {
    var request: MobileImageThumbnailRequest?
    var placeholderMessage: String
    var minHeight: CGFloat = 140
    var accessibilityLabel: String
    var onAspectRatioChange: ((CGFloat) -> Void)?

    @State private var loadState: MobileImageThumbnailLoadState?

    var body: some View {
        ZStack {
            AppTheme.input

            if let request {
                if let loadState, loadState.requestID == request.loadID {
                    if let thumbnail = loadState.thumbnail {
                        Image(
                            thumbnail.cgImage,
                            scale: 1,
                            orientation: .up,
                            label: Text(accessibilityLabel)
                        )
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        MobileMissingImagePlaceholder(
                            message: placeholderMessage,
                            minHeight: minHeight
                        )
                    }
                } else {
                    MobileImageLoadingPlaceholder(minHeight: minHeight)
                }
            } else {
                MobileMissingImagePlaceholder(
                    message: placeholderMessage,
                    minHeight: minHeight
                )
            }
        }
        .task(id: request?.loadID) {
            loadState = nil
            guard let request else { return }

            let requestID = request.loadID
            let thumbnail = await MobileImageThumbnailLoader.shared.thumbnail(for: request)
            guard !Swift.Task<Never, Never>.isCancelled else { return }

            loadState = MobileImageThumbnailLoadState(
                requestID: requestID,
                thumbnail: thumbnail
            )
            if let thumbnail {
                onAspectRatioChange?(thumbnail.aspectRatio)
            }
        }
    }
}

struct MobileImageLoadingPlaceholder: View {
    var minHeight: CGFloat = 140

    var body: some View {
        ProgressView()
            .tint(AppTheme.event)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(AppTheme.input)
            .accessibilityLabel("이미지 불러오는 중")
    }
}

private struct MobileImageThumbnailLoadState {
    var requestID: String
    var thumbnail: MobileImageThumbnail?
}

struct MobileMissingImagePlaceholder: View {
    var message: String
    var minHeight: CGFloat = 140

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.title2)
            Text(message)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding()
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private func mobileDownsampledThumbnail(from data: Data) -> MobileImageThumbnail? {
    guard !data.isEmpty,
          let source = CGImageSourceCreateWithData(
              data as CFData,
              [kCGImageSourceShouldCache: false] as CFDictionary
          ),
          CGImageSourceGetCount(source) > 0 else {
        return nil
    }

    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: mobileThumbnailMaximumPixelSize,
        kCGImageSourceShouldCacheImmediately: true
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        options as CFDictionary
    ), cgImage.height > 0 else {
        return nil
    }

    return MobileImageThumbnail(
        cgImage: cgImage,
        aspectRatio: CGFloat(cgImage.width) / CGFloat(cgImage.height),
        memoryCost: cgImage.bytesPerRow * cgImage.height
    )
}

private func mobileNormalizedImageFileName(_ fileName: String?) -> String? {
    guard let value = fileName?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
        return nil
    }
    return value.lowercased()
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
#endif
