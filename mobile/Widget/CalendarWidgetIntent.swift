import AppIntents
import Foundation
import PlanBaseCore
import SwiftUI
import WidgetKit

enum CalendarWidgetMonthSelectionStore {
    private static let selectedMonthDayKey = "calendarWidget.selectedMonthDayKey"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: CalendarWidgetConstants.appGroupIdentifier)
    }

    static func selection(
        snapshot: CalendarWidgetSnapshot,
        referenceDate: Date
    ) -> CalendarWidgetMonthSelection {
        CalendarWidgetMonthNavigation.selection(
            selectedMonthDayKey: defaults?.string(forKey: selectedMonthDayKey),
            snapshot: snapshot,
            referenceDate: referenceDate
        )
    }

    static func move(by monthDelta: Int, referenceDate: Date = Date()) {
        let snapshot = currentSnapshot(referenceDate: referenceDate)
        let selection = CalendarWidgetMonthNavigation.moving(
            selectedMonthDayKey: defaults?.string(forKey: selectedMonthDayKey),
            by: monthDelta,
            snapshot: snapshot,
            referenceDate: referenceDate
        )
        defaults?.set(DayKey.key(for: selection.month), forKey: selectedMonthDayKey)
    }

    static func reset() {
        defaults?.removeObject(forKey: selectedMonthDayKey)
    }

    private static func currentSnapshot(referenceDate: Date) -> CalendarWidgetSnapshot {
        do {
            return try CalendarWidgetSnapshotStore.read()
                ?? CalendarWidgetSnapshot(generatedAt: referenceDate, events: [])
        } catch {
            return CalendarWidgetSnapshot(generatedAt: referenceDate, events: [])
        }
    }
}

struct ChangeCalendarWidgetMonthIntent: AppIntent {
    static let title: LocalizedStringResource = "캘린더 위젯 월 이동"
    static let description = IntentDescription("PlanBase 캘린더 위젯의 표시 월을 이동합니다.")
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @Parameter(title: "이동 방향")
    var monthDelta: Int

    init() {}

    init(monthDelta: Int) {
        self.monthDelta = monthDelta
    }

    func perform() async throws -> some IntentResult {
        CalendarWidgetMonthSelectionStore.move(by: monthDelta)
        WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.kind)
        return .result()
    }
}

struct ResetCalendarWidgetMonthIntent: AppIntent {
    static let title: LocalizedStringResource = "이번 달 보기"
    static let description = IntentDescription("PlanBase 캘린더 위젯을 이번 달로 되돌립니다.")
    static let isDiscoverable = false
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        CalendarWidgetMonthSelectionStore.reset()
        WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.kind)
        return .result()
    }
}

struct RefreshCalendarWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "캘린더 일정 갱신"
    static let description = IntentDescription(
        "PlanBase를 열어 iCloud 일정과 캘린더 위젯을 갱신합니다."
    )
    static let isDiscoverable = false
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.kind)
        WidgetCenter.shared.reloadTimelines(
            ofKind: CalendarWidgetConstants.lockScreenKind
        )
        return .result()
    }
}
