import AppKit
import PlanBaseCore
import Foundation
import SwiftData
import UniformTypeIdentifiers

enum BackupServiceResult {
    case completed(String)
    case cancelled
}

enum BackupService {
    @MainActor
    static func exportPackage(context: ModelContext) throws -> BackupServiceResult {
        let contents = try BackupPackageCodec.makeContents(context: context)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [backupPackageType]
        panel.nameFieldStringValue = "planbase-backup-\(DayKey.today).easytaskbackup"
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        try BackupPackageCodec.write(contents, to: url)
        return .completed("이미지 원본을 포함한 백업을 내보냈습니다.")
    }

    @MainActor
    static func importBackup(context: ModelContext) throws -> BackupServiceResult {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [backupPackageType, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        guard try endActiveFocusForImportIfConfirmed(context: context) else {
            return .cancelled
        }
        try FocusSessionService.requireNoActiveSessionForBackupImport()

        if url.pathExtension.lowercased() != "json" {
            let contents = try BackupPackageCodec.read(from: url)
            let report = try BackupPackageCodec.restoreMerging(contents, into: context)
            let imported = report.insertedRecords + report.updatedRecords
            let attachments = report.insertedAttachments + report.updatedAttachments
            notifyDataChanged(context: context)
            return .completed("백업을 병합했습니다. 데이터 \(imported)건, 이미지 \(attachments)건 반영")
        }

        let payload = try BackupCodec.decode(Data(contentsOf: url))
        let report = try BackupPackageCodec.restoreLegacyJSONMerging(payload, into: context)
        notifyDataChanged(context: context)
        let missingCount = report.referencedImageFileNames.filter {
            !FileManager.default.fileExists(atPath: DiaryImageStore.imageURL(for: $0).path)
        }.count
        if missingCount > 0 {
            return .completed("JSON V1을 가져왔습니다. 포함되지 않은 이미지 원본 \(missingCount)개를 확인하세요.")
        }
        return .completed("JSON V1 백업을 가져왔습니다.")
    }

    private static func notifyDataChanged(context: ModelContext) {
        NotificationCenter.default.post(
            name: PersistenceCommandService.dataChangedNotification,
            object: context
        )
    }

    @MainActor
    private static func endActiveFocusForImportIfConfirmed(
        context: ModelContext
    ) throws -> Bool {
        guard let snapshot = try FocusSessionService.activeSnapshot() else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "진행 중인 타이머를 종료할까요?"
        alert.informativeText = "백업을 병합하기 전에 현재 집중 기록을 안전하게 저장합니다."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "종료하고 백업 가져오기")
        alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        if snapshot.phase == .breakTime {
            let current = try FocusSessionService.activeSnapshot()
            guard current?.sessionID == snapshot.sessionID,
                  current?.revision == snapshot.revision else {
                throw FocusSessionServiceError.staleCommand
            }
            try FocusActiveSessionStore.clear()
        } else {
            _ = try FocusSessionService.endFocus(
                outcome: .interrupted,
                expectedSessionID: snapshot.sessionID,
                expectedRevision: snapshot.revision,
                in: context
            )
        }
        return true
    }

    private static let backupPackageType = UTType(
        exportedAs: "com.soraul2.easytask.backup-package",
        conformingTo: .package
    )
}
