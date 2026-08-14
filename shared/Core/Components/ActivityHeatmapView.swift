import SwiftUI

public struct ActivityHeatmapPalette {
    public var empty: Color
    public var level1: Color
    public var level2: Color
    public var level3: Color
    public var level4: Color
    public var streakStroke: Color
    public var todayStroke: Color
    public var selectionStroke: Color
    public var future: Color

    public init(
        empty: Color,
        level1: Color,
        level2: Color,
        level3: Color,
        level4: Color,
        streakStroke: Color,
        todayStroke: Color,
        selectionStroke: Color,
        future: Color
    ) {
        self.empty = empty
        self.level1 = level1
        self.level2 = level2
        self.level3 = level3
        self.level4 = level4
        self.streakStroke = streakStroke
        self.todayStroke = todayStroke
        self.selectionStroke = selectionStroke
        self.future = future
    }

    public func fill(for day: ActivityDaySummary) -> Color {
        guard !day.isFuture else { return future }
        return switch day.intensity {
        case .none: empty
        case .low: level1
        case .medium: level2
        case .high: level3
        case .veryHigh: level4
        }
    }
}

public struct ActivityHeatmapLayout: Equatable, Sendable {
    public var size: CGSize
    public var weekCount: Int
    public var spacing: CGFloat
    public var cellSide: CGFloat
    public var origin: CGPoint

    public init(
        size: CGSize,
        weekCount: Int,
        spacing: CGFloat = 2
    ) {
        self.size = size
        self.weekCount = max(1, weekCount)
        self.spacing = max(0, spacing)
        let horizontal = (
            size.width - CGFloat(max(0, self.weekCount - 1)) * self.spacing
        ) / CGFloat(self.weekCount)
        let vertical = (size.height - 6 * self.spacing) / 7
        cellSide = max(0, min(horizontal, vertical))
        let gridWidth = CGFloat(self.weekCount) * cellSide +
            CGFloat(max(0, self.weekCount - 1)) * self.spacing
        let gridHeight = 7 * cellSide + 6 * self.spacing
        origin = CGPoint(
            x: max(0, (size.width - gridWidth) / 2),
            y: max(0, (size.height - gridHeight) / 2)
        )
    }

    public func rect(week: Int, weekday: Int) -> CGRect {
        CGRect(
            x: origin.x + CGFloat(week) * (cellSide + spacing),
            y: origin.y + CGFloat(weekday) * (cellSide + spacing),
            width: cellSide,
            height: cellSide
        )
    }

    public func dayIndex(at location: CGPoint) -> Int? {
        guard cellSide > 0,
              location.x >= origin.x,
              location.y >= origin.y else {
            return nil
        }
        let stride = cellSide + spacing
        let week = Int((location.x - origin.x) / stride)
        let weekday = Int((location.y - origin.y) / stride)
        guard (0..<weekCount).contains(week),
              (0..<7).contains(weekday),
              rect(week: week, weekday: weekday).contains(location) else {
            return nil
        }
        return week * 7 + weekday
    }
}

public struct ActivityHeatmapView: View {
    private let overview: ActivityOverview
    private let palette: ActivityHeatmapPalette
    private let selectedDayKey: String?
    private let onSelectDay: (String?) -> Void
    @State private var hoveredDayKey: String?

    public init(
        overview: ActivityOverview,
        palette: ActivityHeatmapPalette,
        selectedDayKey: String?,
        onSelectDay: @escaping (String?) -> Void
    ) {
        self.overview = overview
        self.palette = palette
        self.selectedDayKey = selectedDayKey
        self.onSelectDay = onSelectDay
    }

