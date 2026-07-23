#if os(iOS)
import Combine
import Foundation
import PlanBaseCore
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum MobileBackupServiceError: LocalizedError, Equatable {
    case securityScopedAccessDenied
    case unsupportedSelection(String)
    case fileOperation(String)

    var errorDescription: String? {
        switch self {
        case .securityScopedAccessDenied:
            "선택한 파일에 안전하게 접근할 수 없습니다."
        case .unsupportedSelection(let fileName):
            "지원하지 않는 백업 파일입니다. file=\(fileName)"
        case .fileOperation(let description):
            "백업 파일 처리에 실패했습니다. \(description)"
        }
    }
}

struct MobileBackupExportArtifact: Equatable, Sendable {
    let packageURL: URL
    let cleanupDirectoryURL: URL
}

final class MobileBackupPreparedImport: @unchecked Sendable {
    enum Payload {
        case package(BackupPackageContents)
        case legacyJSON(BackupPayload)
    }

    let payload: Payload
    let cleanupDirectoryURL: URL

    init(payload: Payload, cleanupDirectoryURL: URL) {
        self.payload = payload
        self.cleanupDirectoryURL = cleanupDirectoryURL
    }
}

@MainActor
protocol MobileBackupFileAdapter {
    func prepareImport(from sourceURL: URL) async throws -> MobileBackupPreparedImport
    func prepareExport(
        contents: BackupPackageContents,
        suggestedFileName: String
    ) async throws -> MobileBackupExportArtifact
    func cleanup(directoryURL: URL) async
}

@MainActor
final class SystemMobileBackupFileAdapter: MobileBackupFileAdapter {
    func prepareImport(from sourceURL: URL) async throws -> MobileBackupPreparedImport {
        guard sourceURL.startAccessingSecurityScopedResource() else {
            throw MobileBackupServiceError.securityScopedAccessDenied
        }
        defer {
            sourceURL.stopAccessingSecurityScopedResource()
        }

        let pathExtension = sourceURL.pathExtension.lowercased()
        guard pathExtension == "easytaskbackup" || pathExtension == "json" else {
            throw MobileBackupServiceError.unsupportedSelection(
                sourceURL.lastPathComponent
            )
        }

        return try await Swift.Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let cleanupDirectoryURL = fileManager.temporaryDirectory
                .appendingPathComponent(
                    "PlanBaseMobileImport-\(UUID().uuidString)",
                    isDirectory: true
                )
            let destinationURL = cleanupDirectoryURL.appendingPathComponent(
                sourceURL.lastPathComponent,
                isDirectory: pathExtension != "json"
            )

            do {
                try fileManager.createDirectory(
                    at: cleanupDirectoryURL,
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: sourceURL, to: destinationURL)

                if pathExtension == "json" {
                    let data = try Data(
                        contentsOf: destinationURL,
                        options: [.mappedIfSafe]
                    )
                    let payload = try BackupCodec.decode(data)
                    return MobileBackupPreparedImport(
                        payload: .legacyJSON(payload),
                        cleanupDirectoryURL: cleanupDirectoryURL
                    )
                }

                let contents = try BackupPackageCodec.read(from: destinationURL)
                return MobileBackupPreparedImport(
                    payload: .package(contents),
                    cleanupDirectoryURL: cleanupDirectoryURL
                )
            } catch {
                try? fileManager.removeItem(at: cleanupDirectoryURL)
                if error is BackupPackageError || error is BackupServiceError {
                    throw error
                }
                throw MobileBackupServiceError.fileOperation(
                    error.localizedDescription
                )
            }
        }.value
    }

    func prepareExport(
        contents: BackupPackageContents,
        suggestedFileName: String
    ) async throws -> MobileBackupExportArtifact {
        let transfer = MobileBackupContentsTransfer(contents)
        return try await Swift.Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let cleanupDirectoryURL = fileManager.temporaryDirectory
                .appendingPathComponent(
                    "PlanBaseMobileExport-\(UUID().uuidString)",
                    isDirectory: true
                )
            let packageURL = cleanupDirectoryURL.appendingPathComponent(
                suggestedFileName,
                isDirectory: true
            )

            do {
                try fileManager.createDirectory(
                    at: cleanupDirectoryURL,
                    withIntermediateDirectories: true
                )
                try BackupPackageCodec.write(
                    transfer.contents,
                    to: packageURL
                )
                return MobileBackupExportArtifact(
                    packageURL: packageURL,
                    cleanupDirectoryURL: cleanupDirectoryURL
                )
            } catch {
                try? fileManager.removeItem(at: cleanupDirectoryURL)
                if error is BackupPackageError {
                    throw error
                }
                throw MobileBackupServiceError.fileOperation(
                    error.localizedDescription
                )
            }
        }.value
    }

    func cleanup(directoryURL: URL) async {
        await Swift.Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: directoryURL)
        }.value
    }
}

private final class MobileBackupContentsTransfer: @unchecked Sendable {
    let contents: BackupPackageContents

    init(_ contents: BackupPackageContents) {
        self.contents = contents
    }
}

enum MobileBackupPickerRequest: Identifiable, Equatable {
    case importBackup
    case exportBackup(URL)

    var id: String {
        switch self {
        case .importBackup:
            "import"
        case .exportBackup(let url):
            "export-\(url.path)"
        }
    }
}

enum MobileBackupPickerResult: Equatable {
    case selected(URL)
    case cancelled
    case failed(String)
}

struct MobileBackupNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case failure
    }

    let id = UUID()
    let kind: Kind
    let message: String

    static func == (lhs: MobileBackupNotice, rhs: MobileBackupNotice) -> Bool {
        lhs.kind == rhs.kind && lhs.message == rhs.message
    }
}

