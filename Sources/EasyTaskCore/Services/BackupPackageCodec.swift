import CryptoKit
import Foundation
import SwiftData

public struct BackupPackageAttachmentManifest: Codable, Equatable, Sendable {
    public var id: UUID
    public var fileName: String
    public var byteCount: Int
    public var sha256: String

    public init(id: UUID, fileName: String, byteCount: Int, sha256: String) {
        self.id = id
        self.fileName = fileName
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public struct BackupPackageManifest: Codable, Equatable, Sendable {
    public var formatIdentifier: String
    public var formatVersion: Int
    public var exportedAt: Date
    public var recordsFileName: String
    public var recordsByteCount: Int
    public var recordsSHA256: String
    public var attachmentsDirectoryName: String
    public var totalAttachmentBytes: Int
    public var attachments: [BackupPackageAttachmentManifest]

    public init(
        formatIdentifier: String,
        formatVersion: Int,
        exportedAt: Date,
        recordsFileName: String,
        recordsByteCount: Int,
        recordsSHA256: String,
        attachmentsDirectoryName: String,
        totalAttachmentBytes: Int,
        attachments: [BackupPackageAttachmentManifest]
    ) {
        self.formatIdentifier = formatIdentifier
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.recordsFileName = recordsFileName
        self.recordsByteCount = recordsByteCount
        self.recordsSHA256 = recordsSHA256
        self.attachmentsDirectoryName = attachmentsDirectoryName
        self.totalAttachmentBytes = totalAttachmentBytes
        self.attachments = attachments
    }
}

public struct BackupPackageAttachmentRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var instanceID: UUID
    public var reviewId: UUID
    public var order: Double
    public var originalFileName: String?
    public var mimeType: String
    public var byteCount: Int
    public var sha256: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        instanceID: UUID,
        reviewId: UUID,
        order: Double,
        originalFileName: String?,
        mimeType: String,
        byteCount: Int,
        sha256: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.instanceID = instanceID
        self.reviewId = reviewId
        self.order = order
        self.originalFileName = originalFileName
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.sha256 = sha256
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct BackupPackageRecords: Codable {
    public var formatVersion: Int
    public var exportedAt: Date
    public var payload: BackupPayload
    public var attachments: [BackupPackageAttachmentRecord]

    public init(
        formatVersion: Int,
        exportedAt: Date,
        payload: BackupPayload,
        attachments: [BackupPackageAttachmentRecord]
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.payload = payload
        self.attachments = attachments
    }
}

public struct BackupPackageContents {
    public var manifest: BackupPackageManifest
    public var records: BackupPackageRecords
    public var attachmentData: [UUID: Data]

    public init(
        manifest: BackupPackageManifest,
        records: BackupPackageRecords,
        attachmentData: [UUID: Data]
    ) {
        self.manifest = manifest
        self.records = records
        self.attachmentData = attachmentData
    }
}

public struct BackupPackageMergeReport: Equatable, Sendable {
    public var insertedRecords: Int
    public var updatedRecords: Int
    public var preservedLocalRecords: Int
    public var insertedAttachments: Int
    public var updatedAttachments: Int

    public init(
        insertedRecords: Int = 0,
        updatedRecords: Int = 0,
        preservedLocalRecords: Int = 0,
        insertedAttachments: Int = 0,
        updatedAttachments: Int = 0
    ) {
        self.insertedRecords = insertedRecords
        self.updatedRecords = updatedRecords
        self.preservedLocalRecords = preservedLocalRecords
        self.insertedAttachments = insertedAttachments
        self.updatedAttachments = updatedAttachments
    }
}

public enum BackupPackageError: LocalizedError, Equatable {
    case invalidFormatIdentifier(String)
    case unsupportedVersion(Int)
    case notDirectory
    case missingFile(String)
    case unexpectedFile(String)
    case invalidFileName(String)
    case duplicateAttachmentID(UUID)
    case duplicateAttachmentFileName(String)
    case duplicateInstanceID(recordType: String, instanceID: UUID)
    case missingAttachmentData(UUID)
    case danglingReviewReference(UUID)
    case invalidAttachmentMetadata(UUID)
    case invalidRecordMetadata(recordType: String, id: UUID)
    case recordsSizeMismatch
    case recordsChecksumMismatch
    case attachmentSizeMismatch(UUID)
    case attachmentChecksumMismatch(UUID)
    case packageTooLarge(actualBytes: Int, maximumBytes: Int)
    case metadataTooLarge(fileName: String, actualBytes: Int, maximumBytes: Int)
    case unresolvedLegacyAttachments(Int)
    case identityCorruption(recordType: String, instanceID: UUID)
    case fileSystem(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormatIdentifier(let identifier):
            return "EasyTask 백업 식별자가 올바르지 않습니다. identifier=\(identifier)"
        case .unsupportedVersion(let version):
            return "지원하지 않는 EasyTask 백업 버전입니다. version=\(version)"
        case .notDirectory:
            return "EasyTask 백업 패키지가 디렉터리 형식이 아닙니다."
        case .missingFile(let fileName):
            return "백업 패키지에 필요한 파일이 없습니다. file=\(fileName)"
        case .unexpectedFile(let fileName):
            return "백업 첨부 폴더에 예상하지 못한 파일이 있습니다. file=\(fileName)"
        case .invalidFileName(let fileName):
            return "백업 패키지 파일명이 안전하지 않습니다. file=\(fileName)"
        case .duplicateAttachmentID(let id):
            return "백업에 중복 첨부 ID가 있습니다. id=\(id)"
        case .duplicateAttachmentFileName(let fileName):
            return "백업에 중복 첨부 파일명이 있습니다. file=\(fileName)"
        case .duplicateInstanceID(let recordType, let instanceID):
            return "백업에 중복 인스턴스 ID가 있습니다. type=\(recordType), instanceID=\(instanceID)"
        case .missingAttachmentData(let id):
            return "백업에 첨부 원본이 없습니다. id=\(id)"
        case .danglingReviewReference(let reviewID):
            return "첨부가 존재하지 않는 회고를 참조합니다. reviewID=\(reviewID)"
        case .invalidAttachmentMetadata(let id):
            return "첨부 메타데이터가 원본 이미지와 일치하지 않습니다. id=\(id)"
        case .invalidRecordMetadata(let recordType, let id):
            return "백업 레코드 메타데이터가 올바르지 않습니다. type=\(recordType), id=\(id)"
        case .recordsSizeMismatch:
            return "records.json 크기가 manifest와 일치하지 않습니다."
        case .recordsChecksumMismatch:
            return "records.json 해시가 manifest와 일치하지 않습니다."
        case .attachmentSizeMismatch(let id):
            return "첨부 파일 크기가 manifest와 일치하지 않습니다. id=\(id)"
        case .attachmentChecksumMismatch(let id):
            return "첨부 파일 해시가 manifest와 일치하지 않습니다. id=\(id)"
        case .packageTooLarge(let actualBytes, let maximumBytes):
            return "백업 첨부 전체 크기가 제한을 초과했습니다. size=\(actualBytes), max=\(maximumBytes)"
        case .metadataTooLarge(let fileName, let actualBytes, let maximumBytes):
            return "백업 메타데이터 파일이 너무 큽니다. file=\(fileName), size=\(actualBytes), max=\(maximumBytes)"
        case .unresolvedLegacyAttachments(let count):
            return "이관되지 않은 기존 이미지 \(count)개가 있어 백업을 만들 수 없습니다. 앱을 다시 연 뒤 이미지를 확인하세요."
        case .identityCorruption(let recordType, let instanceID):
            return "같은 인스턴스가 서로 다른 내용을 가집니다. type=\(recordType), instanceID=\(instanceID)"
        case .fileSystem(let description):
            return "백업 파일 처리에 실패했습니다. \(description)"
        }
    }
}

public enum BackupPackageCodec {
    public static let formatIdentifier = "com.soraul2.easytask.backup"
    public static let currentVersion = 2
    public static let manifestFileName = "manifest.json"
    public static let recordsFileName = "records.json"
    public static let attachmentsDirectoryName = "attachments"
    public static let maximumMetadataSizeBytes = 10 * 1_024 * 1_024
    public static let maximumTotalAttachmentBytes = 200 * 1_024 * 1_024

