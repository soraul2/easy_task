#if DEBUG
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

// Opt-in synthetic measurements only. These measure CPU/wall time of core work,
// not rendered frames, keyboard latency, or CloudKit. Fixtures are memory-only.
private let goalCalendarPerformanceEnabled =
    ProcessInfo.processInfo.environment["PLANBASE_GOAL_CALENDAR_PERFORMANCE"] == "1"

private enum GoalCalendarCountAlgorithm: String {
    case reference, current

    static var selected: Self {
        Self(rawValue: ProcessInfo.processInfo.environment["PLANBASE_GOAL_CALENDAR_COUNTS"] ?? "current") ?? .current
    }
}

private struct GoalCalendarCellCounts: Equatable {
    var eventsByDayKey: [String: Int]
    var placementsByDayKey: [String: Int]

    var digest: String {
        goalCalendarDigest(eventsByDayKey.keys.sorted().flatMap { key in
            [key, String(eventsByDayKey[key] ?? 0), String(placementsByDayKey[key] ?? 0)]
        })
    }
}

@MainActor
private struct GoalCalendarFixture {
    let container: ModelContainer
    let month: Date
    let dates: [Date]
    let events: [CalendarEvent]
    let placements: [TemplatePlacement]
    let requestedEventCount: Int

    init(eventCount: Int, monthKey: String) throws {
        container = try PlanBaseContainerFactory.makeInMemory()
        month = try #require(DayKey.date(from: monthKey))
        dates = DayKey.adaptiveMonthGridDates(for: month)
        requestedEventCount = eventCount
        let gridStart = try #require(dates.first)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let context = container.mainContext
        for index in 0..<eventCount {
            let crossBoundary = index.isMultiple(of: 19)
            let start = DayKey.addingDays(crossBoundary ? -2 : index % dates.count, to: gridStart)
            let duration = crossBoundary ? 6 : [0, 1, 2, 6, 11][index % 5]
            // Adjacent physical rows occasionally share a logical ID, including
            // moved ranges. Superseded rows are excluded by the real descriptor.
            let logicalIndex = index > 0 && index.isMultiple(of: 25) ? index : index + 1
            let title = index.isMultiple(of: 17)
                ? "긴 일정 제목 café 공장 점검 👩🏽‍💻\n" + String(repeating: "준비물 확인 ", count: 6)
                : String(format: "일정 %04d 공장 café", index)
            context.insert(CalendarEvent(
                id: goalCalendarID(logicalIndex), instanceID: goalCalendarID(index + 100_001),
                title: title, startAt: start, endAt: DayKey.addingDays(duration, to: start),
                note: index.isMultiple(of: 7) ? "합성 메모" : nil,
                color: index.isMultiple(of: 3) ? "red" : "blue",
                createdAt: timestamp, updatedAt: timestamp.addingTimeInterval(Double(index)),
                supersededAt: index > 0 && index.isMultiple(of: 31) ? timestamp : nil
            ))
        }
        for index in 0..<max(1, eventCount / 10) {
            context.insert(TemplatePlacement(
                id: goalCalendarID(index + 200_001), instanceID: goalCalendarID(index + 300_001),
                sourceTemplateId: nil,
                templateName: "합성 배치 \(index)",
                dayKey: DayKey.key(for: dates[index % dates.count]),
                createdAt: timestamp.addingTimeInterval(Double(index)), updatedAt: timestamp
            ))
        }
        try context.save()
        let firstKey = DayKey.key(for: gridStart)
        let lastKey = DayKey.key(for: try #require(dates.last))
        events = try context.fetch(BoundedQueryService.eventsDescriptor(
            overlappingStartDayKey: firstKey, endDayKey: lastKey))
        placements = try context.fetch(BoundedQueryService.templatePlacementsDescriptor(
            from: firstKey, through: lastKey))
    }

    var layoutItems: [CalendarEventGridLayoutItem] {
        events.filter { $0.supersededAt == nil }.map {
            CalendarEventGridLayoutItem(
                renderID: $0.instanceID, eventID: $0.id, title: $0.title,
                startDayKey: $0.startDayKey, endDayKey: $0.endDayKey, updatedAt: $0.updatedAt)
        }
    }
}

private func goalCalendarID(_ index: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(index)))!
}

private func goalCalendarDigest(_ parts: [String]) -> String {
    SHA256.hash(data: Data(parts.joined(separator: "\u{1f}").utf8))
        .map { String(format: "%02x", $0) }.joined()
}

private func goalCalendarLayoutDigest(_ layout: CalendarEventGridLayoutResult) -> String {
    var parts = [String(layout.rowCount)]
    for segment in layout.segments {
        parts.append(contentsOf: [segment.renderID.uuidString, segment.eventID.uuidString,
            String(segment.weekIndex), String(segment.startColumn), String(segment.span),
            String(segment.lane), String(segment.laneSpan), String(segment.isDimmed)])
    }
    for key in layout.displayedEventIDsByDayKey.keys.sorted() {
        parts.append(key)
        parts.append(contentsOf: (layout.displayedEventIDsByDayKey[key] ?? []).map(\.uuidString).sorted())
    }
    for key in layout.hiddenEventCountByDayKey.keys.sorted() {
        parts.append(contentsOf: [key, String(layout.hiddenEventCountByDayKey[key] ?? 0)])
    }
    return goalCalendarDigest(parts)
}

