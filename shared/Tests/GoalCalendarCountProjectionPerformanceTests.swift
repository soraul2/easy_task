#if DEBUG
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import EasyTaskCore

// Synthetic core CPU/wall time for iOS month-cell counts only. This does not
// measure macOS layout/title wrapping, SwiftUI frames, query reads, or CloudKit.
// PLANBASE_GOAL_CANDIDATE includes the adopted API for a current-only paired run.
// Without that flag this exact file can compile against the frozen baseline.
private let goalCountBenchmarkEnabled =
    ProcessInfo.processInfo.environment["PLANBASE_GOAL_CALENDAR_COUNT_PERFORMANCE"] == "1"
private let goalCountBenchmarkRepeatLabel =
    ProcessInfo.processInfo.environment["PLANBASE_GOAL_CALENDAR_COUNT_REPEAT"] ?? "1"
#if PLANBASE_GOAL_CANDIDATE
private let goalCountBenchmarkReferenceOnly =
    ProcessInfo.processInfo.environment["PLANBASE_GOAL_CALENDAR_COUNT_MODE"] == "reference"
#else
private let goalCountBenchmarkReferenceOnly = true
#endif

private struct GoalCountBenchmarkOutput: Equatable {
    let eventsByDayKey: [String: Int]
    let placementsByDayKey: [String: Int]

