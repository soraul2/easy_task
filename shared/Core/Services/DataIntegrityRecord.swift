import Foundation

protocol IntegrityRecord: AnyObject {
    var id: UUID { get set }
    var instanceID: UUID { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var supersededAt: Date? { get set }
}

extension EasyTaskSchemaV3.CalendarEvent: IntegrityRecord {}
extension EasyTaskSchemaV3.TaskTemplate: IntegrityRecord {}
extension EasyTaskSchemaV3.TaskTemplateItem: IntegrityRecord {}
extension EasyTaskSchemaV3.TemplatePlacement: IntegrityRecord {}
extension EasyTaskSchemaV3.Task: IntegrityRecord {}
extension EasyTaskSchemaV3.DailyReview: IntegrityRecord {}
extension EasyTaskSchemaV3.DiaryBlock: IntegrityRecord {}
extension EasyTaskSchemaV3.DiaryAttachment: IntegrityRecord {}
extension EasyTaskSchemaV4.CalendarEvent: IntegrityRecord {}
extension EasyTaskSchemaV4.TaskTemplate: IntegrityRecord {}
extension EasyTaskSchemaV4.TaskTemplateItem: IntegrityRecord {}
extension EasyTaskSchemaV4.TemplatePlacement: IntegrityRecord {}
extension EasyTaskSchemaV4.Task: IntegrityRecord {}
extension EasyTaskSchemaV4.DailyReview: IntegrityRecord {}
extension EasyTaskSchemaV4.DiaryBlock: IntegrityRecord {}
extension EasyTaskSchemaV4.DiaryAttachment: IntegrityRecord {}
extension EasyTaskSchemaV5.CalendarEvent: IntegrityRecord {}
extension EasyTaskSchemaV5.TaskTemplate: IntegrityRecord {}
extension EasyTaskSchemaV5.TaskTemplateItem: IntegrityRecord {}
extension EasyTaskSchemaV5.TemplatePlacement: IntegrityRecord {}
extension EasyTaskSchemaV5.Task: IntegrityRecord {}
extension EasyTaskSchemaV5.TaskChecklistItem: IntegrityRecord {}
extension EasyTaskSchemaV5.DailyReview: IntegrityRecord {}
extension EasyTaskSchemaV5.DiaryBlock: IntegrityRecord {}
extension EasyTaskSchemaV5.DiaryAttachment: IntegrityRecord {}
extension EasyTaskSchemaV6.Memo: IntegrityRecord {}
