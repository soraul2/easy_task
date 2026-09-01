import PlanBaseCore
import SwiftUI

struct DesktopCalendarHeader: View {
    @Binding var visibleMonth: Date
    @Binding var selectedDate: Date
    let isPlacementMode: Bool
    let onMoveMonth: (Int) -> Void
    let onToggleTemplatePlacement: () -> Void
    let onOpenDayDetails: () -> Void
    let onAddEvent: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            regularHeader
            compactHeader
        }
    }

    private var regularHeader: some View {
        HStack(spacing: 12) {
            monthNavigation

            monthTitle(fontSize: 28, scaleFactor: 0.75)
                .padding(.leading, 6)

            Spacer()

            dayDetailsButton(compact: false)
            templatePlacementButton(compact: false)
            addEventButton(compact: false)
        }
    }

    private var compactHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                monthNavigation
                monthTitle(fontSize: 24, scaleFactor: 0.65)
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Spacer()
                dayDetailsButton(compact: true)
                templatePlacementButton(compact: true)
                addEventButton(compact: true)
            }
        }
    }

    private func monthTitle(fontSize: CGFloat, scaleFactor: CGFloat) -> some View {
        Text(DayKey.monthTitle(visibleMonth))
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(AppTheme.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(scaleFactor)
    }

    private var monthNavigation: some View {
        HStack(spacing: 8) {
            Button {
                onMoveMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)

            Button {
                visibleMonth = DayKey.startOfMonth(for: Date())
                selectedDate = DayKey.startOfDay(for: Date())
            } label: {
                Text("오늘")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.bordered)

            Button {
                onMoveMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
        }
    }

    private func templatePlacementButton(compact: Bool) -> some View {
        Button(action: onToggleTemplatePlacement) {
            if compact {
                Image(systemName: isPlacementMode ? "xmark.circle" : "square.grid.3x3")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 38, height: 34)
                    .calendarToolbarButtonBackground()
            } else {
                Label(
                    isPlacementMode ? "배치 종료" : "템플릿 배치",
                    systemImage: isPlacementMode ? "xmark.circle" : "square.grid.3x3"
                )
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .calendarToolbarButtonBackground()
            }
        }
        .buttonStyle(.plain)
        .help(isPlacementMode ? "템플릿 배치 종료" : "템플릿을 날짜에 배치")
    }

    private func dayDetailsButton(compact: Bool) -> some View {
        Button(action: onOpenDayDetails) {
            if compact {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 38, height: 34)
                    .calendarToolbarButtonBackground()
            } else {
                Label("날짜 상세", systemImage: "list.bullet.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .calendarToolbarButtonBackground()
            }
        }
        .buttonStyle(.plain)
        .disabled(isPlacementMode)
        .help("선택한 날짜 상세 열기 (⌘↩)")
        .keyboardShortcut(.return, modifiers: .command)
    }

    private func addEventButton(compact: Bool) -> some View {
        Button(action: onAddEvent) {
            if compact {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 42, height: 34)
                    .calendarToolbarButtonBackground(isPrimary: true)
            } else {
                Label("이벤트 추가", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .calendarToolbarButtonBackground(isPrimary: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(DayKey.display(selectedDate)) 이벤트 추가")
        .help("\(DayKey.display(selectedDate))에 이벤트 추가")
    }
}
