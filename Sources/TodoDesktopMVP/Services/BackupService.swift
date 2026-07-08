import AppKit
import EasyTaskCore
import Foundation
import SwiftData

enum BackupServiceResult {
    case completed
    case cancelled
}

enum BackupService {
    @MainActor
    static func exportJSON(context: ModelContext) throws -> BackupServiceResult {
        let data = try BackupCodec.encode(BackupCodec.makePayload(context: context))

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "todoapp-backup-\(DayKey.today).json"
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        try data.write(to: url)
        return .completed
    }

    @MainActor
    static func importReplacingAll(context: ModelContext) throws -> BackupServiceResult {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        let payload = try BackupCodec.decode(Data(contentsOf: url))
        try BackupCodec.replaceAll(with: payload, in: context)
        return .completed
    }
}
