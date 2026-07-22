import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import PlanBaseCore

struct DiaryPreviewImageRequest: Sendable {
    enum Source: Sendable {
        case data(Data)
        case file(URL)
    }

    let cacheKey: String
    let source: Source
}

struct DiaryResolvedLegacyImage: Sendable {
    let index: Int
    let normalizedFileName: String
    let fileURL: URL
}

enum DiaryImageStore {
    private static let appSupportFolder =
        PlanBaseCompatibility.legacyDesktopImageFolderName
    private static let previewMaxPixelSize = 1_600

    static var directoryURL: URL {
        DiaryImageFileStore.directoryURL(appSupportFolder: appSupportFolder)
    }

    static func imageURL(for fileName: String) -> URL {
        DiaryImageFileStore.imageURL(for: fileName, appSupportFolder: appSupportFolder)
    }

    static func attachmentPreviewCacheKey(instanceID: UUID, sha256: String) -> String {
        "diary-attachment-\(instanceID.uuidString)-\(sha256)"
    }

    static func filePreviewCacheKey(for fileURL: URL) -> String {
        "diary-file-\(fileURL.standardizedFileURL.path)"
    }

    @MainActor
    static func chooseImageDrafts() async throws -> [DiaryAttachmentDraft] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return [] }
        let sourceURLs = panel.urls

        return try await Swift.Task.detached(priority: .userInitiated) {
            try sourceURLs.map { sourceURL in
                try autoreleasepool {
                    try readDraft(from: sourceURL)
                }
            }
        }.value
    }

    @MainActor
    static func previewImage(for request: DiaryPreviewImageRequest) async -> NSImage? {
        await DiaryPreviewImageCache.shared.image(
            for: request,
            maxPixelSize: previewMaxPixelSize
        )
    }

    static func resolveLegacyImages(
        fileNames: [String],
        canonicalFileNames: Set<String>,
        canonicalHashes: Set<String>
    ) async -> [DiaryResolvedLegacyImage] {
        await Swift.Task.detached(priority: .utility) {
            var resolved: [DiaryResolvedLegacyImage] = []
            var seenFileNames: Set<String> = []
            var seenHashes: Set<String> = []

            for (index, fileName) in fileNames.enumerated() {
                guard !Swift.Task.isCancelled else { break }
                guard let normalizedFileName = normalizedFileName(fileName) else { continue }

                let fileURL = imageURL(for: fileName)
                let hash: String? = autoreleasepool {
                    guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else {
                        return nil
                    }
                    return (try? DiaryAttachmentService.inspect(data))?.sha256
                }
                let duplicatesCanonical = canonicalFileNames.contains(normalizedFileName) ||
                    hash.map(canonicalHashes.contains) == true
                let duplicatesLegacy = !seenFileNames.insert(normalizedFileName).inserted ||
                    hash.map { !seenHashes.insert($0).inserted } == true
                guard !duplicatesCanonical, !duplicatesLegacy else { continue }

                resolved.append(DiaryResolvedLegacyImage(
                    index: index,
                    normalizedFileName: normalizedFileName,
                    fileURL: fileURL
                ))
            }
            return resolved
        }.value
    }

    private static func readDraft(from sourceURL: URL) throws -> DiaryAttachmentDraft {
        let isAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        if let fileSize = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize > DiaryAttachmentService.maximumImageSizeBytes {
            throw DiaryAttachmentServiceError.fileTooLarge(
                actualBytes: fileSize,
                maximumBytes: DiaryAttachmentService.maximumImageSizeBytes
            )
        }

        let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        _ = try DiaryAttachmentService.inspect(data)
        return DiaryAttachmentDraft(data: data, originalFileName: sourceURL.lastPathComponent)
    }

    private static func normalizedFileName(_ fileName: String) -> String? {
        let value = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value.lowercased()
    }

    fileprivate static func downsampledImage(
        from source: DiaryPreviewImageRequest.Source,
        maxPixelSize: Int
    ) -> CGImage? {
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        let imageSource: CGImageSource?
        switch source {
        case .data(let data):
            imageSource = CGImageSourceCreateWithData(data as CFData, sourceOptions)
        case .file(let fileURL):
            imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions)
        }
        guard let imageSource else { return nil }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions)
    }
}

@MainActor
private final class DiaryPreviewImageCache {
    static let shared = DiaryPreviewImageCache()

    private let images = NSCache<NSString, NSImage>()
    private var inFlight: [String: Swift.Task<CGImage?, Never>] = [:]

    private init() {
        images.countLimit = 48
        images.totalCostLimit = 96 * 1_024 * 1_024
    }

    func image(
        for request: DiaryPreviewImageRequest,
        maxPixelSize: Int
    ) async -> NSImage? {
        let key = request.cacheKey as NSString
        if let cachedImage = images.object(forKey: key) {
            return cachedImage
        }

        let task: Swift.Task<CGImage?, Never>
        if let existingTask = inFlight[request.cacheKey] {
            task = existingTask
        } else {
            task = Swift.Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    DiaryImageStore.downsampledImage(
                        from: request.source,
                        maxPixelSize: maxPixelSize
                    )
                }
            }
            inFlight[request.cacheKey] = task
        }

        guard let cgImage = await task.value else {
            inFlight[request.cacheKey] = nil
            return nil
        }
        inFlight[request.cacheKey] = nil

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        let cost = cgImage.bytesPerRow * cgImage.height
        images.setObject(image, forKey: key, cost: cost)
        return image
    }
}
