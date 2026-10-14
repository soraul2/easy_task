import Foundation

@available(watchOS 11, *)
protocol IntegrityRecord: AnyObject {
    var id: UUID { get set }
    var instanceID: UUID { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var supersededAt: Date? { get set }
}

@available(watchOS 11, *)
extension EasyTaskSchemaV3.CalendarEvent: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV3.TaskTemplate: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV3.TaskTemplateItem: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV3.TemplatePlacement: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV3.Task: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV3.DailyReview: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV3.DiaryBlock: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV3.DiaryAttachment: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV4.CalendarEvent: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV4.TaskTemplate: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV4.TaskTemplateItem: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV4.TemplatePlacement: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV4.Task: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV4.DailyReview: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV4.DiaryBlock: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV4.DiaryAttachment: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV5.CalendarEvent: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV5.TaskTemplate: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV5.TaskTemplateItem: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV5.TemplatePlacement: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV5.Task: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV5.TaskChecklistItem: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV5.DailyReview: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV5.DiaryBlock: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV5.DiaryAttachment: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV6.Memo: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV7.TaskCompletionActivity: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV8.TaskProgressEvent: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV9.Memo: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV9.MemoDrawing: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV9.MemoChecklistItem: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV10.FocusSession: IntegrityRecord {}
@available(watchOS 11, *)
extension EasyTaskSchemaV11.TaskTemplate: IntegrityRecord {}