    @MainActor
    public static func makeContents(
        context: ModelContext,
        exportedAt: Date = Date()
    ) throws -> BackupPackageContents {
        _ = try DataIntegrityService.reconcile(context: context)
        var payload = try BackupCodec.makePayload(context: context)
        payload.exportedAt = exportedAt

        let unresolvedLegacyCount = (payload.dailyReviews ?? []).reduce(0) {
            $0 + ($1.imageFileNames?.count ?? 0)
        } + (payload.diaryBlocks ?? []).filter {
            $0.type == DiaryBlockType.image.rawValue && $0.imageFileName != nil
        }.count
        guard unresolvedLegacyCount == 0 else {
            throw BackupPackageError.unresolvedLegacyAttachments(unresolvedLegacyCount)
        }

        // Package V2 stores images as first-class attachment records, not legacy paths.
        if var reviews = payload.dailyReviews {
            for index in reviews.indices {
                reviews[index].imageFileNames = []
            }
            payload.dailyReviews = reviews
        }
        payload.diaryBlocks = (payload.diaryBlocks ?? []).filter {
            $0.type != DiaryBlockType.image.rawValue
        }
        try BackupCodec.validate(payload)

        let attachments = try context.fetch(FetchDescriptor<DiaryAttachment>())
            .filter { $0.supersededAt == nil }
            .sorted {
                if $0.reviewId != $1.reviewId {
                    return $0.reviewId.uuidString < $1.reviewId.uuidString
                }
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.instanceID.uuidString < $1.instanceID.uuidString
            }
        var dataByID: [UUID: Data] = [:]
        var records: [BackupPackageAttachmentRecord] = []
        var manifestEntries: [BackupPackageAttachmentManifest] = []

        for attachment in attachments {
            let metadata = try DiaryAttachmentService.inspect(attachment.data)
            let record = BackupPackageAttachmentRecord(
                id: attachment.id,
                instanceID: attachment.instanceID,
                reviewId: attachment.reviewId,
                order: attachment.order,
                originalFileName: attachment.originalFileName,
                mimeType: metadata.mediaType.rawValue,
                byteCount: metadata.byteCount,
                sha256: metadata.sha256,
                createdAt: attachment.createdAt,
                updatedAt: attachment.updatedAt
            )
            records.append(record)
            dataByID[record.id] = attachment.data
            manifestEntries.append(BackupPackageAttachmentManifest(
                id: record.id,
                fileName: assetFileName(for: record),
                byteCount: record.byteCount,
                sha256: record.sha256
            ))
        }

        let packageRecords = BackupPackageRecords(
            formatVersion: currentVersion,
            exportedAt: exportedAt,
            payload: payload,
            attachments: records
        )
        let recordsData = try encoded(packageRecords)
        let manifest = BackupPackageManifest(
            formatIdentifier: formatIdentifier,
            formatVersion: currentVersion,
            exportedAt: exportedAt,
            recordsFileName: recordsFileName,
            recordsByteCount: recordsData.count,
            recordsSHA256: sha256(recordsData),
            attachmentsDirectoryName: attachmentsDirectoryName,
            totalAttachmentBytes: records.reduce(0) { $0 + $1.byteCount },
            attachments: manifestEntries
        )
        let contents = BackupPackageContents(
            manifest: manifest,
            records: packageRecords,
            attachmentData: dataByID
        )
        try validate(contents)
        return contents
    }

