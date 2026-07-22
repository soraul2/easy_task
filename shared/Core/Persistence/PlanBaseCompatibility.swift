import Foundation

/// Identifiers that must remain stable for existing App Store installs,
/// CloudKit records, local media, and SwiftData stores.
public enum PlanBaseCompatibility {
    public static let appStoreBundleIdentifier = "com.soraul2.easytask"
    public static let cloudKitContainerIdentifier = "iCloud.com.soraul2.easytask"
    public static let applicationGroupIdentifier = "group.com.soraul2.easytask"
    public static let calendarWidgetKind = "com.soraul2.easytask.calendar-widget"
    public static let backupFormatIdentifier = "com.soraul2.easytask.backup"
    public static let legacyDeepLinkScheme = "easytask"
    public static let legacyTaskReminderIdentifierPrefix = "easytask.task-reminder."
    public static let modelConfigurationName = "EasyTask"
    public static let cloudKitStoreName = "EasyTask"
    public static let legacyStoreName = "EasyTaskLegacy"
    public static let legacyBackupRootDirectoryName = "EasyTaskLegacyBackups"
    public static let legacyPendingMarkerFileName = ".EasyTaskLegacyMigration.pending.json"
    public static let legacyMobileImageFolderName = "EasyTask"
    public static let legacyDesktopImageFolderName = "TodoDesktopMVP"
}
