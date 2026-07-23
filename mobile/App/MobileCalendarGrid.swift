#if os(iOS)
import PlanBaseCore
import SwiftUI

struct CalendarHeader: View {
    @Binding var visibleMonth: Date
    @Binding var selectedDate: Date
    var showsActions: Bool
    var onShowTheme: () -> Void
    var onShowTemplates: () -> Void
    var onAddEvent: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Button { moveMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 34)
            }
            .accessibilityLabel("이전 달")

            Text(DayKey.monthTitle(visibleMonth))
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Button { moveMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 34)
            }
            .accessibilityLabel("다음 달")

            Spacer(minLength: 0)

            if showsActions {
                HStack(spacing: 6) {
                    MobileThemeButton(action: onShowTheme)

                    Button {
                        onShowTemplates()
                    } label: {
                        Image(systemName: "square.grid.3x3")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 36, height: 34)
                    }
                    .accessibilityLabel("템플릿 배치")

                    Button {
                        onAddEvent()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .frame(width: 36, height: 34)
                    }
                    .accessibilityLabel("이벤트 추가")
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private func moveMonth(by offset: Int) {
        let month = DayKey.startOfMonth(for: DayKey.addingMonths(offset, to: visibleMonth))
        visibleMonth = month
        selectedDate = month
    }
}

struct CalendarWeekdayHeader: View {
    var body: some View {
        let symbols = DayKey.weekdaySymbols()

        HStack(spacing: 0) {
            ForEach(symbols.indices, id: \.self) { index in
                let symbol = symbols[index]

                Text(symbol)
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                    .foregroundStyle(index == 0 ? Color(red: 0.98, green: 0.40, blue: 0.42) : AppTheme.secondaryText)
                    .background(AppTheme.panel.opacity(0.92))
                    .overlay(alignment: .trailing) {
                        if index < symbols.count - 1 {
                            Rectangle()
                                .fill(AppTheme.border)
                                .frame(width: 1)
                        }
                    }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
        }
    }
}

struct CalendarTemplatePlacementStatus: View {
    var templateName: String
    var selectedCount: Int
    var taskCount: Int
    var message: String?
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.3x3.fill")
                .foregroundStyle(AppTheme.event)
            VStack(alignment: .leading, spacing: 2) {
                Text(templateName)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(message ?? "\(selectedCount)일 선택됨 · 작업 \(taskCount)개")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("선택한 템플릿 삭제")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}

struct CalendarNoticeBanner: View {
    var message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.bold))
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .foregroundStyle(AppTheme.eventText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.event.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
            .accessibilityAddTraits(.isStaticText)
    }
}

struct MobileMonthDayCell: View {
    var date: Date
    var visibleMonth: Date
    var isSelected: Bool
    var isPlacementSelected: Bool
    var events: [CalendarEvent]
    var templatePlacements: [TemplatePlacement]
    var specialDays: [SpecialDay]
    var showsTrailingDivider: Bool
    var showsBottomDivider: Bool

    private var isCurrentMonth: Bool {
        DayKey.isSameMonth(date, visibleMonth)
    }

    private var isToday: Bool {
        DayKey.isToday(date)
    }

    private var primarySpecialDay: SpecialDay? {
        specialDays.first
    }

    private var hasPublicHoliday: Bool {
        specialDays.contains { $0.isPublicHoliday }
    }

    private var cellBackground: Color {
        if isPlacementSelected { return AppTheme.event.opacity(0.16) }
        if isSelected { return AppTheme.selectedTab.opacity(0.32) }
        if !isCurrentMonth { return AppTheme.input.opacity(0.38) }
        return AppTheme.panel.opacity(isToday ? 0.92 : 0.72)
    }

    private var dayBackground: Color {
        if isPlacementSelected || isSelected || isToday { return AppTheme.event }
        return Color.clear
    }

    private var dayForeground: Color {
        if isPlacementSelected || isSelected || isToday { return AppTheme.eventText }
        if hasPublicHoliday, isCurrentMonth { return Color(red: 0.98, green: 0.40, blue: 0.42) }
        return isCurrentMonth ? AppTheme.primaryText : AppTheme.secondaryText.opacity(0.45)
    }

    private var accessibilityLabel: String {
        var parts = [DayKey.display(date)]
        if isSelected { parts.append("선택됨") }
        if isPlacementSelected { parts.append("배치 선택됨") }
        if let specialDay = specialDays.first { parts.append(specialDay.name) }
        if !events.isEmpty { parts.append("이벤트 \(events.count)개") }
        if !templatePlacements.isEmpty { parts.append("템플릿 배치 \(templatePlacements.count)개") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 3) {
                Text(DayKey.dayNumber(date))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(dayForeground)
                    .frame(width: 18, height: 18)
                    .background(dayBackground, in: Circle())

                if let specialDay = primarySpecialDay {
                    Text(specialDay.name)
                        .font(.system(size: 8, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(specialDayForeground(specialDay))
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
                if isPlacementSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.event)
                        .padding(.top, 2)
                } else if !templatePlacements.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "square.grid.3x3.fill")
                        if templatePlacements.count > 1 {
                            Text("\(templatePlacements.count)")
                        }
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.event)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(AppTheme.event.opacity(0.12), in: Capsule())
                    .fixedSize()
                    .accessibilityLabel("템플릿 배치 \(templatePlacements.count)개")
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cellBackground)
        .overlay(alignment: .trailing) {
            if showsTrailingDivider {
                Rectangle()
                    .fill(AppTheme.border)
                    .frame(width: 1)
            }
        }
        .overlay(alignment: .bottom) {
            if showsBottomDivider {
                Rectangle()
                    .fill(AppTheme.border)
                    .frame(height: 1)
            }
        }
        .overlay {
            if isPlacementSelected || isSelected {
                Rectangle()
                    .strokeBorder(AppTheme.event, lineWidth: isPlacementSelected ? 2 : 1.5)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private func specialDayForeground(_ specialDay: SpecialDay) -> Color {
        if !isCurrentMonth {
            return AppTheme.secondaryText.opacity(0.40)
        }

        if specialDay.isPublicHoliday {
            return Color(red: 0.98, green: 0.40, blue: 0.42)
        }

        return AppTheme.secondaryText
    }
}

struct MobileCalendarEventSpanBar: View {
    var event: CalendarEvent
    var isDimmed: Bool

    var body: some View {
        Text(event.title)
            .font(.system(size: 9, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(AppTheme.eventText)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                CalendarEventPalette.color(for: event.color).opacity(isDimmed ? 0.52 : 0.96),
                in: RoundedRectangle(cornerRadius: 2)
            )
    }
}
#endif
