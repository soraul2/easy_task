import CryptoKit
import Foundation
import ImageIO
import SwiftData

public enum DiaryAttachmentMediaType: String, Codable, CaseIterable, Sendable {
    case jpeg = "image/jpeg"
    case png = "image/png"
    case heic = "image/heic"

    public var preferredFileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        }
    }
}

public struct DiaryAttachmentDraft: Equatable, Sendable {
    public var id: UUID?
    public var instanceID: UUID?
    public var data: Data
    public var originalFileName: String?

    public init(
        id: UUID? = nil,
        instanceID: UUID? = nil,
        data: Data,
        originalFileName: String? = nil
    ) {
        self.id = id
        self.instanceID = instanceID
        self.data = data
        self.originalFileName = originalFileName
    }

    public init(attachment: DiaryAttachment) {
        id = attachment.id
        instanceID = attachment.instanceID
        data = attachment.data
        originalFileName = attachment.originalFileName
    }
}

public struct DiaryAttachmentMetadata: Equatable, Sendable {
    public var mediaType: DiaryAttachmentMediaType
    public var byteCount: Int
    public var sha256: String

    public init(mediaType: DiaryAttachmentMediaType, byteCount: Int, sha256: String) {
        self.mediaType = mediaType
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public enum DiaryAttachmentServiceError: LocalizedError, Equatable {
    case emptyData
    case fileTooLarge(actualBytes: Int, maximumBytes: Int)
    case unsupportedImageFormat
    case tooManyAttachments(actual: Int, maximum: Int)
    case invalidReviewID(UUID)
    case invalidAttachmentIdentity(UUID)
    case duplicateAttachmentIdentity(UUID)
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyData:
            return "빈 이미지는 첨부할 수 없습니다."
        case .fileTooLarge(let actualBytes, let maximumBytes):
            return "이미지 파일이 너무 큽니다. size=\(actualBytes), max=\(maximumBytes)"
        case .unsupportedImageFormat:
            return "JPEG, PNG, HEIC 이미지만 첨부할 수 있습니다."
        case .tooManyAttachments(let actual, let maximum):
            return "이미지는 최대 \(maximum)개까지 첨부할 수 있습니다. count=\(actual)"
        case .invalidReviewID(let reviewID):
            return "첨부 대상 회고를 찾을 수 없습니다. reviewID=\(reviewID)"
        case .invalidAttachmentIdentity(let id):
            return "기존 첨부의 식별자가 올바르지 않습니다. id=\(id)"
        case .duplicateAttachmentIdentity(let id):
            return "같은 첨부가 초안에 두 번 포함됐습니다. id=\(id)"
        case .saveFailed(let description):
            return "이미지 첨부를 저장하지 못했습니다. \(description)"
        }
    }
}

public enum DiaryAttachmentService {
    public static let maximumAttachmentCount = 10
    public static let maximumImageSizeBytes = DiaryImageFileStore.maximumImageSizeBytes

