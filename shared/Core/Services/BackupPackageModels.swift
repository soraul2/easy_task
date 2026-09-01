import Foundation

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
    case tooManyAttachments(actual: Int, maximum: Int)
    case identityCorruption(recordType: String, instanceID: UUID)
    case fileSystem(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormatIdentifier(let identifier):
            return "PlanBase 백업 식별자가 올바르지 않습니다. identifier=\(identifier)"
        case .unsupportedVersion(let version):
            return "지원하지 않는 PlanBase 백업 버전입니다. version=\(version)"
        case .notDirectory:
            return "PlanBase 백업 패키지가 디렉터리 형식이 아닙니다."
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
        case .tooManyAttachments(let actual, let maximum):
            return "회고 한 건의 이미지가 제한을 초과했습니다. count=\(actual), max=\(maximum)"
        case .identityCorruption(let recordType, let instanceID):
            return "같은 인스턴스가 서로 다른 내용을 가집니다. type=\(recordType), instanceID=\(instanceID)"
        case .fileSystem(let description):
            return "백업 파일 처리에 실패했습니다. \(description)"
        }
    }
}