// Freeze the starting MobileCalendarView cell preparation, including its
// full filter/sort and physical-row counts. This is the correctness reference
// for a later count-only proposal, not a proposed production implementation.
@MainActor
private func goalReferenceCalendarCellCounts(_ fixture: GoalCalendarFixture) -> GoalCalendarCellCounts {
    var eventCounts: [String: Int] = [:]
    var placementCounts: [String: Int] = [:]
    for date in fixture.dates {
        let key = DayKey.key(for: date)
        eventCounts[key] = fixture.events.filter {
            $0.supersededAt == nil && $0.startDayKey <= key && key <= $0.endDayKey
        }.sorted { lhs, rhs in
            if lhs.startDayKey != rhs.startDayKey { return lhs.startDayKey < rhs.startDayKey }
            if lhs.endDayKey != rhs.endDayKey { return lhs.endDayKey > rhs.endDayKey }
            return lhs.title < rhs.title
        }.count
        placementCounts[key] = fixture.placements.filter {
            $0.supersededAt == nil && $0.dayKey == key
        }.sorted { lhs, rhs in
            if lhs.dayKey != rhs.dayKey { return lhs.dayKey < rhs.dayKey }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.templateName.localizedStandardCompare(rhs.templateName) == .orderedAscending
        }.count
    }
    return .init(eventsByDayKey: eventCounts, placementsByDayKey: placementCounts)
}

@MainActor
private func goalCurrentCalendarCellCounts(_ fixture: GoalCalendarFixture) -> GoalCalendarCellCounts {
    // The baseline calls the existing shared APIs, with no new cache or candidate.
    // Once measured and separately authorized, this adapter can call the adopted
    // production count API while the frozen reference remains unchanged.
    var eventCounts: [String: Int] = [:]
    var placementCounts: [String: Int] = [:]
    for date in fixture.dates {
        let key = DayKey.key(for: date)
        eventCounts[key] = CalendarEventRules.events(on: date, in: fixture.events).count
        placementCounts[key] = TemplateService.placements(on: date, in: fixture.placements).count
    }
    return .init(eventsByDayKey: eventCounts, placementsByDayKey: placementCounts)
}

@MainActor
private func goalCalendarReport<Output>(
    name: String, details: String, samples count: Int = 30,
    operation: () throws -> Output, digest: (Output) -> String
) rethrows {
    let warmup = try operation()
    let expectedDigest = digest(warmup)
    var samples: [Double] = []
    samples.reserveCapacity(count)
    for _ in 0..<count {
        let start = DispatchTime.now().uptimeNanoseconds
        let output = try operation()
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        // Digest, assertions, fixture generation, and log output are untimed.
        #expect(digest(output) == expectedDigest)
    }
    let ordered = samples.sorted()
    let p95Index = Int(ceil(Double(count) * 0.95)) - 1
    print("GOAL_CALENDAR_BENCHMARK name=\(name) unit=ms warmup=1 n=\(count) \(details) timezone=\(TimeZone.current.identifier) p50=\(ordered[count / 2]) p95=\(ordered[p95Index]) max=\(ordered.last ?? 0) digest=\(expectedDigest) samples=\(samples)")
}

