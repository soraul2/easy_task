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
    static func chooseAndCopyImages() throws -> [String] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else { return [] }
        return try panel.urls.map(copyImage)
    }

    static func removeImage(fileName: String) {
        DiaryImageFileStore.removeImage(fileName: fileName, appSupportFolder: appSupportFolder)
    }

    private static func copyImage(from sourceURL: URL) throws -> String {
        try DiaryImageFileStore.copyImage(from: sourceURL, appSupportFolder: appSupportFolder)
    }
}
