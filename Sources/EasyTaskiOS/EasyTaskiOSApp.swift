#if os(iOS)
import Combine
import EasyTaskCore
import Foundation
import SwiftData
import SwiftUI

@main
struct EasyTaskiOSApp: App {
    private let modelContainer: ModelContainer

    init() {
        if let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            try? FileManager.default.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
        }

        do {
#if DEBUG
            _ = try EasyTaskContainerFactory.initializeDevelopmentCloudKitSchemaIfRequested()
#endif
            modelContainer = try EasyTaskContainerFactory.makePersistent(
                mode: EasyTaskContainerFactory.appStoreMode
            )
        } catch {
            fatalError("EasyTask 저장소를 열 수 없습니다: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MobileAppRootView()
        }
        .modelContainer(modelContainer)
    }
}

private enum MobileTab: String, CaseIterable, Identifiable {
    case board
    case calendar
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .board: "칸반"
        case .calendar: "캘린더"
        case .archive: "기록"
        }
    }

    var symbol: String {
        switch self {
        case .board: "rectangle.3.group"
        case .calendar: "calendar"
        case .archive: "book.pages"
        }
    }
}

private struct MobileAppRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [TodoTask]
    @Query private var events: [CalendarEvent]
    @Query private var templates: [TaskTemplate]
    @Query private var reviews: [DailyReview]

    @State private var selectedTab: MobileTab = .board
    @State private var selectedBoardDate = DayKey.startOfDay(for: Date())
    @State private var themeRevision = 0
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppThemePreset.defaultID

    var body: some View {
        TabView(selection: $selectedTab) {
            MobileBoardView(selectedDate: $selectedBoardDate)
                .tabItem {
                    Image(systemName: MobileTab.board.symbol)
                        .accessibilityLabel(MobileTab.board.title)
                }
                .tag(MobileTab.board)

            MobileCalendarView { date in
                selectedBoardDate = date
                selectedTab = .board
            }
            .tabItem {
                Image(systemName: MobileTab.calendar.symbol)
                    .accessibilityLabel(MobileTab.calendar.title)
            }
            .tag(MobileTab.calendar)

            MobileArchiveView { date in
                selectedBoardDate = date
                selectedTab = .board
            }
            .tabItem {
                Image(systemName: MobileTab.archive.symbol)
                    .accessibilityLabel(MobileTab.archive.title)
            }
            .tag(MobileTab.archive)
        }
        .tint(AppTheme.event)
        .background(AppTheme.background)
        .id("\(selectedThemeID)-\(colorScheme)-\(themeRevision)")
        .task {
            start()
        }
        .onChange(of: selectedTab) {
            TaskRules.archiveIfNeeded(tasks)
        }
        .onChange(of: colorScheme) {
            AppTheme.activate(selectedThemeID, colorScheme: colorScheme)
            themeRevision += 1
        }
        .onReceive(NotificationCenter.default.publisher(
            for: CloudKitSyncService.eventChangedNotification
        )) { notification in
            handleCloudKitEvent(notification)
        }
    }

    private func start() {
        let migratedThemeID = AppTheme.migrateStoredDefaultIfNeeded(selectedThemeID)
        if migratedThemeID != selectedThemeID {
            selectedThemeID = migratedThemeID
        }
        AppTheme.activate(migratedThemeID, colorScheme: colorScheme)
        themeRevision += 1
        do {
            try DataIntegrityService.reconcile(context: modelContext)
            let migration = try LegacyDiaryAttachmentMigrationService.migrateIfNeeded(
                context: modelContext,
                appSupportFolder: MobileImageStorage.appSupportFolder
            )
            if !migration.missingFileNames.isEmpty ||
                !migration.rejectedFileNames.isEmpty ||
                !migration.deferredFileNames.isEmpty {
                print(
                    "EasyTask legacy image migration pending: " +
                        "missing=\(migration.missingFileNames.count), " +
                        "rejected=\(migration.rejectedFileNames.count), " +
                        "deferred=\(migration.deferredFileNames.count)"
                )
            }
        } catch {
            print("EasyTask data reconciliation failed: \(error.localizedDescription)")
        }
        SeedService.seedIfNeeded(
            context: modelContext,
            tasks: tasks,
            events: events,
            templates: templates,
            reviews: reviews,
            policy: .appStartup(
                cloudKitEnabled: EasyTaskContainerFactory.appStoreMode.usesCloudKit
            )
        )
        TaskRules.archiveIfNeeded(tasks)
    }

    private func handleCloudKitEvent(_ notification: Notification) {
        do {
            guard let summary = try CloudKitSyncService.handle(
                notification,
                context: modelContext
            ), summary.isCompleted else { return }

            if summary.succeeded {
                print("EasyTask CloudKit \(summary.kind.rawValue) completed")
            } else {
                print(
                    "EasyTask CloudKit \(summary.kind.rawValue) failed: " +
                        (summary.errorDescription ?? "unknown error")
                )
            }
        } catch {
            print("EasyTask post-sync reconciliation failed: \(error.localizedDescription)")
        }
    }
}
#else
@main
struct EasyTaskiOSPlaceholder {
    static func main() {
        print("EasyTaskiOS builds only for iOS.")
    }
}
#endif