@Test(.enabled(if: goalCalendarPerformanceEnabled))
@MainActor
func goalCalendarMonthAndTimelinePerformance() throws {
    let algorithm = GoalCalendarCountAlgorithm.selected
    for monthKey in ["2026-07-01", "2026-08-01"] {
        for eventCount in [30, 200, 1_000] {
            let fixture = try GoalCalendarFixture(eventCount: eventCount, monthKey: monthKey)
            #expect(fixture.dates.count == (monthKey == "2026-07-01" ? 35 : 42))
            let details = "storedEvents=\(eventCount) activeEvents=\(fixture.events.count) dates=\(fixture.dates.count) placements=\(fixture.placements.count) month=\(monthKey)"
            let referenceCounts = goalReferenceCalendarCellCounts(fixture)
            #expect(goalCurrentCalendarCellCounts(fixture) == referenceCounts)
            goalCalendarReport(name: "month-cell-counts-\(algorithm.rawValue)", details: details,
                operation: {
                    algorithm == .reference
                        ? goalReferenceCalendarCellCounts(fixture)
                        : goalCurrentCalendarCellCounts(fixture)
                }, digest: { $0.digest })

            // Separate core lane layout from view preparation and font metrics.
            let items = fixture.layoutItems
            let expandedIDs = Set(items.filter { $0.startDayKey == $0.endDayKey && $0.title.contains(where: \.isNewline) }.map(\.renderID))
            goalCalendarReport(name: "grid-layout-core", details: details + " lanes=4",
                operation: {
                    CalendarEventGridLayout.make(items: items, dates: fixture.dates,
                        visibleMonth: fixture.month, maximumLanes: 4, expandedTitleRenderIDs: expandedIDs)
                }, digest: goalCalendarLayoutDigest)

            #if os(iOS) || os(macOS)
            // The desktop month body uses font size 11. Geometry is fixed here;
            // rendered width/rotation/dynamic-type behavior remains a UI test.
            goalCalendarReport(name: "month-prepare-title-wrap-layout", details: details + " titleWidth=70 font=11 lanes=4",
                operation: {
                    let active = fixture.events.filter { $0.supersededAt == nil }
                    let currentItems = active.map {
                        CalendarEventGridLayoutItem(renderID: $0.instanceID, eventID: $0.id,
                            title: $0.title, startDayKey: $0.startDayKey, endDayKey: $0.endDayKey,
                            updatedAt: $0.updatedAt)
                    }
                    let expanded = Set(active.filter {
                        $0.startDayKey == $0.endDayKey
                            && CalendarEventTitleMetrics.needsTwoLines($0.title, width: 70, fontSize: 11)
                    }.map(\.instanceID))
                    return CalendarEventGridLayout.make(items: currentItems, dates: fixture.dates,
                        visibleMonth: fixture.month, maximumLanes: 4, expandedTitleRenderIDs: expanded)
                }, digest: goalCalendarLayoutDigest)
            #endif

            let selectedDate = fixture.dates[fixture.dates.count / 2]
            let dayEvents = CalendarEventRules.events(on: selectedDate, in: fixture.events)
            goalCalendarReport(name: "day-event-date-range-text", details: details + " visibleRows=\(dayEvents.count)",
                operation: { dayEvents.map { CalendarEventTimeline.dateRangeText(for: $0) } },
                digest: goalCalendarDigest)
        }
    }
}

// Calendar preview is a distinct optional run: it performs real bounded fetches
// on synthetic memory data, not a stand-in array filter. Selection accumulation
// and mutating apply/save are separate designs documented with this harness.
@Test(.enabled(if: goalCalendarPerformanceEnabled &&
    ProcessInfo.processInfo.environment["PLANBASE_GOAL_CALENDAR_TEMPLATE_PERFORMANCE"] == "1"))
@MainActor
func goalCalendarTemplatePreviewPerformance() throws {
    let firstDate = try #require(DayKey.date(from: "2026-07-01"))
    for dayCount in [1, 7, 30] {
        for tasksPerDay in [0, 24, 240] {
            let container = try PlanBaseContainerFactory.makeInMemory()
            let context = container.mainContext
            let dates = (0..<dayCount).map { DayKey.addingDays($0, to: firstDate) }
            let keys = dates.map(DayKey.key(for:)).sorted()
            for (dayIndex, date) in dates.enumerated() {
                for index in 0..<tasksPerDay {
                    let task = Task(title: "기존 제목 \(index)",
                        status: index.isMultiple(of: 5) ? .doing : .todo,
                        plannedAt: date, order: Double(index) * 100,
                        createdAt: firstDate, updatedAt: firstDate)
                    task.id = goalCalendarID(dayIndex * max(tasksPerDay, 1) + index + 400_001)
                    task.instanceID = goalCalendarID(dayIndex * max(tasksPerDay, 1) + index + 500_001)
                    if index > 0 && index.isMultiple(of: 13) { task.archivedAt = firstDate }
                    if index > 0 && index.isMultiple(of: 17) { task.supersededAt = firstDate }
                    context.insert(task)
                }
            }
            try context.save()
            for draftCount in [1, 10] {
                var drafts: [TemplateTaskDraft] = []
                drafts.reserveCapacity(draftCount)
                for index in 0..<draftCount {
                    let title: String
                    if index == 0 {
                        title = "  기존 제목 1  "
                    } else if index == 7 {
                        title = " \n "
                    } else {
                        let titleIndex = index == 9 ? 8 : index
                        title = "신규 제목 \(titleIndex)"
                    }
                    let order: Double = Double(index) * 100
                    let identifier = goalCalendarID(index + 600_001)
                    let draft = TemplateTaskDraft(id: identifier, title: title, order: order)
                    drafts.append(draft)
                }
                try goalCalendarReport(name: "template-selected-days-preview",
                    details: "dates=\(dayCount) tasksPerDay=\(tasksPerDay) drafts=\(draftCount) fetchesPerOperation=\(keys.count)",
                    operation: { () throws -> TemplateApplicationSummary in
                        let tasks: [Task] = try keys.flatMap { key in
                            try BoundedQueryService.tasks(from: key, through: key, in: context)
                        }
                        return TemplateApplicationRules.summary(drafts: drafts, dates: dates, tasks: tasks)
                    }, digest: { goalCalendarDigest([String($0.totalCount), String($0.newCount), String($0.duplicateCount)]) })
            }
        }
    }
}
#endif
