import Foundation

public enum DiaryImageFileStore {
    public static func directoryURL(appSupportFolder: String) -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent(appSupportFolder, isDirectory: true)
            .appendingPathComponent("DiaryImages", isDirectory: true)
    }

    public static func imageURL(for fileName: String, appSupportFolder: String) -> URL {
        directoryURL(appSupportFolder: appSupportFolder).appendingPathComponent(fileName)
    }

    public static func copyImage(from sourceURL: URL, appSupportFolder: String) throws -> String {
        try FileManager.default.createDirectory(
            at: directoryURL(appSupportFolder: appSupportFolder),
            withIntermediateDirectories: true
        )

        let fileExtension = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = imageURL(for: fileName, appSupportFolder: appSupportFolder)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return fileName
    }

    public static func writeImageData(
        _ data: Data,
        preferredExtension: String = "jpg",
        appSupportFolder: String
    ) throws -> String {
        try FileManager.default.createDirectory(
            at: directoryURL(appSupportFolder: appSupportFolder),
            withIntermediateDirectories: true
        )

        let fileName = "\(UUID().uuidString).\(preferredExtension)"
        let destinationURL = imageURL(for: fileName, appSupportFolder: appSupportFolder)
        try data.write(to: destinationURL)
        return fileName
    }

    public static func removeImage(fileName: String, appSupportFolder: String) {
        try? FileManager.default.removeItem(at: imageURL(for: fileName, appSupportFolder: appSupportFolder))
    }
}