    public var body: some View {
        GeometryReader { proxy in
            let days = overview.days
            let layout = ActivityHeatmapLayout(
                size: proxy.size,
                weekCount: max(overview.weeks.count, 1)
            )
            Canvas { context, _ in
                for (index, day) in days.enumerated() {
                    let rect = layout.rect(week: index / 7, weekday: index % 7)
                    let cornerRadius = min(2.5, layout.cellSide * 0.22)
                    let path = Path(roundedRect: rect, cornerRadius: cornerRadius)
                    context.fill(path, with: .color(palette.fill(for: day)))

                    if selectedDayKey == day.dayKey {
                        context.stroke(
                            path,
                            with: .color(palette.selectionStroke),
                            lineWidth: min(2.5, max(1, layout.cellSide * 0.18))
                        )
                    } else if day.dayKey == overview.range?.todayDayKey {
                        context.stroke(
                            path,
                            with: .color(palette.todayStroke),
                            style: StrokeStyle(
                                lineWidth: min(2, max(1, layout.cellSide * 0.15)),
                                dash: [max(1, layout.cellSide * 0.25)]
                            )
                        )
                    } else if hoveredDayKey == day.dayKey {
                        context.stroke(
                            path,
                            with: .color(palette.selectionStroke.opacity(0.55)),
                            lineWidth: min(2, max(1, layout.cellSide * 0.14))
                        )
                    } else if day.isInCurrentStreak {
                        context.stroke(
                            path,
                            with: .color(palette.streakStroke),
                            lineWidth: min(2, max(1, layout.cellSide * 0.12))
                        )
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    guard let index = layout.dayIndex(at: value.location),
                          days.indices.contains(index),
                          !days[index].isFuture else {
                        return
                    }
                    let dayKey = days[index].dayKey
                    onSelectDay(selectedDayKey == dayKey ? nil : dayKey)
                }
            )
#if os(macOS)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard let index = layout.dayIndex(at: location),
                          days.indices.contains(index),
                          !days[index].isFuture else {
                        hoveredDayKey = nil
                        return
                    }
                    hoveredDayKey = days[index].dayKey
                case .ended:
                    hoveredDayKey = nil
                }
            }
            .focusable()
            .onKeyPress(.leftArrow) {
                moveSelection(by: -1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                moveSelection(by: 1)
                return .handled
            }
            .onKeyPress(.return) {
                toggleKeyboardSelection()
                return .handled
            }
            .onKeyPress(.space) {
                toggleKeyboardSelection()
                return .handled
            }
            .onKeyPress(.escape) {
                onSelectDay(nil)
                return .handled
            }
            .help(hoverHelp)
#endif
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("활동 달력")
            .accessibilityValue(accessibilityValue)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    moveSelection(by: 1)
                case .decrement:
                    moveSelection(by: -1)
                @unknown default:
                    break
                }
            }
            .accessibilityAction(named: "이전 날짜") {
                moveSelection(by: -1)
            }
            .accessibilityAction(named: "다음 날짜") {
                moveSelection(by: 1)
            }
        }
        .aspectRatio(
            CGFloat(max(overview.weeks.count, 1)) / 7,
            contentMode: .fit
        )
    }
}

private extension ActivityHeatmapView {
    var accessibilityValue: String {
        guard let range = overview.range else { return "활동 기록 없음" }
        let overviewValue = "\(range.startDayKey)부터 \(range.endDayKey), " +
            "활동한 날 \(overview.activeDayCount)일, " +
            "현재 \(overview.currentStreak)일 연속"
        guard let selectedDayKey,
              let selectedDay = overview.days.first(where: {
                  $0.dayKey == selectedDayKey
              }) else {
            return overviewValue
        }
        return overviewValue + ", 선택한 날짜 \(selectedDay.dayKey), " +
            "완료 작업 \(selectedDay.completedTaskCount)개"
    }

    func moveSelection(by offset: Int) {
        let days = overview.days.filter { !$0.isFuture }
        guard !days.isEmpty else { return }
        let currentIndex = selectedDayKey.flatMap { selected in
            days.firstIndex { $0.dayKey == selected }
        } ?? max(0, days.count - 1)
        let nextIndex = min(max(0, currentIndex + offset), days.count - 1)
        onSelectDay(days[nextIndex].dayKey)
    }

#if os(macOS)
    var hoverHelp: String {
        guard let hoveredDayKey,
              let day = overview.days.first(where: {
                  $0.dayKey == hoveredDayKey
              }) else {
            return "날짜별 완료 작업 활동"
        }
        let dateText = DayKey.date(from: day.dayKey).map(DayKey.display) ?? day.dayKey
        return day.completedTaskCount == 0
            ? "\(dateText), 완료 작업 없음"
            : "\(dateText), 완료 작업 \(day.completedTaskCount)개"
    }

    func toggleKeyboardSelection() {
        let days = overview.days.filter { !$0.isFuture }
        guard !days.isEmpty else { return }
        if selectedDayKey != nil {
            onSelectDay(nil)
        } else {
            onSelectDay(days.last?.dayKey)
        }
    }
#endif
}
