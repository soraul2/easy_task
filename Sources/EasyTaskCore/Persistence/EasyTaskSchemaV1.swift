import SwiftData

public enum EasyTaskSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        [
            Task.self,
            CalendarEvent.self,
            TaskTemplate.self,
            TaskTemplateItem.self,
            TemplatePlacement.self,
            DailyReview.self,
            DiaryBlock.self
        ]
    }
}