    public static func inspect(_ data: Data) throws -> DiaryAttachmentMetadata {
        guard !data.isEmpty else {
            throw DiaryAttachmentServiceError.emptyData
        }
        guard data.count <= maximumImageSizeBytes else {
            throw DiaryAttachmentServiceError.fileTooLarge(
                actualBytes: data.count,
                maximumBytes: maximumImageSizeBytes
            )
        }
        guard let mediaType = detectedMediaType(in: data) else {
            throw DiaryAttachmentServiceError.unsupportedImageFormat
        }
        guard isDecodableImage(data) else {
            throw DiaryAttachmentServiceError.unsupportedImageFormat
        }

        return DiaryAttachmentMetadata(
            mediaType: mediaType,
            byteCount: data.count,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    public static func activeAttachments(
        for reviewID: UUID,
        in attachments: [DiaryAttachment]
    ) -> [DiaryAttachment] {
        attachments
            .filter { $0.reviewId == reviewID && $0.supersededAt == nil }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.instanceID.uuidString < $1.instanceID.uuidString
            }
    }

    @MainActor
    @discardableResult
    public static func replaceAttachments(
        for review: DailyReview,
        with drafts: [DiaryAttachmentDraft],
        in context: ModelContext,
        now: Date = Date()
    ) throws -> [DiaryAttachment] {
        guard drafts.count <= maximumAttachmentCount else {
            throw DiaryAttachmentServiceError.tooManyAttachments(
                actual: drafts.count,
                maximum: maximumAttachmentCount
            )
        }

        let prepared = try drafts.map { draft in
            (draft, try inspect(draft.data))
        }
        let activeReviewExists = try context.fetch(FetchDescriptor<DailyReview>()).contains {
            $0.id == review.id && $0.supersededAt == nil
        }
        guard activeReviewExists else {
            throw DiaryAttachmentServiceError.invalidReviewID(review.id)
        }

        let existing = try context.fetch(FetchDescriptor<DiaryAttachment>())
            .filter { $0.reviewId == review.id && $0.supersededAt == nil }
        var existingByID: [UUID: DiaryAttachment] = [:]
        for attachment in existing {
            guard existingByID[attachment.id] == nil else {
                throw DiaryAttachmentServiceError.duplicateAttachmentIdentity(attachment.id)
            }
            existingByID[attachment.id] = attachment
        }
        var retainedIDs: Set<UUID> = []
        for draft in drafts {
            guard let id = draft.id else {
                if let instanceID = draft.instanceID {
                    throw DiaryAttachmentServiceError.invalidAttachmentIdentity(instanceID)
                }
                continue
            }
            guard retainedIDs.insert(id).inserted else {
                throw DiaryAttachmentServiceError.duplicateAttachmentIdentity(id)
            }
            guard let attachment = existingByID[id],
                  let instanceID = draft.instanceID,
                  attachment.instanceID == instanceID else {
                throw DiaryAttachmentServiceError.invalidAttachmentIdentity(id)
            }
        }

        let resolved = prepared.enumerated().map { index, value in
            let (draft, metadata) = value
            if let id = draft.id, let attachment = existingByID[id] {
                let order = Double(index) * 100
                let originalFileName = normalizedFileName(draft.originalFileName)
                let changed = attachment.order != order ||
                    attachment.originalFileName != originalFileName ||
                    attachment.mimeType != metadata.mediaType.rawValue ||
                    attachment.byteCount != metadata.byteCount ||
                    attachment.sha256 != metadata.sha256 ||
                    attachment.data != draft.data
                attachment.order = order
                attachment.originalFileName = originalFileName
                attachment.mimeType = metadata.mediaType.rawValue
                attachment.byteCount = metadata.byteCount
                attachment.sha256 = metadata.sha256
                attachment.data = draft.data
                if changed {
                    attachment.updatedAt = now
                }
                return attachment
            }
            let attachment = DiaryAttachment(
                reviewId: review.id,
                order: Double(index) * 100,
                originalFileName: normalizedFileName(draft.originalFileName),
                mimeType: metadata.mediaType.rawValue,
                byteCount: metadata.byteCount,
                sha256: metadata.sha256,
                data: draft.data,
                createdAt: now,
                updatedAt: now
            )
            context.insert(attachment)
            return attachment
        }
        for attachment in existing where !retainedIDs.contains(attachment.id) {
            context.delete(attachment)
        }
        review.updatedAt = now
        return resolved
    }

    @MainActor
    @discardableResult
    public static func saveReview(
        review existingReview: DailyReview?,
        dayKey: String,
        title: String = "",
        content: String,
        attachments drafts: [DiaryAttachmentDraft],
        in context: ModelContext,
        forceCreate: Bool = false,
        now: Date = Date()
    ) throws -> DailyReview? {
        guard drafts.count <= maximumAttachmentCount else {
            throw DiaryAttachmentServiceError.tooManyAttachments(
                actual: drafts.count,
                maximum: maximumAttachmentCount
            )
        }
        _ = try drafts.map { try inspect($0.data) }

        // Save pending edits as a rollback point before this review transaction starts.
        try context.save()
        do {
            guard let review = DailyReviewService.save(
                review: existingReview,
                dayKey: dayKey,
                title: title,
                content: content,
                imageFileNames: [],
                in: context,
                forceCreate: forceCreate || !drafts.isEmpty,
                now: now
            ) else {
                return nil
            }
            _ = try replaceAttachments(
                for: review,
                with: drafts,
                in: context,
                now: now
            )
            try context.save()
            return review
        } catch {
            context.rollback()
            if let serviceError = error as? DiaryAttachmentServiceError {
                throw serviceError
            }
            throw DiaryAttachmentServiceError.saveFailed(error.localizedDescription)
        }
    }
}

private extension DiaryAttachmentService {
    static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    static let heicBrands: Set<String> = ["heic", "heix", "hevc", "hevx", "mif1", "msf1"]