    public static func write(_ contents: BackupPackageContents, to destinationURL: URL) throws {
        try validate(contents)
        let fileManager = FileManager.default
        let parent = destinationURL.deletingLastPathComponent()
        let stagingURL = parent.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).staging",
            isDirectory: true
        )
        defer {
            try? fileManager.removeItem(at: stagingURL)
        }

        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            try fileManager.createDirectory(
                at: stagingURL.appendingPathComponent(attachmentsDirectoryName, isDirectory: true),
                withIntermediateDirectories: true
            )
            try encoded(contents.manifest).write(
                to: stagingURL.appendingPathComponent(manifestFileName),
                options: .atomic
            )
            try encoded(contents.records).write(
                to: stagingURL.appendingPathComponent(recordsFileName),
                options: .atomic
            )
            for entry in contents.manifest.attachments {
                guard let data = contents.attachmentData[entry.id] else {
                    throw BackupPackageError.missingAttachmentData(entry.id)
                }
                try data.write(
                    to: stagingURL
                        .appendingPathComponent(attachmentsDirectoryName, isDirectory: true)
                        .appendingPathComponent(entry.fileName),
                    options: .atomic
                )
            }

            _ = try read(from: stagingURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagingURL)
            } else {
                try fileManager.moveItem(at: stagingURL, to: destinationURL)
            }
        } catch let error as BackupPackageError {
            throw error
        } catch {
            throw BackupPackageError.fileSystem(error.localizedDescription)
        }
    }

    public static func read(from packageURL: URL) throws -> BackupPackageContents {
        let values = try packageURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw BackupPackageError.notDirectory
        }

        let rootURLs = try FileManager.default.contentsOfDirectory(
            at: packageURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        let expectedRootNames = Set([
            manifestFileName,
            recordsFileName,
            attachmentsDirectoryName
        ])
        for url in rootURLs where !expectedRootNames.contains(url.lastPathComponent) {
            throw BackupPackageError.unexpectedFile(url.lastPathComponent)
        }

        let manifestURL = packageURL.appendingPathComponent(manifestFileName)
        let manifestData = try metadataData(from: manifestURL)
        let manifest: BackupPackageManifest = try decoded(manifestData)
        guard manifest.formatIdentifier == formatIdentifier else {
            throw BackupPackageError.invalidFormatIdentifier(manifest.formatIdentifier)
        }
        guard manifest.formatVersion == currentVersion else {
            throw BackupPackageError.unsupportedVersion(manifest.formatVersion)
        }
        guard manifest.recordsFileName == recordsFileName,
              manifest.attachmentsDirectoryName == attachmentsDirectoryName else {
            throw BackupPackageError.invalidFileName(
                "\(manifest.recordsFileName),\(manifest.attachmentsDirectoryName)"
            )
        }
        guard manifest.recordsByteCount > 0,
              manifest.recordsByteCount <= maximumMetadataSizeBytes,
              isSHA256(manifest.recordsSHA256),
              manifest.totalAttachmentBytes >= 0,
              manifest.totalAttachmentBytes <= maximumTotalAttachmentBytes else {
            throw BackupPackageError.invalidRecordMetadata(
                recordType: "Manifest",
                id: zeroUUID
            )
        }
        var earlyAttachmentIDs: Set<UUID> = []
        var earlyFileNames: Set<String> = []
        for entry in manifest.attachments {
            try validateAssetFileName(entry.fileName)
            guard earlyAttachmentIDs.insert(entry.id).inserted else {
                throw BackupPackageError.duplicateAttachmentID(entry.id)
            }
            guard earlyFileNames.insert(entry.fileName).inserted else {
                throw BackupPackageError.duplicateAttachmentFileName(entry.fileName)
            }
            guard entry.byteCount > 0,
                  entry.byteCount <= DiaryAttachmentService.maximumImageSizeBytes,
                  isSHA256(entry.sha256) else {
                throw BackupPackageError.invalidAttachmentMetadata(entry.id)
            }
        }

        let recordsURL = packageURL.appendingPathComponent(recordsFileName)
        let recordsData = try metadataData(from: recordsURL)
        guard recordsData.count == manifest.recordsByteCount else {
            throw BackupPackageError.recordsSizeMismatch
        }
        guard sha256(recordsData) == manifest.recordsSHA256 else {
            throw BackupPackageError.recordsChecksumMismatch
        }
        let records: BackupPackageRecords = try decoded(recordsData)
        let attachmentsURL = packageURL.appendingPathComponent(
            manifest.attachmentsDirectoryName,
            isDirectory: true
        )
        let attachmentsValues = try? attachmentsURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard attachmentsValues?.isDirectory == true,
              attachmentsValues?.isSymbolicLink != true else {
            throw BackupPackageError.missingFile(manifest.attachmentsDirectoryName)
        }

        let expectedNames = Set(manifest.attachments.map(\.fileName))
        let actualURLs = try FileManager.default.contentsOfDirectory(
            at: attachmentsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        for url in actualURLs where !expectedNames.contains(url.lastPathComponent) {
            throw BackupPackageError.unexpectedFile(url.lastPathComponent)
        }

        var dataByID: [UUID: Data] = [:]
        var runningTotal = 0
        for entry in manifest.attachments {
            let url = attachmentsURL.appendingPathComponent(entry.fileName)
            let fileValues = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard fileValues.isRegularFile == true, fileValues.isSymbolicLink != true else {
                throw BackupPackageError.missingFile(entry.fileName)
            }
            let fileSize = fileValues.fileSize ?? 0
            guard fileSize == entry.byteCount else {
                throw BackupPackageError.attachmentSizeMismatch(entry.id)
            }
            let (nextTotal, didOverflow) = runningTotal.addingReportingOverflow(fileSize)
            guard !didOverflow else {
                throw BackupPackageError.packageTooLarge(
                    actualBytes: Int.max,
                    maximumBytes: maximumTotalAttachmentBytes
                )
            }
            runningTotal = nextTotal
            guard runningTotal <= maximumTotalAttachmentBytes else {
                throw BackupPackageError.packageTooLarge(
                    actualBytes: runningTotal,
                    maximumBytes: maximumTotalAttachmentBytes
                )
            }
            dataByID[entry.id] = try Data(contentsOf: url, options: [.mappedIfSafe])
        }

        let contents = BackupPackageContents(
            manifest: manifest,
            records: records,
            attachmentData: dataByID
        )
        try validate(contents)
        return contents
    }

    public static func validate(_ contents: BackupPackageContents) throws {
        guard contents.manifest.formatIdentifier == formatIdentifier else {
            throw BackupPackageError.invalidFormatIdentifier(contents.manifest.formatIdentifier)
        }
        guard contents.manifest.formatVersion == currentVersion else {
            throw BackupPackageError.unsupportedVersion(contents.manifest.formatVersion)
        }
        guard contents.records.formatVersion == currentVersion else {
            throw BackupPackageError.unsupportedVersion(contents.records.formatVersion)
        }
        guard contents.manifest.recordsFileName == recordsFileName,
              contents.manifest.attachmentsDirectoryName == attachmentsDirectoryName else {
            throw BackupPackageError.invalidFileName(
                "\(contents.manifest.recordsFileName),\(contents.manifest.attachmentsDirectoryName)"
            )
        }
        guard contents.manifest.recordsByteCount > 0,
              contents.manifest.recordsByteCount <= maximumMetadataSizeBytes,
              isSHA256(contents.manifest.recordsSHA256),
              contents.manifest.totalAttachmentBytes >= 0,
              contents.manifest.exportedAt.timeIntervalSinceReferenceDate.isFinite,
              contents.records.exportedAt.timeIntervalSinceReferenceDate.isFinite,
              contents.manifest.exportedAt == contents.records.exportedAt else {
            throw BackupPackageError.invalidRecordMetadata(
                recordType: "Manifest",
                id: zeroUUID
            )
        }
        try BackupCodec.validate(contents.records.payload)
        let legacyReferenceCount = (contents.records.payload.dailyReviews ?? []).reduce(0) {
            $0 + ($1.imageFileNames?.count ?? 0)
        } + (contents.records.payload.diaryBlocks ?? []).filter {
            $0.type == DiaryBlockType.image.rawValue || $0.imageFileName != nil
        }.count
        guard legacyReferenceCount == 0 else {
            throw BackupPackageError.unresolvedLegacyAttachments(legacyReferenceCount)
        }
        try validateRecordInstanceIDs(contents.records.payload)
        let canonicalRecordsData = try encoded(contents.records)
        guard canonicalRecordsData.count == contents.manifest.recordsByteCount else {
            throw BackupPackageError.recordsSizeMismatch
        }
        guard sha256(canonicalRecordsData) == contents.manifest.recordsSHA256 else {
            throw BackupPackageError.recordsChecksumMismatch
        }

        let reviewIDs = Set((contents.records.payload.dailyReviews ?? []).map(\.id))
        var recordIDs: Set<UUID> = []
        var manifestIDs: Set<UUID> = []
        var fileNames: Set<String> = []
        var totalBytes = 0
        for entry in contents.manifest.attachments {
            guard manifestIDs.insert(entry.id).inserted else {
                throw BackupPackageError.duplicateAttachmentID(entry.id)
            }
            guard fileNames.insert(entry.fileName).inserted else {
                throw BackupPackageError.duplicateAttachmentFileName(entry.fileName)
            }
            try validateAssetFileName(entry.fileName)
        }
        let manifestByID = Dictionary(
            uniqueKeysWithValues: contents.manifest.attachments.map { ($0.id, $0) }
        )

        var attachmentCountsByReview: [UUID: Int] = [:]
        for record in contents.records.attachments {
            guard recordIDs.insert(record.id).inserted else {
                throw BackupPackageError.duplicateAttachmentID(record.id)
            }
            guard reviewIDs.contains(record.reviewId) else {
                throw BackupPackageError.danglingReviewReference(record.reviewId)
            }
            guard record.order.isFinite,
                  record.byteCount > 0,
                  isSHA256(record.sha256),
                  record.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  record.updatedAt.timeIntervalSinceReferenceDate.isFinite,
                  DiaryAttachmentMediaType(rawValue: record.mimeType) != nil else {
                throw BackupPackageError.invalidAttachmentMetadata(record.id)
            }
            attachmentCountsByReview[record.reviewId, default: 0] += 1
            guard attachmentCountsByReview[record.reviewId, default: 0] <=
                    DiaryAttachmentService.maximumAttachmentCount else {
                throw BackupPackageError.invalidAttachmentMetadata(record.id)
            }
            guard let data = contents.attachmentData[record.id] else {
                throw BackupPackageError.missingAttachmentData(record.id)
            }
            guard data.count == record.byteCount else {
                throw BackupPackageError.attachmentSizeMismatch(record.id)
            }
            let metadata = try DiaryAttachmentService.inspect(data)
            guard metadata.mediaType.rawValue == record.mimeType else {
                throw BackupPackageError.invalidAttachmentMetadata(record.id)
            }
            guard metadata.sha256 == record.sha256 else {
                throw BackupPackageError.attachmentChecksumMismatch(record.id)
            }
            guard let entry = manifestByID[record.id],
                  entry.fileName == assetFileName(for: record),
                  entry.byteCount == record.byteCount else {
                throw BackupPackageError.invalidAttachmentMetadata(record.id)
            }
            guard entry.sha256 == record.sha256 else {
                throw BackupPackageError.attachmentChecksumMismatch(record.id)
            }
            let (nextTotal, didOverflow) = totalBytes.addingReportingOverflow(data.count)
            guard !didOverflow else {
                throw BackupPackageError.packageTooLarge(
                    actualBytes: Int.max,
                    maximumBytes: maximumTotalAttachmentBytes
                )
            }
            totalBytes = nextTotal
        }

        guard recordIDs == manifestIDs,
              recordIDs == Set(contents.attachmentData.keys) else {
            let missingID = recordIDs.symmetricDifference(manifestIDs)
                .union(recordIDs.symmetricDifference(Set(contents.attachmentData.keys)))
                .sorted { $0.uuidString < $1.uuidString }
                .first ?? UUID()
            throw BackupPackageError.missingAttachmentData(missingID)
        }
        guard totalBytes == contents.manifest.totalAttachmentBytes else {
            throw BackupPackageError.packageTooLarge(
                actualBytes: totalBytes,
                maximumBytes: contents.manifest.totalAttachmentBytes
            )
        }
        guard totalBytes <= maximumTotalAttachmentBytes else {
            throw BackupPackageError.packageTooLarge(
                actualBytes: totalBytes,
                maximumBytes: maximumTotalAttachmentBytes
            )
        }
    }
}

