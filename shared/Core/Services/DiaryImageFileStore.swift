import Foundation

public enum DiaryImageFileStoreError: LocalizedError, Equatable {
    case unsafeFileName(String)
    case unsupportedFileExtension(String)
    case fileTooLarge(actualBytes: Int, maximumBytes: Int)
    case sourceIsNotRegularFile

    public var errorDescription: String? {
        switch self {
        case .unsafeFileName(let fileName):
            return "안전하지 않은 이미지 파일명입니다. fileName=\(fileName)"
        case .unsupportedFileExtension(let fileExtension):
            return "지원하지 않는 이미지 확장자입니다. extension=\(fileExtension)"
        case .fileTooLarge(let actualBytes, let maximumBytes):
            return "이미지 파일이 너무 큽니다. size=\(actualBytes), max=\(maximumBytes)"
        case .sourceIsNotRegularFile:
            return "일반 이미지 파일만 저장할 수 있습니다."
        }
    }
}

public enum DiaryImageFileStore {
    public static let maximumImageSizeBytes = 20 * 1_024 * 1_024
    public static let supportedFileExtensions: Set<String> = ["heic", "jpeg", "jpg", "png"]

    public static func directoryURL(appSupportFolder: String) -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent(appSupportFolder, isDirectory: true)
            .appendingPathComponent("DiaryImages", isDirectory: true)
    }

    public static func imageURL(for fileName: String, appSupportFolder: String) -> URL {
        (try? validatedImageURL(for: fileName, appSupportFolder: appSupportFolder))
            ?? directoryURL(appSupportFolder: appSupportFolder)
                .appendingPathComponent("__rejected_attachment__", isDirectory: false)
    }

    public static func validatedImageURL(for fileName: String, appSupportFolder: String) throws -> URL {
        _ = try validateAttachmentFileName(fileName)

        let directory = directoryURL(appSupportFolder: appSupportFolder).standardizedFileURL
        let destination = directory
            .appendingPathComponent(fileName, isDirectory: false)
            .standardizedFileURL
        guard destination.deletingLastPathComponent() == directory else {
            throw DiaryImageFileStoreError.unsafeFileName(fileName)
        }
        return destination
    }

    @discardableResult
    public static func validateAttachmentFileName(_ fileName: String) throws -> String {
        let trimmedFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let unsafeCharacters = CharacterSet.controlCharacters.union(
            CharacterSet(charactersIn: "/\\:%?#")
        )
        let hasUnsafeCharacter = fileName.unicodeScalars.contains {
            unsafeCharacters.contains($0)
        }
        let nsFileName = fileName as NSString

        guard !fileName.isEmpty,
              fileName == trimmedFileName,
              fileName.utf8.count <= 255,
              !nsFileName.isAbsolutePath,
              !fileName.hasPrefix("~"),
              !hasUnsafeCharacter else {
            throw DiaryImageFileStoreError.unsafeFileName(fileName)
        }

        let fileExtension = nsFileName.pathExtension.lowercased()
        let stem = nsFileName.deletingPathExtension
        let dotComponents = stem.split(separator: ".", omittingEmptySubsequences: false)
        guard !stem.isEmpty,
              !stem.hasPrefix("."),
              !stem.hasSuffix("."),
              dotComponents.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw DiaryImageFileStoreError.unsafeFileName(fileName)
        }

        try validateFileExtension(fileExtension)
        return fileExtension
    }

    public static func storedFileName(importing fileName: String) throws -> String {
        let fileExtension = try validateAttachmentFileName(fileName)
        let stem = (fileName as NSString).deletingPathExtension
        guard UUID(uuidString: stem) == nil else { return fileName }
        return try makeStoredFileName(fileExtension: fileExtension)
    }

    public static func copyImage(from sourceURL: URL, appSupportFolder: String) throws -> String {
        let resourceValues = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard resourceValues.isRegularFile == true else {
            throw DiaryImageFileStoreError.sourceIsNotRegularFile
        }
        if let fileSize = resourceValues.fileSize {
            try validateFileSize(fileSize)
        }

        let fileName = try makeStoredFileName(fileExtension: sourceURL.pathExtension)
        try FileManager.default.createDirectory(
            at: directoryURL(appSupportFolder: appSupportFolder),
            withIntermediateDirectories: true
        )

        let destinationURL = try validatedImageURL(
            for: fileName,
            appSupportFolder: appSupportFolder
        )
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
            if let copiedFileSize = (attributes[.size] as? NSNumber)?.intValue {
                try validateFileSize(copiedFileSize)
            }
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
        return fileName
    }

    public static func writeImageData(
        _ data: Data,
        preferredExtension: String = "jpg",
        appSupportFolder: String
    ) throws -> String {
        try validateFileSize(data.count)
        let fileName = try makeStoredFileName(fileExtension: preferredExtension)
        try FileManager.default.createDirectory(
            at: directoryURL(appSupportFolder: appSupportFolder),
            withIntermediateDirectories: true
        )

        let destinationURL = try validatedImageURL(
            for: fileName,
            appSupportFolder: appSupportFolder
        )
        try data.write(to: destinationURL, options: .atomic)
        return fileName
    }

    public static func removeImage(fileName: String, appSupportFolder: String) {
        guard let imageURL = try? validatedImageURL(
            for: fileName,
            appSupportFolder: appSupportFolder
        ) else { return }
        try? FileManager.default.removeItem(at: imageURL)
    }

    private static func makeStoredFileName(fileExtension: String) throws -> String {
        let normalizedExtension = fileExtension.lowercased()
        guard fileExtension == fileExtension.trimmingCharacters(in: .whitespacesAndNewlines),
              !fileExtension.isEmpty,
              !fileExtension.contains("."),
              !fileExtension.contains("/"),
              !fileExtension.contains("\\") else {
            throw DiaryImageFileStoreError.unsafeFileName(fileExtension)
        }
        try validateFileExtension(normalizedExtension)
        return "\(UUID().uuidString).\(normalizedExtension)"
    }

    private static func validateFileExtension(_ fileExtension: String) throws {
        guard supportedFileExtensions.contains(fileExtension) else {
            throw DiaryImageFileStoreError.unsupportedFileExtension(fileExtension)
        }
    }

    private static func validateFileSize(_ fileSize: Int) throws {
        guard fileSize <= maximumImageSizeBytes else {
            throw DiaryImageFileStoreError.fileTooLarge(
                actualBytes: fileSize,
                maximumBytes: maximumImageSizeBytes
            )
        }
    }
}