    var digest: String {
        let parts = eventsByDayKey.keys.sorted().flatMap { key in
            [key, String(eventsByDayKey[key] ?? 0), String(placementsByDayKey[key] ?? 0)]
        }
        return SHA256.hash(data: Data(parts.joined(separator: "\u{1f}").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
private struct GoalCountBenchmarkFixture {
    let container: ModelContainer
    let dates: [Date]
    let events: [CalendarEvent]
    let placements: [TemplatePlacement]
    let details: String

    init(eventCount: Int, monthKey: String) throws {
        container = try PlanBaseContainerFactory.makeInMemory()
        let month = try #require(DayKey.date(from: monthKey))
        dates = DayKey.adaptiveMonthGridDates(for: month)
        let gridStart = try #require(dates.first)
        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<eventCount {
            let crossBoundary = index.isMultiple(of: 19)
            let start = DayKey.addingDays(crossBoundary ? -2 : index % dates.count, to: gridStart)
            let duration = crossBoundary ? 6 : [0, 1, 2, 6, 11][index % 5]
            let title = index.isMultiple(of: 17)
                ? "긴 일정 제목 café 공장 점검 👩🏽‍💻\n" + String(repeating: "준비물 확인 ", count: 6)
                : String(format: "일정 %04d 공장 café", index)
            // Deliberately canonical logical IDs: transient duplicate semantics
            // belong to ordinary correctness tests, not a physical-count oracle.
            context.insert(CalendarEvent(
                id: goalCountBenchmarkID(index + 1), instanceID: goalCountBenchmarkID(index + 100_001),
                title: title, startAt: start, endAt: DayKey.addingDays(duration, to: start),
                note: index.isMultiple(of: 7) ? "합성 메모" : nil,
                color: index.isMultiple(of: 3) ? "red" : "blue",
                createdAt: timestamp, updatedAt: timestamp.addingTimeInterval(Double(index)),
                supersededAt: index > 0 && index.isMultiple(of: 31) ? timestamp : nil))
        }
        for index in 0..<max(1, eventCount / 10) {
            context.insert(TemplatePlacement(
                id: goalCountBenchmarkID(index + 200_001), instanceID: goalCountBenchmarkID(index + 300_001),
                sourceTemplateId: nil, templateName: "합성 배치 \(index)",
                dayKey: DayKey.key(for: dates[index % dates.count]),
                createdAt: timestamp.addingTimeInterval(Double(index)), updatedAt: timestamp))
        }
        try context.save()
        let firstKey = DayKey.key(for: gridStart)
        let lastKey = DayKey.key(for: try #require(dates.last))
        events = try context.fetch(BoundedQueryService.eventsDescriptor(
            overlappingStartDayKey: firstKey, endDayKey: lastKey))
        placements = try context.fetch(BoundedQueryService.templatePlacementsDescriptor(
            from: firstKey, through: lastKey))
        details = "storedEvents=\(eventCount) activeEvents=\(events.count) logicalIDs=unique dates=\(dates.count) placements=\(placements.count) month=\(monthKey)"
    }
}

private func goalCountBenchmarkID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llx", Int64(value)))!
}

// Literal frozen original cell loop from GoalCalendarPerformanceTests.swift
// (SHA256 9554eec46a6d3318dad8de17561a4459edc823f0fa2a19a00501e7726bd02bb4).
// Frozen MobileCalendarView.swift SHA256:
// bb1f8ce713bc47583448e91872eb622980f446892c9a2fb99b1760dcdb7cf946.
// Keep filter + sort + count, including placement localized sorting, intact.
@MainActor
private func goalOriginalCalendarCountLoop(_ fixture: GoalCountBenchmarkFixture) -> GoalCountBenchmarkOutput {
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

#if PLANBASE_GOAL_CANDIDATE
@MainActor
private func goalAdoptedCalendarCountProjection(_ fixture: GoalCountBenchmarkFixture) -> GoalCountBenchmarkOutput {
    let projection = CalendarMonthCountProjection.make(
        dates: fixture.dates, events: fixture.events, templatePlacements: fixture.placements)
    return .init(eventsByDayKey: projection.eventCountByDayKey, placementsByDayKey: projection.placementCountByDayKey)
}
#endif

@MainActor
@inline(never)
private func goalTimeCalendarCounts(
    _ operation: () -> GoalCountBenchmarkOutput
) -> (output: GoalCountBenchmarkOutput, milliseconds: Double) {
    let start = DispatchTime.now().uptimeNanoseconds
    let output = operation()
    let elapsed = DispatchTime.now().uptimeNanoseconds - start
    return (output, Double(elapsed) / 1_000_000)
}

private func goalPrintCalendarCountSamples(
    algorithm: String, details: String, samples: [Double], digest: String, paired: Bool
) {
    let ordered = samples.sorted()
    let p95Index = Int(ceil(Double(samples.count) * 0.95)) - 1
    // One invocation is one independently prepared fixture run per case.
    // These n=30 samples are repeated/paired operations, not 30 independent runs.
    print("GOAL_CALENDAR_COUNT_BENCHMARK scope=ios-month-cell-counts algorithm=\(algorithm) unit=ms warmupPerAlgorithm=1 n=\(samples.count) paired=\(paired) independentInvocationCount=1 repeatLabel=\(goalCountBenchmarkRepeatLabel) \(details) timezone=\(TimeZone.current.identifier) p50=\(ordered[samples.count / 2]) p95=\(ordered[p95Index]) max=\(ordered.last ?? 0) digest=\(digest) samples=\(samples)")
}

@Test(.enabled(if: goalCountBenchmarkEnabled && goalCountBenchmarkReferenceOnly))
@MainActor
func goalCalendarOriginalCellLoopPerformance() throws {
    for monthKey in ["2026-07-01", "2026-08-01"] {
        for eventCount in [30, 200, 1_000] {
            let fixture = try GoalCountBenchmarkFixture(eventCount: eventCount, monthKey: monthKey)
            #expect(fixture.dates.count == (monthKey == "2026-07-01" ? 35 : 42))
            let expected = goalOriginalCalendarCountLoop(fixture)
            let expectedDigest = expected.digest
            var samples: [Double] = []
            for _ in 0..<30 {
                let measurement = goalTimeCalendarCounts { goalOriginalCalendarCountLoop(fixture) }
                samples.append(measurement.milliseconds)
                #expect(measurement.output == expected)
                #expect(measurement.output.digest == expectedDigest)
            }
            goalPrintCalendarCountSamples(algorithm: "frozen-original-reference", details: fixture.details,
                samples: samples, digest: expectedDigest, paired: false)
        }
    }
}

#if PLANBASE_GOAL_CANDIDATE
@Test(.enabled(if: goalCountBenchmarkEnabled && !goalCountBenchmarkReferenceOnly))
@MainActor
func goalCalendarCountProjectionPairedPerformance() throws {
    for monthKey in ["2026-07-01", "2026-08-01"] {
        for eventCount in [30, 200, 1_000] {
            let fixture = try GoalCountBenchmarkFixture(eventCount: eventCount, monthKey: monthKey)
            #expect(fixture.dates.count == (monthKey == "2026-07-01" ? 35 : 42))
            let expected = goalOriginalCalendarCountLoop(fixture)
            let candidateWarmup = goalAdoptedCalendarCountProjection(fixture)
            #expect(candidateWarmup == expected)
            let expectedDigest = expected.digest
            var referenceSamples: [Double] = []
            var candidateSamples: [Double] = []
            for index in 0..<30 {
                let reference: (output: GoalCountBenchmarkOutput, milliseconds: Double)
                let candidate: (output: GoalCountBenchmarkOutput, milliseconds: Double)
                // Alternate first position to distribute temporal/order effects.
                if index.isMultiple(of: 2) {
                    reference = goalTimeCalendarCounts { goalOriginalCalendarCountLoop(fixture) }
                    candidate = goalTimeCalendarCounts { goalAdoptedCalendarCountProjection(fixture) }
                } else {
                    candidate = goalTimeCalendarCounts { goalAdoptedCalendarCountProjection(fixture) }
                    reference = goalTimeCalendarCounts { goalOriginalCalendarCountLoop(fixture) }
                }
                referenceSamples.append(reference.milliseconds)
                candidateSamples.append(candidate.milliseconds)
                // All comparisons, digests, and reporting are outside both timers.
                #expect(reference.output == expected)
                #expect(candidate.output == expected)
                #expect(reference.output.digest == expectedDigest)
                #expect(candidate.output.digest == expectedDigest)
            }
            let details = fixture.details + " pairs=30 order=alternating-reference-candidate"
            goalPrintCalendarCountSamples(algorithm: "frozen-original-reference", details: details,
                samples: referenceSamples, digest: expectedDigest, paired: true)
            goalPrintCalendarCountSamples(algorithm: "actual-core-projection", details: details,
                samples: candidateSamples, digest: expectedDigest, paired: true)
        }
    }
}
#endif
#endif