    static func detectedMediaType(in data: Data) -> DiaryAttachmentMediaType? {
        let prefix = Array(data.prefix(64))
        if prefix.count >= 3, prefix[0] == 0xFF, prefix[1] == 0xD8, prefix[2] == 0xFF {
            return .jpeg
        }
        if prefix.count >= pngSignature.count,
           Array(prefix.prefix(pngSignature.count)) == pngSignature {
            return .png
        }
        guard prefix.count >= 12,
              String(bytes: prefix[4..<8], encoding: .ascii) == "ftyp" else {
            return nil
        }

        let brandBytes = prefix.dropFirst(8)
        for offset in stride(from: 0, through: max(brandBytes.count - 4, 0), by: 4) {
            let start = brandBytes.index(brandBytes.startIndex, offsetBy: offset)
            guard let end = brandBytes.index(start, offsetBy: 4, limitedBy: brandBytes.endIndex),
                  let brand = String(bytes: brandBytes[start..<end], encoding: .ascii) else {
                continue
            }
            if heicBrands.contains(brand) {
                return .heic
            }
        }
        return nil
    }

    static func isDecodableImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else {
            return false
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) != nil
    }

    static func normalizedFileName(_ fileName: String?) -> String? {
        guard let value = fileName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return String(value.prefix(255))
    }
}

public struct LegacyDiaryAttachmentMigrationReport: Equatable, Sendable {
    public var importedCount: Int
    public var missingFileNames: [String]
    public var rejectedFileNames: [String]

    public init(
        importedCount: Int = 0,
        missingFileNames: [String] = [],
        rejectedFileNames: [String] = []
    ) {
        self.importedCount = importedCount
        self.missingFileNames = missingFileNames
        self.rejectedFileNames = rejectedFileNames
    }
}