@MainActor
final class MobileBackupCoordinator: ObservableObject {
    @Published private(set) var isBusy = false
    @Published var pickerRequest: MobileBackupPickerRequest?
    @Published var notice: MobileBackupNotice?

    private let fileAdapter: any MobileBackupFileAdapter
    private var pendingExportArtifact: MobileBackupExportArtifact?

    init(fileAdapter: (any MobileBackupFileAdapter)? = nil) {
        self.fileAdapter = fileAdapter ?? SystemMobileBackupFileAdapter()
    }

    func requestImport() {
        guard !isBusy else { return }
        isBusy = true
        notice = nil
        pickerRequest = .importBackup
    }

    func requestExport(context: ModelContext) {
        guard !isBusy else { return }
        isBusy = true
        notice = nil

        Swift.Task { @MainActor in
            do {
                let contents = try BackupPackageCodec.makeContents(context: context)
                let artifact = try await fileAdapter.prepareExport(
                    contents: contents,
                    suggestedFileName: "planbase-backup-\(DayKey.today).easytaskbackup"
                )
                pendingExportArtifact = artifact
                pickerRequest = .exportBackup(artifact.packageURL)
            } catch {
                finishWithFailure(error)
            }
        }
    }

    func handlePickerResult(
        _ result: MobileBackupPickerResult,
        for request: MobileBackupPickerRequest,
        context: ModelContext
    ) {
        pickerRequest = nil

        switch request {
        case .importBackup:
            switch result {
            case .selected(let url):
                Swift.Task { @MainActor in
                    await importSelectedURL(url, context: context)
                }
            case .cancelled:
                isBusy = false
            case .failed(let message):
                finishWithFailure(MobileBackupServiceError.fileOperation(message))
            }

        case .exportBackup:
            let artifact = pendingExportArtifact
            pendingExportArtifact = nil
            Swift.Task { @MainActor in
                if let artifact {
                    await fileAdapter.cleanup(
                        directoryURL: artifact.cleanupDirectoryURL
                    )
                }

                switch result {
                case .selected:
                    notice = MobileBackupNotice(
                        kind: .success,
                        message: "이미지 원본을 포함한 백업을 내보냈습니다."
                    )
                case .cancelled:
                    break
                case .failed(let message):
                    notice = MobileBackupNotice(
                        kind: .failure,
                        message: MobileBackupServiceError
                            .fileOperation(message)
                            .localizedDescription
                    )
                }
                isBusy = false
            }
        }
    }

    func importSelectedURL(_ url: URL, context: ModelContext) async {
        var cleanupDirectoryURL: URL?

        do {
            let prepared = try await fileAdapter.prepareImport(from: url)
            cleanupDirectoryURL = prepared.cleanupDirectoryURL
            let message: String

            switch prepared.payload {
            case .package(let contents):
                let report = try BackupPackageCodec.restoreMerging(
                    contents,
                    into: context
                )
                let recordCount = report.insertedRecords + report.updatedRecords
                let attachmentCount = report.insertedAttachments
                    + report.updatedAttachments
                message = "백업을 병합했습니다. 데이터 \(recordCount)건, 이미지 \(attachmentCount)건 반영"

            case .legacyJSON(let payload):
                let report = try BackupPackageCodec.restoreLegacyJSONMerging(
                    payload,
                    into: context
                )
                let recordCount = report.merge.insertedRecords
                    + report.merge.updatedRecords
                let missingImageCount = Set(
                    report.referencedImageFileNames
                ).count
                message = "JSON V1을 병합했습니다. 데이터 \(recordCount)건 반영 · 이미지 원본 미포함 \(missingImageCount)개"
            }

            if let cleanupDirectoryURL {
                await fileAdapter.cleanup(directoryURL: cleanupDirectoryURL)
            }
            NotificationCenter.default.post(
                name: PersistenceCommandService.dataChangedNotification,
                object: context
            )
            notice = MobileBackupNotice(kind: .success, message: message)
            isBusy = false
        } catch {
            if let cleanupDirectoryURL {
                await fileAdapter.cleanup(directoryURL: cleanupDirectoryURL)
            }
            finishWithFailure(error)
        }
    }

    private func finishWithFailure(_ error: Error) {
        pendingExportArtifact = nil
        pickerRequest = nil
        isBusy = false
        notice = MobileBackupNotice(
            kind: .failure,
            message: error.localizedDescription
        )
    }
}

struct MobileBackupDocumentPicker: UIViewControllerRepresentable {
    let request: MobileBackupPickerRequest
    let onComplete: (MobileBackupPickerResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker: UIDocumentPickerViewController
        switch request {
        case .importBackup:
            picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [
                    Self.backupPackageType,
                    .json
                ],
                asCopy: false
            )
            picker.allowsMultipleSelection = false
        case .exportBackup(let packageURL):
            picker = UIDocumentPickerViewController(
                forExporting: [packageURL],
                asCopy: true
            )
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onComplete: (MobileBackupPickerResult) -> Void

        init(onComplete: @escaping (MobileBackupPickerResult) -> Void) {
            self.onComplete = onComplete
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else {
                onComplete(.failed("선택한 파일을 확인할 수 없습니다."))
                return
            }
            onComplete(.selected(url))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete(.cancelled)
        }
    }

    private static let backupPackageType = UTType(
        exportedAs: PlanBaseCompatibility.backupPackageUTI,
        conformingTo: .package
    )
}
#endif