private extension BackupPackageCodec {
    static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )

    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    static func validateRecordInstanceIDs(_ payload: BackupPayload) throws {
        try validateInstanceIDs(
            payload.tasks.map { ($0.id, $0.instanceID) },
            recordType: "Task"
        )
        try validateInstanceIDs(
            payload.calendarEvents.map { ($0.id, $0.instanceID) },
            recordType: "CalendarEvent"
        )
        try validateInstanceIDs(
            payload.taskTemplates.map { ($0.id, $0.instanceID) },
            recordType: "TaskTemplate"
        )
        try validateInstanceIDs(
            payload.taskTemplateItems.map { ($0.id, $0.instanceID) },
            recordType: "TaskTemplateItem"
        )
        try validateInstanceIDs(
            (payload.templatePlacements ?? []).map { ($0.id, $0.instanceID) },
            recordType: "TemplatePlacement"
        )
        try validateInstanceIDs(
            (payload.dailyReviews ?? []).map { ($0.id, $0.instanceID) },
            recordType: "DailyReview"
        )
        try validateInstanceIDs(
            (payload.diaryBlocks ?? []).map { ($0.id, $0.instanceID) },
            recordType: "DiaryBlock"
        )

        for item in payload.taskTemplateItems {
            guard let createdAt = item.createdAt,
                  let updatedAt = item.updatedAt,
                  createdAt.timeIntervalSinceReferenceDate.isFinite,
                  updatedAt.timeIntervalSinceReferenceDate.isFinite else {
                throw BackupPackageError.invalidRecordMetadata(
                    recordType: "TaskTemplateItem",
                    id: item.id
                )
            }
        }
    }

    static func validateInstanceIDs(
        _ records: [(id: UUID, instanceID: UUID?)],
        recordType: String
    ) throws {
        var seen: Set<UUID> = []
        for record in records {
            guard let instanceID = record.instanceID else {
                throw BackupPackageError.invalidRecordMetadata(
                    recordType: recordType,
                    id: record.id
                )
            }
            guard seen.insert(instanceID).inserted else {
                throw BackupPackageError.duplicateInstanceID(
                    recordType: recordType,
                    instanceID: instanceID
                )
            }
        }
    }

    static func assetFileName(for record: BackupPackageAttachmentRecord) -> String {
        let fileExtension = DiaryAttachmentMediaType(rawValue: record.mimeType)?
            .preferredFileExtension ?? "bin"
        return "\(record.id.uuidString.lowercased()).\(fileExtension)"
    }

    static func validateAssetFileName(_ fileName: String) throws {
        guard fileName == URL(fileURLWithPath: fileName).lastPathComponent,
              !fileName.hasPrefix("."),
              !fileName.contains("/"),
              !fileName.contains("\\"),
              fileName.utf8.count <= 255 else {
            throw BackupPackageError.invalidFileName(fileName)
        }
    }

    static func encoded<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func metadataData(from url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BackupPackageError.missingFile(url.lastPathComponent)
        }
        let values = try url.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw BackupPackageError.missingFile(url.lastPathComponent)
        }
        let size = values.fileSize ?? 0
        guard size <= maximumMetadataSizeBytes else {
            throw BackupPackageError.metadataTooLarge(
                fileName: url.lastPathComponent,
                actualBytes: size,
                maximumBytes: maximumMetadataSizeBytes
            )
        }
        return try Data(contentsOf: url)
    }

    static func decoded<Value: Decodable>(_ data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Value.self, from: data)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