public enum LegacyDiaryAttachmentMigrationService {
    @MainActor
    @discardableResult
    public static func migrateIfNeeded(
        context: ModelContext,
        appSupportFolder: String,
        now: Date = Date()
    ) throws -> LegacyDiaryAttachmentMigrationReport {
        let reviews = try context.fetch(FetchDescriptor<DailyReview>())
            .filter { $0.supersededAt == nil }
        let blocks = try context.fetch(FetchDescriptor<DiaryBlock>())
            .filter {
                $0.supersededAt == nil &&
                    $0.type == DiaryBlockType.image.rawValue &&
                    $0.imageFileName != nil
            }
        let existing = try context.fetch(FetchDescriptor<DiaryAttachment>())
            .filter { $0.supersededAt == nil }
        var report = LegacyDiaryAttachmentMigrationReport()
        var knownIDs = Set(existing.map(\.id))

        // Keep already-saved user edits as the rollback point for each review migration.
        try context.save()

        for review in reviews.sorted(by: { $0.dayKey < $1.dayKey }) {
            let reviewBlocks = blocks
                .filter { $0.reviewId == review.id }
                .sorted {
                    if $0.order != $1.order { return $0.order < $1.order }
                    return $0.instanceID.uuidString < $1.instanceID.uuidString
                }
            let candidates = legacyCandidates(
                reviewFileNames: review.imageFileNames,
                imageBlocks: reviewBlocks
            )
            guard !candidates.isEmpty else { continue }

            var didResolveAllCandidates = true
            for (index, candidate) in candidates.enumerated() {
                let fileName = candidate.fileName
                let attachmentID = stableAttachmentID(
                    reviewID: review.id,
                    fileName: fileName,
                    occurrence: candidate.occurrence
                )
                if knownIDs.contains(attachmentID) {
                    if let attachment = existing.first(where: { $0.id == attachmentID }) {
                        attachment.order = Double(index) * 100
                    }
                    continue
                }
                let url: URL
                do {
                    url = try DiaryImageFileStore.validatedImageURL(
                        for: fileName,
                        appSupportFolder: appSupportFolder
                    )
                } catch {
                    report.rejectedFileNames.append(fileName)
                    didResolveAllCandidates = false
                    continue
                }
                guard FileManager.default.fileExists(atPath: url.path) else {
                    report.missingFileNames.append(fileName)
                    didResolveAllCandidates = false
                    continue
                }

                do {
                    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                    let metadata = try DiaryAttachmentService.inspect(data)
                    context.insert(DiaryAttachment(
                        id: attachmentID,
                        reviewId: review.id,
                        order: Double(index) * 100,
                        originalFileName: fileName,
                        mimeType: metadata.mediaType.rawValue,
                        byteCount: metadata.byteCount,
                        sha256: metadata.sha256,
                        data: data,
                        createdAt: review.createdAt,
                        updatedAt: now
                    ))
                    knownIDs.insert(attachmentID)
                    report.importedCount += 1
                } catch {
                    report.rejectedFileNames.append(fileName)
                    didResolveAllCandidates = false
                }
            }

            guard didResolveAllCandidates else {
                // Persist valid candidates, but retain legacy references so missing files stay retryable.
                do {
                    try context.save()
                } catch {
                    context.rollback()
                    throw DiaryAttachmentServiceError.saveFailed(error.localizedDescription)
                }
                continue
            }

            review.imageFileNames = []
            review.updatedAt = now
            for block in reviewBlocks {
                block.supersededAt = now
                block.updatedAt = now
            }
            do {
                try context.save()
            } catch {
                context.rollback()
                throw DiaryAttachmentServiceError.saveFailed(error.localizedDescription)
            }
        }
        report.missingFileNames.sort()
        report.rejectedFileNames.sort()
        return report
    }

    private struct LegacyCandidate {
        var fileName: String
        var occurrence: Int
    }

    private static func legacyCandidates(
        reviewFileNames: [String],
        imageBlocks: [DiaryBlock]
    ) -> [LegacyCandidate] {
        var candidates: [LegacyCandidate] = []
        var reviewCounts: [String: Int] = [:]
        for fileName in reviewFileNames {
            let occurrence = reviewCounts[fileName, default: 0]
            candidates.append(LegacyCandidate(fileName: fileName, occurrence: occurrence))
            reviewCounts[fileName] = occurrence + 1
        }

        var blockCounts: [String: Int] = [:]
        for block in imageBlocks {
            guard let fileName = block.imageFileName else { continue }
            let occurrence = blockCounts[fileName, default: 0]
            blockCounts[fileName] = occurrence + 1
            guard occurrence >= reviewCounts[fileName, default: 0] else { continue }
            candidates.append(LegacyCandidate(fileName: fileName, occurrence: occurrence))
        }
        return candidates
    }

    private static func stableAttachmentID(
        reviewID: UUID,
        fileName: String,
        occurrence: Int
    ) -> UUID {
        let digest = SHA256.hash(
            data: Data("DiaryAttachment|\(reviewID.uuidString)|\(fileName)|\(occurrence)".utf8)
        )
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
