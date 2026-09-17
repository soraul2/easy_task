import Combine
import SwiftData
import SwiftUI

@MainActor
public enum FocusModeSelectionRequest {
    public nonisolated static let didRequestNotification = Notification.Name(
        "PlanBaseFocusModeSelectionRequested"
    )
    private static var pendingTaskID: UUID?

    public static func post(taskID: UUID) {
        pendingTaskID = taskID
        NotificationCenter.default.post(
            name: didRequestNotification,
            object: taskID
        )
    }

    public static func consume() -> UUID? {
        defer { pendingTaskID = nil }
        return pendingTaskID
    }
}

public struct FocusModeLauncher: View {
    private let action: () -> Void
    @State private var snapshot: FocusActiveSessionSnapshot?

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Group {
            if let snapshot {
                Button(action: action) {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        HStack(spacing: 7) {
                            Image(systemName: "timer.circle.fill")
                            Text(FocusModeFormatting.clock(
                                FocusTimerRules.remainingSeconds(
                                    for: snapshot,
                                    now: timeline.date
                                )
                            ))
                            .monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 13)
                        .frame(minHeight: 44)
                        .foregroundStyle(AppTheme.primaryText)
                        .background(AppTheme.floatingBar, in: Capsule())
                        .overlay {
                            Capsule().stroke(AppTheme.accent.opacity(0.55), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(snapshot.phase == .focus ? "진행 중인 집중 모드 열기" : "진행 중인 휴식 열기")
                .accessibilityIdentifier("focus-active-launcher")
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(
            for: FocusActiveSessionStore.didChangeNotification
        )) { _ in
            reload()
        }
    }

    private func reload() {
        snapshot = try? FocusSessionService.activeSnapshot()
    }
}

public struct FocusModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var timerColumnWidth = 320.0
    @AppStorage("planbase.focusAlwaysOnTop") private var alwaysOnTop = true

    @State private var snapshot: FocusActiveSessionSnapshot?
    @State private var candidates: [FocusTaskCandidate] = []
    @State private var selectedTaskID: UUID?
    @State private var focusMinutes = FocusTimerRules.defaultFocusSeconds / 60
    @State private var breakMinutes = FocusTimerRules.defaultBreakSeconds / 60
    @State private var completion: FocusCompletionPresentation?
    @State private var todaySummary = FocusDaySummary()
    @State private var errorMessage: String?
    @State private var visibleFocusSessionID: UUID?
    @State private var durationTaskID: UUID?
    @State private var showingTaskPicker = false
    @State private var taskSearch = ""
    @State private var pendingEnd: FocusActiveSessionSnapshot?
    @State private var pendingTaskCompletion: FocusActiveSessionSnapshot?
    @State private var pendingReminderAt: Date?

    private let onExplicitStart: () -> Void

    public init(initialTaskID: UUID? = nil, onExplicitStart: @escaping () -> Void = {}) {
        _selectedTaskID = State(initialValue: initialTaskID)
        self.onExplicitStart = onExplicitStart
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                GeometryReader { geometry in
                    let usesColumns = !dynamicTypeSize.isAccessibilitySize
                        && geometry.size.width >= timerColumnWidth * 2 + 40
                    ScrollView {
                        Group {
                            if let snapshot {
                                timerView(snapshot, usesColumns: usesColumns)
                            } else if let completion {
                                completionView(completion)
                            } else {
                                setupView
                            }
                        }
                        .frame(maxWidth: snapshot != nil && usesColumns ? 920 : 540)
                        .padding(20)
                        .frame(maxWidth: .infinity)
                    }
                    .id(screenIdentity)
                    .accessibilityIdentifier("focus-content-scroll")
                }
            }
            .foregroundStyle(AppTheme.primaryText)
            .navigationTitle("집중 모드")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기", action: close)
                        .accessibilityIdentifier("focus-close")
                }
                #if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $alwaysOnTop) {
                        Image(systemName: alwaysOnTop ? "pin.fill" : "pin")
                    }
                    .toggleStyle(.button)
                    .help("항상 위에 표시")
                    .accessibilityLabel("항상 위에 표시")
                }
                #endif
            }
        }
        .preferredColorScheme(AppTheme.current.preferredColorScheme)
        .frame(minWidth: pickerMinimumWidth)
        .tint(AppTheme.accent)
        .sheet(isPresented: $showingTaskPicker) {
            taskPicker.environment(\.dynamicTypeSize, dynamicTypeSize)
        }
        .task {
            load()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: FocusActiveSessionStore.didChangeNotification
        )) { _ in
            reloadSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: PersistenceCommandService.dataChangedNotification
        )) { notification in
            guard PersistenceCommandService.affects(.tasks, in: notification) else { return }
            reconcile()
            loadCandidates()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: FocusModeSelectionRequest.didRequestNotification
        )) { notification in
            guard let taskID = notification.object as? UUID else { return }
            _ = FocusModeSelectionRequest.consume()
            completion = nil
            selectedTaskID = taskID
            loadCandidates()
        }
        .onChange(of: snapshot?.sessionID) {
            updatePresentationVisibility()
        }
        .onChange(of: completion?.sessionID) {
            updatePresentationVisibility()
        }
        .onDisappear(perform: clearPresentationVisibility)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reconcile(); loadCandidates() }
        }
        .alert("집중을 마칠까요?", isPresented: Binding(
            get: { pendingEnd != nil }, set: { if !$0 { pendingEnd = nil } }
        ), presenting: pendingEnd) { active in
            Button("계속 집중", role: .cancel) {}
            Button("집중 마치기") { end(active) }
        } message: { _ in
            Text("지금까지 집중한 시간을 기록합니다. 작업은 진행 중으로 남아요.")
        }
        .alert("작업도 완료할까요?", isPresented: Binding(
            get: { pendingTaskCompletion != nil }, set: { if !$0 { pendingTaskCompletion = nil } }
        ), presenting: pendingTaskCompletion) { active in
            Button("취소", role: .cancel) {}
            Button("작업 완료") { completeTask(active) }
        } message: { _ in
            if let pendingReminderAt {
                Text("집중을 마치고 작업을 완료합니다. \(pendingReminderAt.formatted(date: .abbreviated, time: .shortened)) 알림이 중지되며 알림 설정 기록은 유지됩니다.")
            } else {
                Text("지금까지 집중한 시간을 기록하고 작업을 완료 상태로 바꿉니다.")
            }
        }
        .alert("집중 모드를 실행할 수 없습니다", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "알 수 없는 오류")
        }
    }

    private var selectedTask: FocusTaskCandidate? {
        candidates.first { $0.id == selectedTaskID }
    }

    private var screenIdentity: String {
        if let snapshot { return snapshot.phase == .focus ? "focus" : "break" }
        return completion == nil ? "setup" : "completion"
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Label("한 가지에 집중할 시간", systemImage: "scope")
                    .font(.title2.bold())
                Text("작업과 시간을 확인하고 시작하세요.")
                    .foregroundStyle(AppTheme.secondaryText)
            }

            if let selectedTask {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("집중할 작업").font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                        Button("변경") { showingTaskPicker = true }
                            .buttonStyle(PlanBaseButtonStyle(.secondary))
                            .accessibilityIdentifier("focus-change-task")
                    }
                    Text(selectedTask.title).font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("focus-selected-task")
                    Text(taskSubtitle(selectedTask))
                        .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(AppTheme.border, lineWidth: 1) }
            } else {
                ContentUnavailableView("집중할 작업이 없어요", systemImage: "checkmark.circle",
                    description: Text("보드에서 할 일을 만든 뒤 다시 열어 주세요."))
                if !candidates.isEmpty {
                    Button("다른 작업 선택") { showingTaskPicker = true }
                        .buttonStyle(PlanBaseButtonStyle(.secondary))
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("이번 집중 시간").font(.headline)
                if dynamicTypeSize.isAccessibilitySize {
                    durationControls(vertical: true)
                } else {
                    ViewThatFits(in: .horizontal) {
                        durationControls(vertical: false).fixedSize(horizontal: true, vertical: false)
                        durationControls(vertical: true)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    presetButtons(vertical: false)
                    presetButtons(vertical: true)
                }
                if let estimate = selectedTask?.estimatedMinutes, estimate > 0 {
                    let suggested = FocusTimerRules.suggestedFocusMinutes(estimatedMinutes: estimate)
                    Button {
                        focusMinutes = suggested
                    } label: {
                        Label(focusMinutes == suggested ? "작업 예상 시간 반영" : "예상 시간으로 맞추기",
                              systemImage: focusMinutes == suggested ? "checkmark.circle.fill" : "arrow.uturn.backward")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PlanBaseButtonStyle(.secondary))
                    .accessibilityIdentifier("focus-use-estimate")
                    Text(estimate == suggested
                         ? "예상 \(estimate)분을 기본으로 설정했어요. 이번 집중 시간은 자유롭게 바꿀 수 있어요."
                         : "작업 예상은 \(estimate)분이에요. 한 번의 집중은 5~120분 범위에서 설정해요.")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("focus-estimate-explanation")
                } else {
                    Text("예상 시간이 없는 작업은 25분으로 시작해요.")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
            }

            VStack(spacing: 10) {
                Button(action: beginFocus) {
                    Label("\(focusMinutes)분 집중 시작", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(PlanBaseButtonStyle())
                .disabled(selectedTaskID == nil)
                .accessibilityIdentifier("focus-start")
                Text("시작하면 작업이 진행 중으로 바뀌어요. 휴식은 자동으로 시작하지 않아요.")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            if todaySummary.focusedDurationSeconds > 0 {
                Label("오늘 \(FocusModeFormatting.minutes(todaySummary.focusedDurationSeconds)) 집중했어요",
                      systemImage: "clock.badge.checkmark")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private func durationControls(vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            FocusDurationControl(title: "집중", identifier: "focus-duration", minutes: $focusMinutes,
                range: (FocusTimerRules.minimumFocusSeconds / 60)...(FocusTimerRules.maximumFocusSeconds / 60))
            FocusDurationControl(title: "휴식", identifier: "focus-break-duration", minutes: $breakMinutes,
                range: (FocusTimerRules.minimumBreakSeconds / 60)...(FocusTimerRules.maximumBreakSeconds / 60))
        }
    }

    private func presetButtons(vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            ForEach([15, 25, 50], id: \.self) { minutes in
                Button { focusMinutes = minutes } label: {
                    Text("\(minutes)분").frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(PlanBaseButtonStyle(focusMinutes == minutes ? .primary : .secondary))
                .accessibilityAddTraits(focusMinutes == minutes ? .isSelected : [])
                .accessibilityIdentifier("focus-preset-\(minutes)")
            }
        }
    }

    private var taskPicker: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.secondaryText)
                    TextField("작업 제목 검색", text: $taskSearch)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("작업 제목 검색")
                        .accessibilityIdentifier("focus-task-search")
                    if !taskSearch.isEmpty {
                        Button { taskSearch = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.secondaryText)
                        .accessibilityLabel("검색어 지우기")
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, taskSearch.isEmpty ? 14 : 0)
                .frame(minHeight: 48)
                .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.top, 12)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        if filteredCandidates.isEmpty {
                            ContentUnavailableView("일치하는 작업이 없어요", systemImage: "magnifyingglass",
                                                   description: Text("다른 제목으로 검색해 보세요."))
                        }
                        ForEach(filteredCandidates) { candidate in
                            Button {
                                selectedTaskID = candidate.id
                                applySuggestedDurationIfNeeded()
                                showingTaskPicker = false
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(candidate.title).font(.headline)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(taskSubtitle(candidate)).font(.caption)
                                            .foregroundStyle(AppTheme.secondaryText)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: selectedTaskID == candidate.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(AppTheme.accent)
                                }
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedTaskID == candidate.id ? .isSelected : [])
                        }
                    }.padding(20)
                }
            }
            .background(AppTheme.background)
            .foregroundStyle(AppTheme.primaryText)
            .navigationTitle("집중할 작업")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { showingTaskPicker = false }
                }
            }
        }
        .preferredColorScheme(AppTheme.current.preferredColorScheme)
        .frame(minWidth: pickerMinimumWidth, minHeight: 420)
    }

    private var filteredCandidates: [FocusTaskCandidate] {
        let query = taskSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidates.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
    }

    private var pickerMinimumWidth: CGFloat? {
        #if os(macOS)
        400
        #else
        nil
        #endif
    }

    private func taskSubtitle(_ task: FocusTaskCandidate) -> String {
        let status = task.status == .doing ? "진행 중" : "할 일"
        let date = DayKey.date(from: task.dayKey).map {
            $0.formatted(.dateTime.month().day().locale(Locale(identifier: "ko_KR")))
        } ?? task.dayKey
        let estimate = task.estimatedMinutes.flatMap { $0 > 0 ? " · 예상 \($0)분" : nil } ?? ""
        return "\(status) · \(date)\(estimate)"
    }

    private func timerView(_ active: FocusActiveSessionSnapshot, usesColumns: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = FocusTimerRules.remainingSeconds(for: active, now: timeline.date)
            let planned = active.phase == .focus ? active.plannedFocusSeconds : active.plannedBreakSeconds
            let layout = usesColumns
                ? AnyLayout(HStackLayout(alignment: .center, spacing: 28))
                : AnyLayout(VStackLayout(spacing: 22))
            layout {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Label(active.phase == .focus ? "집중하는 시간" : "쉬어가는 시간",
                              systemImage: active.phase == .focus ? "scope" : "cup.and.saucer")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
                        Text(active.taskTitleSnapshot).font(.title2.bold())
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Text("이번 \(active.phase == .focus ? "집중" : "휴식") \(planned / 60)분")
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    }
                    FocusTimerDial(seconds: remaining,
                        progress: planned > 0 ? 1 - remaining / Double(planned) : 0,
                        paused: active.runState == .paused, isBreak: active.phase == .breakTime)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 18) {
                    if active.runState == .running, let deadline = active.deadline {
                        Text("\(deadline.formatted(.dateTime.hour().minute().locale(Locale(identifier: "ko_KR")))) 종료 예정")
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    } else {
                        Text("멈춘 시간은 집중 기록에 포함되지 않아요.")
                            .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    timerActions(active)
                    if active.phase == .focus {
                        Button { requestTaskCompletion(active) } label: {
                            Label("작업도 완료하기", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity, minHeight: 28)
                        }
                        .buttonStyle(PlanBaseButtonStyle(.secondary))
                        .accessibilityIdentifier("focus-complete-task")
                    }
                    Text("화면을 닫아도 타이머는 계속돼요.")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .onChange(of: remaining) { _, value in if value <= 0 { reconcile() } }
        }
    }

    private func timerActions(_ active: FocusActiveSessionSnapshot) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Button { togglePause(active) } label: {
                Label(active.runState == .paused ? (active.phase == .focus ? "다시 집중" : "휴식 계속") : "일시정지",
                      systemImage: active.runState == .paused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(PlanBaseButtonStyle())
            .accessibilityIdentifier("focus-pause-resume")
            Button {
                if active.phase == .focus { pendingEnd = active } else { end(active) }
            } label: {
                Label(active.phase == .focus ? "집중 마치기" : "휴식 건너뛰기", systemImage: "stop")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(PlanBaseButtonStyle(.secondary))
            .accessibilityIdentifier("focus-stop")
        }
    }

    private func completionView(_ completed: FocusCompletionPresentation) -> some View {
        VStack(spacing: 22) {
            Image(systemName: completed.kind == .focus ? "checkmark.circle" : "cup.and.saucer")
                .font(.system(size: 46, weight: .medium)).foregroundStyle(AppTheme.accent)
                .padding(22).background(AppTheme.panel, in: Circle())
            VStack(spacing: 10) {
                Text(completionTitle(completed)).font(.title.bold())
                    .accessibilityIdentifier("focus-completion-title")
                Text(completed.title).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(completionSubtitle(completed)).font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .multilineTextAlignment(.center)
            if completed.kind == .focus {
                Text(completionDetail(completed))
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                Button { beginBreak(completed) } label: {
                    Label("\(completed.breakMinutes)분 휴식 시작", systemImage: "cup.and.saucer.fill")
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(PlanBaseButtonStyle())
                .accessibilityIdentifier("focus-start-break")
            }
            if candidates.contains(where: { $0.id == completed.taskID }) {
                Button { beginAgain(completed) } label: {
                    Label(completed.kind == .focus ? "\(completed.focusMinutes)분 더 집중" : "\(completed.focusMinutes)분 집중 시작",
                          systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(PlanBaseButtonStyle(completed.kind == .breakTime ? .primary : .secondary))
                .accessibilityIdentifier("focus-start-again")
            }
            if completed.kind == .breakTime {
                Button { extendBreak(completed) } label: {
                    Label("5분 더 쉬기", systemImage: "plus.circle").frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(PlanBaseButtonStyle(.secondary))
            }
            Button { selectAnotherTask() } label: {
                Text("다른 작업 선택").frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(PlanBaseButtonStyle(.secondary))
            .accessibilityIdentifier("focus-another-task")
        }
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private func load() {
        if let requestedTaskID = FocusModeSelectionRequest.consume() {
            selectedTaskID = requestedTaskID
        }
        reconcile()
        restoreNotificationCompletionIfNeeded()
        loadCandidates()
    }

    @MainActor
    private func loadCandidates() {
        do {
            candidates = try FocusTaskQueryService.candidates(
                selectedTaskID: selectedTaskID ?? snapshot?.taskID ?? completion?.taskID,
                in: modelContext
            )
            if selectedTaskID == nil { selectedTaskID = candidates.first?.id }
            if !candidates.contains(where: { $0.id == selectedTaskID }) {
                selectedTaskID = nil
            }
            applySuggestedDurationIfNeeded()
            todaySummary = try FocusSessionQueryService.summary(in: modelContext)
        } catch {
            present(error)
        }
    }

    private func applySuggestedDurationIfNeeded() {
        guard snapshot == nil, completion == nil,
              let selectedTask, durationTaskID != selectedTask.id else { return }
        focusMinutes = FocusTimerRules.suggestedFocusMinutes(estimatedMinutes: selectedTask.estimatedMinutes)
        durationTaskID = selectedTask.id
    }

    @MainActor
    private func beginFocus() {
        guard let selectedTaskID else { return }
        do {
            completion = nil
            snapshot = try FocusSessionService.beginFocus(
                taskID: selectedTaskID,
                focusSeconds: focusMinutes * 60,
                breakSeconds: breakMinutes * 60,
                in: modelContext
            )
            onExplicitStart()
        } catch {
            present(error)
        }
    }

    private func togglePause(_ active: FocusActiveSessionSnapshot) {
        do {
            snapshot = if active.runState == .paused {
                try FocusSessionService.resume(
                    expectedSessionID: active.sessionID,
                    expectedRevision: active.revision
                )
            } else {
                try FocusSessionService.pause(
                    expectedSessionID: active.sessionID,
                    expectedRevision: active.revision
                )
            }
            if active.runState == .paused { onExplicitStart() }
        } catch {
            present(error)
            reloadSnapshot()
        }
    }

    @MainActor
    private func end(_ active: FocusActiveSessionSnapshot) {
        do {
            guard let current = try FocusSessionService.activeSnapshot(),
                  current.sessionID == active.sessionID, current.revision == active.revision else {
                reloadSnapshot()
                return
            }
            if active.phase == .breakTime {
                try FocusSessionService.endBreak(
                    expectedSessionID: active.sessionID,
                    expectedRevision: active.revision
                )
                snapshot = nil
                completion = FocusCompletionPresentation(
                    sessionID: active.sessionID, kind: .breakTime, taskID: active.taskID,
                    title: active.taskTitleSnapshot, focusedSeconds: 0,
                    focusMinutes: active.plannedFocusSeconds / 60,
                    breakMinutes: active.plannedBreakSeconds / 60, outcome: .stopped
                )
                return
            }
            let record = try FocusSessionService.endFocus(
                outcome: .stopped,
                expectedSessionID: active.sessionID,
                expectedRevision: active.revision,
                in: modelContext
            )
            showCompletion(record, snapshot: active)
        } catch {
            present(error)
            reloadSnapshot()
        }
    }

    @MainActor
    private func requestTaskCompletion(_ active: FocusActiveSessionSnapshot) {
        do {
            guard let task = BoundedQueryService.representativeTask(from: try modelContext.fetch(
                BoundedQueryService.taskCandidatesDescriptor(id: active.taskID)
            )) else { reconcile(); return }
            pendingReminderAt = TaskReminderRules.upcomingReminderDate(for: task)
            pendingTaskCompletion = active
        } catch { present(error) }
    }

    @MainActor
    private func completeTask(_ active: FocusActiveSessionSnapshot) {
        do {
            guard let current = try FocusSessionService.activeSnapshot(),
                  current.sessionID == active.sessionID, current.taskID == active.taskID,
                  current.phase == .focus else { reconcile(); return }
            guard let task = try BoundedQueryService.representativeTask(
                from: modelContext.fetch(
                    BoundedQueryService.taskCandidatesDescriptor(id: active.taskID)
                )
            ) else {
                reconcile()
                return
            }
            try PersistenceCommandService.perform(in: modelContext) {
                _ = try TaskLifecycleService.applyStatus(
                    .done,
                    to: task,
                    in: modelContext
                )
            }
            reconcile()
        } catch {
            present(error)
            reloadSnapshot()
        }
    }

    @MainActor
    private func reconcile() {
        do {
            let source = snapshot ?? (try? FocusSessionService.activeSnapshot())
            switch try FocusSessionService.reconcile(in: modelContext) {
            case .unchanged(let value):
                snapshot = value
            case .focusEnded(let record):
                snapshot = nil
                completion = FocusCompletionPresentation(
                    sessionID: record.id,
                    kind: .focus,
                    taskID: record.taskId,
                    title: source?.taskTitleSnapshot ?? "집중 작업",
                    focusedSeconds: record.focusedDurationSeconds,
                    focusMinutes: record.plannedDurationSeconds / 60,
                    breakMinutes: source.map { $0.plannedBreakSeconds / 60 }
                        ?? FocusTimerRules.defaultBreakSeconds / 60,
                    outcome: FocusSessionOutcome(rawValue: record.outcomeRawValue) ?? .interrupted
                )
            case .breakEnded:
                snapshot = nil
                if let source {
                    completion = FocusCompletionPresentation(
                        sessionID: source.sessionID,
                        kind: .breakTime,
                        taskID: source.taskID,
                        title: source.taskTitleSnapshot,
                        focusedSeconds: 0,
                        focusMinutes: source.plannedFocusSeconds / 60,
                        breakMinutes: source.plannedBreakSeconds / 60,
                        outcome: .completed
                    )
                }
            case .noActiveSession:
                snapshot = nil
            }
        } catch {
            present(error)
            reloadSnapshot()
        }
    }

    private func reloadSnapshot() {
        do {
            snapshot = try FocusSessionService.activeSnapshot()
            if snapshot == nil {
                restoreNotificationCompletionIfNeeded()
            }
        } catch {
            present(error)
        }
    }

    private func showCompletion(
        _ record: FocusSession?,
        snapshot source: FocusActiveSessionSnapshot
    ) {
        snapshot = nil
        completion = FocusCompletionPresentation(
            sessionID: source.sessionID,
            kind: .focus,
            taskID: source.taskID,
            title: source.taskTitleSnapshot,
            focusedSeconds: record?.focusedDurationSeconds ?? 0,
            focusMinutes: source.plannedFocusSeconds / 60,
            breakMinutes: source.plannedBreakSeconds / 60,
            outcome: record.flatMap { FocusSessionOutcome(rawValue: $0.outcomeRawValue) }
                ?? .stopped
        )
    }

    private func beginBreak(_ completed: FocusCompletionPresentation) {
        do {
            snapshot = try FocusSessionService.beginBreak(
                taskID: completed.taskID,
                taskTitle: completed.title,
                focusSeconds: completed.focusMinutes * 60,
                breakSeconds: completed.breakMinutes * 60
            )
            completion = nil
            try? FocusNotificationActionTokenStore.clear()
            onExplicitStart()
        } catch {
            present(error)
        }
    }

    private func beginAgain(_ completed: FocusCompletionPresentation) {
        do {
            snapshot = try FocusSessionService.beginFocus(
                taskID: completed.taskID,
                focusSeconds: completed.focusMinutes * 60,
                breakSeconds: completed.breakMinutes * 60,
                in: modelContext
            )
            completion = nil
            try? FocusNotificationActionTokenStore.clear()
            onExplicitStart()
        } catch {
            present(error)
        }
    }

    private func extendBreak(_ completed: FocusCompletionPresentation) {
        do {
            snapshot = try FocusSessionService.beginBreak(
                taskID: completed.taskID,
                taskTitle: completed.title,
                focusSeconds: completed.focusMinutes * 60,
                breakSeconds: FocusNotificationRules.extensionBreakSeconds
            )
            completion = nil
            try? FocusNotificationActionTokenStore.clear()
            onExplicitStart()
        } catch {
            present(error)
        }
    }

    @MainActor
    private func restoreNotificationCompletionIfNeeded(now: Date = Date()) {
        guard snapshot == nil, completion == nil else { return }
        do {
            guard let token = try FocusNotificationActionTokenStore.read() else { return }
            guard FocusNotificationRules.isActionable(token, now: now) else {
                if now > token.expiresAt {
                    try? FocusNotificationActionTokenStore.clear()
                }
                return
            }
            guard try FocusSessionService.activeSnapshot() == nil else { return }

            let focusedSeconds: Int
            let outcome: FocusSessionOutcome
            if token.phase == .focus {
                let id = token.sessionID
                let instanceID = token.instanceID
                let records = try modelContext.fetch(FetchDescriptor<FocusSession>(
                    predicate: #Predicate<FocusSession> { session in
                        session.id == id &&
                            session.instanceID == instanceID &&
                            session.supersededAt == nil
                    }
                ))
                guard let record = records.first(where: {
                    $0.taskId == token.taskID &&
                        $0.endedAt == token.deadline &&
                        $0.outcomeRawValue == FocusSessionOutcome.completed.rawValue
                }) else { return }
                focusedSeconds = record.focusedDurationSeconds
                outcome = .completed
            } else {
                focusedSeconds = 0
                outcome = .completed
            }

            completion = FocusCompletionPresentation(
                sessionID: token.sessionID,
                kind: token.phase == .focus ? .focus : .breakTime,
                taskID: token.taskID,
                title: token.taskTitleSnapshot,
                focusedSeconds: focusedSeconds,
                focusMinutes: token.plannedFocusSeconds / 60,
                breakMinutes: token.plannedBreakSeconds / 60,
                outcome: outcome
            )
        } catch {
            present(error)
        }
    }

    private func completionTitle(_ completed: FocusCompletionPresentation) -> String {
        if completed.kind == .breakTime {
            return completed.outcome == .stopped ? "다시 시작할 준비" : "휴식 완료"
        }
        if completed.outcome == .taskCompleted { return "작업까지 완료했어요" }
        return completed.outcome == .completed ? "집중을 채웠어요" : "집중을 마쳤어요"
    }

    private func completionSubtitle(_ completed: FocusCompletionPresentation) -> String {
        if completed.kind == .breakTime { return "다시 집중할 준비가 됐나요?" }
        return completed.focusedSeconds > 0
            ? "\(FocusModeFormatting.minutes(completed.focusedSeconds)) 집중했어요"
            : "기록할 집중 시간이 없어요"
    }

    private func completionDetail(_ completed: FocusCompletionPresentation) -> String {
        if completed.outcome == .taskCompleted {
            return completed.focusedSeconds > 0 ? "작업을 완료하고 집중 기록도 남겼어요." : "작업을 완료했어요."
        }
        if completed.outcome == .interrupted {
            return "작업 상태가 바뀌어 집중을 마쳤어요. 현재 상태는 보드에서 확인할 수 있어요."
        }
        return completed.focusedSeconds > 0
            ? "집중한 시간은 기록에 남고, 작업은 진행 중으로 유지돼요."
            : "타이머만 종료했어요. 작업은 진행 중으로 유지돼요."
    }

    private func selectAnotherTask() {
        try? FocusNotificationActionTokenStore.clear()
        completion = nil
        durationTaskID = nil
        loadCandidates()
        showingTaskPicker = !candidates.isEmpty
    }

    private func close() {
        if completion != nil {
            try? FocusNotificationActionTokenStore.clear()
        }
        clearPresentationVisibility()
        dismiss()
    }

    private func updatePresentationVisibility() {
        let nextSessionID = snapshot?.sessionID ?? completion?.sessionID
        guard visibleFocusSessionID != nextSessionID else { return }
        if let visibleFocusSessionID {
            FocusPresentationVisibilityStore.shared.hide(sessionID: visibleFocusSessionID)
        }
        visibleFocusSessionID = nextSessionID
        if let nextSessionID {
            FocusPresentationVisibilityStore.shared.show(sessionID: nextSessionID)
        }
    }

    private func clearPresentationVisibility() {
        if let visibleFocusSessionID {
            FocusPresentationVisibilityStore.shared.hide(sessionID: visibleFocusSessionID)
        }
        visibleFocusSessionID = nil
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

private struct FocusCompletionPresentation {
    let sessionID: UUID
    let kind: FocusCompletionKind
    let taskID: UUID
    let title: String
    let focusedSeconds: Int
    let focusMinutes: Int
    let breakMinutes: Int
    let outcome: FocusSessionOutcome
}

private enum FocusCompletionKind {
    case focus
    case breakTime
}

private enum FocusModeFormatting {
    static func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    static func minutes(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)초" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)분" : "\(minutes)분 \(remainder)초"
    }
}
