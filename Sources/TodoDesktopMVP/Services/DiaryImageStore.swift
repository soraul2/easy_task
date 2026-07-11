import AppKit
import Foundation
import UniformTypeIdentifiers
import EasyTaskCore

enum DiaryImageStore {
    private static let appSupportFolder = "TodoDesktopMVP"

    static var directoryURL: URL {
        DiaryImageFileStore.directoryURL(appSupportFolder: appSupportFolder)
    }

    static func imageURL(for fileName: String) -> URL {
        DiaryImageFileStore.imageURL(for: fileName, appSupportFolder: appSupportFolder)
    }

    @MainActor
    static func chooseImageDrafts() throws -> [DiaryAttachmentDraft] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return [] }
        return try panel.urls.map(readDraft)
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
}
