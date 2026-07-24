import Foundation
import PlanBaseCore
import WidgetKit

struct PlanBaseCalendarEntry: TimelineEntry {
    let date: Date
    let snapshot: CalendarWidgetSnapshot
    let availability: PlanBaseWidgetSnapshotAvailability
    let monthSelection: CalendarWidgetMonthSelection
}

struct PlanBaseCalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlanBaseCalendarEntry {
        let date = Date()
        let snapshot = CalendarWidgetSnapshot.preview
        return PlanBaseCalendarEntry(
            date: date,
            snapshot: snapshot,
            availability: .available,
            monthSelection: CalendarWidgetMonthNavigation.selection(
                selectedMonthDayKey: nil,
                snapshot: snapshot,
                referenceDate: date
            )
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (PlanBaseCalendarEntry) -> Void
    ) {
        completion(entry(at: Date(), usesPreviewData: context.isPreview))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<PlanBaseCalendarEntry>) -> Void
    ) {
        let now = Date()
        let entry = entry(at: now, usesPreviewData: false)
        let nextDay = DayKey.addingDays(1, to: DayKey.startOfDay(for: now))
        completion(Timeline(entries: [entry], policy: .after(nextDay)))
    }

    private func entry(at date: Date, usesPreviewData: Bool) -> PlanBaseCalendarEntry {
        if usesPreviewData {
            let snapshot = CalendarWidgetSnapshot.preview
            return makeEntry(
                date: date,
                snapshot: snapshot,
                availability: .available,
                usesStoredSelection: false
            )
        }

        do {
            guard let snapshot = try CalendarWidgetSnapshotStore.read() else {
                return makeEntry(
                    date: date,
                    snapshot: .empty(at: date),
                    availability: .missing
                )
            }
            guard snapshot.covers(dayKey: DayKey.key(for: date)) else {
                return makeEntry(
                    date: date,
                    snapshot: .empty(at: date, themeID: snapshot.themeID),
                    availability: .staleCoverage
                )
            }
            return makeEntry(
                date: date,
                snapshot: snapshot,
                availability: .available
            )
        } catch CalendarWidgetSnapshotStore.StoreError.unsupportedSchemaVersion {
            return makeEntry(
                date: date,
                snapshot: .empty(at: date),
                availability: .unsupportedNewerSchema
            )
        } catch is DecodingError {
            return makeEntry(
                date: date,
                snapshot: .empty(at: date),
                availability: .corrupt
            )
        } catch {
            return makeEntry(
                date: date,
                snapshot: .empty(at: date),
                availability: .corrupt
            )
        }
    }

    private func makeEntry(
        date: Date,
        snapshot: CalendarWidgetSnapshot,
        availability: PlanBaseWidgetSnapshotAvailability,
        usesStoredSelection: Bool = true
    ) -> PlanBaseCalendarEntry {
        let monthSelection = usesStoredSelection
            ? CalendarWidgetMonthSelectionStore.selection(
                snapshot: snapshot,
                referenceDate: date
            )
            : CalendarWidgetMonthNavigation.selection(
                selectedMonthDayKey: nil,
                snapshot: snapshot,
                referenceDate: date
            )
        return PlanBaseCalendarEntry(
            date: date,
            snapshot: snapshot,
            availability: availability,
            monthSelection: monthSelection
        )
    }
}
