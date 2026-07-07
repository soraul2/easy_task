import AppKit
import Foundation
import UniformTypeIdentifiers

enum DiaryImageStore {
    static var directoryURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("TodoDesktopMVP", isDirectory: true)
            .appendingPathComponent("DiaryImages", isDirectory: true)
    }

    static func imageURL(for fileName: String) -> URL {
        directoryURL.appendingPathComponent(fileName)
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
        try? FileManager.default.removeItem(at: imageURL(for: fileName))
    }

    private static func copyImage(from sourceURL: URL) throws -> String {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let fileExtension = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = imageURL(for: fileName)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return fileName
    }
}
