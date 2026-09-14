#if os(iOS) || os(macOS)
import SwiftData
import SwiftUI

public struct TaskRecordSheet: View {
    private let selection: TaskRecordSelection
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var record: TaskRecord?
    @State private var errorMessage: String?
    @State private var refreshID = 0
    @State private var visibleEventCount = 20

    public init(selection: TaskRecordSelection) { self.selection = selection }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let errorMessage {
                        ContentUnavailableView {
                            Label(
                                "작업 기록을 불러오지 못했어요",
                                systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("다시 시도") { refreshID += 1 }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("task-record-retry")
                        }
                    } else if let record {
                        content(record)
                    } else {
                        ProgressView("작업 기록을 불러오는 중")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
                .padding(20)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.background)
            .foregroundStyle(AppTheme.primaryText)
            .navigationTitle("작업 기록")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .accessibilityIdentifier("archive-task-record")
        }
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 640, minHeight: 640, idealHeight: 760)
        #endif
        .task(id: refreshID) { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshID += 1 }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: PersistenceCommandService.dataChangedNotification)
        ) { notification in
            guard PersistenceCommandService.affects(.tasks, in: notification) else { return }
            guard let source = notification.object as? ModelContext, source === modelContext else { return }
            refreshID += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            refreshID += 1
        }
    }

    @ViewBuilder
    private func content(_ record: TaskRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(record.title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("task-record-title")
            if let rawStatus = record.currentStatus, let status = TaskStatus(rawValue: rawStatus) {
                Label("현재 \(status.title)", systemImage: status.systemImage)
                    .font(.subheadline.weight(.medium))
            }
            Text("만든 날짜 · \(record.createdAt.map(timestamp) ?? "기록 없음")")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .accessibilityIdentifier("task-record-created")
            if !record.hasCurrentTask {
                Text("원본 작업은 없지만 남아 있는 활동 기록은 계속 볼 수 있어요.")
                    .font(.callout).foregroundStyle(AppTheme.secondaryText)
                    .accessibilityIdentifier("task-record-missing-task")
            }
        }

        section("\(dayText(selection.dayKey))의 활동") {
            let day = record.selectedDay
            if day.completed {
                Label("이날 완료 처리", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
            } else if day.legacyCompletion {
                Text("이전 완료 기록이 있어요. 실제 처리 시각은 남아 있지 않아요.")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
            }
            metrics(
                progress: day.progressSeconds, focus: day.focusSeconds,
                identifier: "task-record-day")
            if day.focusSessionCount > 0 {
                Text("집중 시간은 이날 종료한 세션 기준이에요.")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            if day.started && day.progressSeconds == 0 {
                Text("진행 시작 기록이 있어요. 종료가 확인된 구간만 시간에 포함해요.")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            if !day.hasActivity {
                Text("이 날짜에 저장된 활동 기록은 없어요.")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
        }

        section("지금까지 기록") {
            metrics(
                progress: record.progress.recordedDuration, focus: record.focusedSeconds,
                identifier: "task-record-total")
            Text("종료된 진행 구간 \(record.progress.intervals.count)개 · 집중 기록 \(record.focusSessionCount)개")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
            if record.progress.currentStartedAt != nil || record.progress.hasUnknownDuration {
                Text("종료 시각이 없거나 시간을 확인할 수 없는 진행 구간은 합계에 포함하지 않았어요.")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            Text("진행 시간은 진행 상태로 둔 시간, 집중 시간은 종료한 타이머의 기록이에요. 서로 겹칠 수 있어 더하지 않아요.")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
        }

        section("주요 시점") {
            information("첫 진행 시작", value: record.firstStartedAt.map(timestamp) ?? "기록 없음")
            information("최근 완료 처리", value: record.latestCompletedAt.map(timestamp) ?? "처리 시각 기록 없음")
            if let key = record.plannedDayKey { information("현재 계획일", value: dayText(key)) }
            if let key = record.recordedCompletionDayKey {
                information("저장된 완료일", value: dayText(key))
            }
        }

        if !record.checklist.isEmpty {
            section("현재 체크리스트") {
                Text("\(record.checklist.totalCount)개 중 \(record.checklist.completedCount)개 완료")
                    .font(.body.weight(.medium))
                Text("선택한 날짜의 과거 상태가 아닌 현재 상태예요.")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
        }
        if let note = record.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DisclosureGroup("작업 메모") {
                Text(note).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }
            .font(.subheadline)
        }

        section("활동 이력") {
            Text("최근 순 · 저장된 시작·종료 기록")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
            if record.timeline.isEmpty {
                Text("저장된 이력이 없어요.").foregroundStyle(AppTheme.secondaryText)
            }
            ForEach(record.timeline.prefix(visibleEventCount)) { event in
                eventRow(event, currentStatus: record.currentStatus)
                    .accessibilityIdentifier("task-record-event-\(event.id)")
                if event.id != record.timeline.prefix(visibleEventCount).last?.id { Divider() }
            }
            if record.timeline.count > visibleEventCount {
                Button("이력 더 보기") { visibleEventCount += 20 }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("task-record-more-history")
            }
        }
    }

    private func metrics(progress: TimeInterval, focus: Int, identifier: String) -> some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: columns),
            alignment: .leading, spacing: 16
        ) {
            metric("진행 시간", seconds: progress, id: "\(identifier)-progress")
            metric("집중 시간", seconds: TimeInterval(focus), id: "\(identifier)-focus")
        }
    }

    private func metric(_ title: String, seconds: TimeInterval, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
            Text(seconds > 0 ? TaskProgressEventRules.durationText(for: seconds) : "기록 없음")
                .font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(AppTheme.border, lineWidth: 1) }
    }

    private func information(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text(value).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func eventRow(_ event: TaskRecordEvent, currentStatus: String?) -> some View {
        let title: String
        let symbol: String
        switch event.kind {
        case .created: (title, symbol) = ("작업 생성", "plus.circle")
        case .progress: (title, symbol) = ("진행 상태 · \(duration(event))", "play.circle")
        case .focus: (title, symbol) = ("집중 · \(duration(event))", "timer")
        case .completed: (title, symbol) = ("완료 처리", "checkmark.circle")
        case .legacyCompletion: (title, symbol) = ("이전 완료 기록 · 시각 정보 없음", "clock.badge.questionmark")
        case .openProgress:
            (title, symbol) = (
                currentStatus == TaskStatus.doing.rawValue ? "진행 중인 구간" : "진행 시작 · 종료 기록 없음", "play.circle"
            )
        case .unknownProgress: (title, symbol) = ("진행 시작 · 소요 시간 확인 불가", "clock.badge.questionmark")
        }
        return VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
            if let start = event.startedAt, let end = event.endedAt {
                Text("\(timestamp(start)) → \(timestamp(end))")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            } else {
                Text(event.startedAt.map(timestamp) ?? dayText(event.dayKey))
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
            if let outcome = event.focusOutcome {
                Text(focusOutcomeText(outcome)).font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func focusOutcomeText(_ outcome: FocusSessionOutcome) -> String {
        switch outcome {
        case .completed: "목표 시간 완료"
        case .stopped: "집중 종료"
        case .taskCompleted: "작업 완료로 종료"
        case .interrupted: "집중 중단"
        }
    }

    private func duration(_ event: TaskRecordEvent) -> String {
        TaskProgressEventRules.durationText(for: event.duration ?? 0)
    }

    private func timestamp(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: "ko_KR")))
    }
    private func dayText(_ key: String) -> String {
        DayKey.date(from: key)?.formatted(.dateTime.year().month().day().locale(Locale(identifier: "ko_KR")))
            ?? key
    }

    @MainActor
    private func load() async {
        errorMessage = nil
        do {
            #if DEBUG
            if TaskRecordUITestFixture.consumeLoadFailure() {
                throw CocoaError(.fileReadUnknown)
            }
            #endif
            let result = try await TaskRecordQueryService.load(selection: selection, in: modelContext)
            try Swift.Task.checkCancellation()
            record = result
        } catch is CancellationError {
            // SwiftUI cancels an obsolete load when the sheet closes or a newer refresh starts.
        } catch {
            guard !Swift.Task.isCancelled else { return }
            errorMessage = "잠시 후 다시 시도해 주세요."
        }
    }
}

#if DEBUG
@MainActor
private enum TaskRecordUITestFixture {
    private static var didFailLoad = false

    static func consumeLoadFailure() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing"),
              arguments.contains("--ui-testing-task-record-load-failure-once"),
              !didFailLoad
        else { return false }
        didFailLoad = true
        return true
    }
}
#endif
#endif
