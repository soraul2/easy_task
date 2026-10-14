#if os(watchOS)
import PlanBaseCore
import SwiftUI

struct WatchCompanionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = WatchCompanionController.shared
    @State private var title = ""
    @State private var pendingCompletion: WatchCompanionTask?
    @State private var path: [String] = []

    private var tasks: [WatchCompanionTask] {
        controller.state.snapshot?.dayKey == DayKey.today ? controller.state.projectedTasks : []
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("iPhone 연동 모드").font(.caption)
                            Spacer(minLength: 2)
                            Button { controller.refresh() } label: { Image(systemName: "arrow.clockwise") }
                                .buttonStyle(.plain)
                                .accessibilityLabel("목록 새로 받기")
                        }
                        if let snapshot = controller.state.snapshot {
                            Text("받은 시각 \(snapshot.generatedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2).foregroundStyle(.secondary)
                            if snapshot.dayKey != DayKey.today {
                                Text("오늘 목록이 필요해요. iPhone에서 PlanBase를 열어 주세요.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        } else {
                            Text("연결된 iPhone에서 PlanBase를 한 번 열어 주세요. 처음 목록을 받은 뒤 사용할 수 있어요.")
                                .font(.caption)
                        }
                        if !controller.state.pending.isEmpty {
                            Text("iPhone 반영 대기 \(controller.state.pending.count)건")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }

                if let issue = controller.issue {
                    Section { Text(issue).font(.caption).foregroundStyle(.orange) }
                }
                if let failure = controller.state.lastFailure {
                    Section("변경 확인 필요") {
                        Text(failure).font(.caption)
                        ForEach(controller.state.failed) { command in
                            switch command.action {
                            case let .addTask(_, title, _): Text("추가 대기였던 작업: \(title)").font(.caption)
                            case .setStatus: Text("작업 상태 변경을 다시 확인해 주세요.").font(.caption2)
                            case let .recordFocus(record):
                                Text("미반영 집중: \(record.focusedSeconds / 60)분 · \(record.endedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2)
                            }
                        }
                        Button("확인했어요") { controller.dismissFailure() }
                    }
                }

                if controller.state.activeFocus != nil || controller.state.completedFocus != nil {
                    Section("집중") {
                        NavigationLink(value: "focus") {
                            VStack(alignment: .leading) {
                                Text(controller.state.activeFocus?.taskTitleSnapshot ?? "집중 구간 종료")
                                    .lineLimit(2)
                                if let active = controller.state.activeFocus {
                                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                        Text(clock(FocusTimerRules.remainingSeconds(for: active, now: timeline.date)))
                                            .monospacedDigit().foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("빠른 추가") {
                    TextField("할 일 말하기", text: $title).onSubmit(addTask)
                    Button("오늘 할 일 추가", systemImage: "plus", action: addTask)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.state.snapshot?.dayKey != DayKey.today)
                }

                Section("할 일") {
                    ForEach(tasks.filter { $0.status != "done" }) { task in taskRow(task) }
                    if tasks.allSatisfy({ $0.status == "done" }), controller.state.snapshot != nil {
                        Text("남은 할 일이 없어요").foregroundStyle(.secondary)
                    }
                    if controller.state.snapshot?.hasMoreTasks == true {
                        Text("목록은 최대 100개까지 표시해요. 전체 작업은 iPhone에서 확인해 주세요.").font(.caption2)
                    }
                }
                if !tasks.filter({ $0.status == "done" }).isEmpty {
                    Section("완료") {
                        ForEach(tasks.filter { $0.status == "done" }.prefix(20)) { task in taskRow(task) }
                    }
                }
                if controller.state.snapshot?.dayKey == DayKey.today,
                   let events = controller.state.snapshot?.events, !events.isEmpty {
                    Section("일정") { ForEach(events) { Text($0.title).font(.caption) } }
                }
            }
            .navigationTitle("오늘")
            .navigationDestination(for: String.self) { _ in WatchCompanionFocusView(controller: controller) }
            .refreshable { controller.refresh() }
            .alert(item: $pendingCompletion) { task in
                Alert(title: Text("알림이 남아 있어요"),
                    message: Text("완료하면 iPhone에 반영된 뒤 알림이 정리됩니다."),
                    primaryButton: .default(Text("완료")) {
                        controller.setStatus(task, status: "done", confirmedReminderAt: task.reminderAt)
                    }, secondaryButton: .cancel(Text("취소")))
            }
        }
        .task {
            controller.start()
            if controller.focusPresentationID != nil { path = ["focus"] }
        }
        .onOpenURL { url in
            if PlanBaseDeepLink.focusRoute(from: url) != nil { path = ["focus"] }
        }
        .onChange(of: controller.focusPresentationID) { _, _ in path = ["focus"] }
        .onChange(of: scenePhase) { _, phase in if phase == .active { controller.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in controller.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in controller.refresh() }
    }

    private func taskRow(_ task: WatchCompanionTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title).font(.body).lineLimit(3).strikethrough(task.status == "done")
            Button(task.status == "todo" ? "시작" : task.status == "doing" ? "완료" : "다시 시작") {
                let status = task.status == "doing" ? "done" : "doing"
                if status == "done", let reminder = task.reminderAt, reminder > Date() {
                    pendingCompletion = task
                } else { controller.setStatus(task, status: status) }
            }
            .buttonStyle(.bordered)
            if task.status != "done" {
                NavigationLink("집중 타이머") { WatchCompanionFocusView(controller: controller, task: task) }
            }
        }
        .padding(.vertical, 4)
    }

    private func addTask() { if controller.addTask(title) { title = "" } }
    private func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

private struct WatchCompanionFocusView: View {
    var controller: WatchCompanionController
    var task: WatchCompanionTask?
    @State private var minutes = 25
    @State private var confirmingStop = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let active = controller.state.activeFocus {
                    Text(active.phase == .focus ? "집중" : "휴식").font(.headline)
                    Text(active.taskTitleSnapshot).font(.caption).lineLimit(2)
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        let remaining = FocusTimerRules.remainingSeconds(for: active, now: timeline.date)
                        let seconds = max(0, Int(remaining.rounded(.up)))
                        Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
                            .onChange(of: seconds) { _, value in if value == 0 { controller.reconcileTimer() } }
                    }
                    Button(active.runState == .paused ? "계속 집중" : "일시정지") { controller.pauseOrResume() }
                    Button("종료", role: .destructive) { confirmingStop = true }
                } else {
                    if let completed = controller.state.completedFocus {
                        Text(completed.phase == .focus ? "집중 구간을 마쳤어요" : "휴식을 마쳤어요").font(.headline)
                        if completed.phase == .focus {
                            Button("5분 휴식") { controller.startBreak() }
                        }
                    }
                    if let task = availableTask {
                        Text(task.title).font(.caption).lineLimit(2)
                        Picker("집중 시간", selection: $minutes) {
                            ForEach([5, 10, 15, 25, 30, 45, 60, 90, 120], id: \.self) { Text("\($0)분").tag($0) }
                        }
                        .pickerStyle(.navigationLink)
                        Button("집중 시작") { controller.startFocus(task, minutes: minutes) }
                    } else {
                        Text("오늘 목록에서 집중할 작업을 골라 주세요.").font(.caption)
                    }
                }
                if let issue = controller.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
                Text("집중 기록은 iPhone에 연결되면 반영돼요.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("집중")
        .onAppear {
            if let task { minutes = FocusTimerRules.suggestedFocusMinutes(estimatedMinutes: task.estimatedMinutes) }
            controller.reconcileTimer()
        }
        .confirmationDialog("집중을 종료할까요?", isPresented: $confirmingStop) {
            Button("종료", role: .destructive) { controller.stopFocus() }
        }
    }

    private var availableTask: WatchCompanionTask? {
        guard controller.state.snapshot?.dayKey == DayKey.today else { return nil }
        let id = task?.id ?? controller.state.completedFocus?.taskID
        return controller.state.projectedTasks.first { $0.id == id && $0.status != "done" }
    }
}
#endif
