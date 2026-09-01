import Foundation
import SwiftData

public enum MemoEditorMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case drawing
    case checklist

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .text:
            "텍스트"
        case .drawing:
            "필기"
        case .checklist:
            "체크리스트"
        }
    }

    public var systemImage: String {
        switch self {
        case .text:
            "text.alignleft"
        case .drawing:
            "pencil.tip"
        case .checklist:
            "checklist"
        }
    }
}

public enum EasyTaskSchemaV9: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(9, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        EasyTaskSchemaV5.models + [
            Memo.self,
            EasyTaskSchemaV7.TaskCompletionActivity.self,
            EasyTaskSchemaV8.TaskProgressEvent.self,
            MemoDrawing.self,
            MemoChecklistItem.self
        ]
    }

    @Model
    public final class Memo {
        public var id: UUID = UUID()
        public var instanceID: UUID = UUID()
        public var content: String = ""
        public var isPinned: Bool = false
        public var preferredModeRawValue: String = MemoEditorMode.text.rawValue

        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var supersededAt: Date?

        public init(
            id: UUID = UUID(),
            instanceID: UUID = UUID(),
            content: String,
            isPinned: Bool = false,
            preferredMode: MemoEditorMode = .text,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            supersededAt: Date? = nil
        ) {
            self.id = id
            self.instanceID = instanceID
            self.content = content
            self.isPinned = isPinned
            self.preferredModeRawValue = preferredMode.rawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.supersededAt = supersededAt
        }
    }

    @Model
    public final class MemoDrawing {
        #Index<MemoDrawing>([\.id], [\.memoId])

        public var id: UUID = UUID()
        public var instanceID: UUID = UUID()
        public var memoId: UUID = UUID()
        @Attribute(.externalStorage) public var drawingData: Data = Data()

        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var supersededAt: Date?

        public init(
            id: UUID = UUID(),
            instanceID: UUID = UUID(),
            memoId: UUID,
            drawingData: Data,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            supersededAt: Date? = nil
        ) {
            self.id = id
            self.instanceID = instanceID
            self.memoId = memoId
            self.drawingData = drawingData
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.supersededAt = supersededAt
        }
    }

    @Model
    public final class MemoChecklistItem {
        #Index<MemoChecklistItem>([\.id], [\.memoId], [\.memoId, \.order])

        public var id: UUID = UUID()
        public var instanceID: UUID = UUID()
        public var memoId: UUID = UUID()
        public var title: String = ""
        public var isCompleted: Bool = false
        public var order: Double = 0
        public var completedAt: Date?

        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var supersededAt: Date?

        public init(
            id: UUID = UUID(),
            instanceID: UUID = UUID(),
            memoId: UUID,
            title: String,
            isCompleted: Bool = false,
            order: Double,
            completedAt: Date? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            supersededAt: Date? = nil
        ) {
            self.id = id
            self.instanceID = instanceID
            self.memoId = memoId
            self.title = title
            self.isCompleted = isCompleted
            self.order = order
            self.completedAt = completedAt
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.supersededAt = supersededAt
        }
    }
}
