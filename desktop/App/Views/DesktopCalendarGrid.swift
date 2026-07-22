import SwiftUI
import PlanBaseCore

struct CalendarEventSegment: Identifiable {
    var event: CalendarEvent
    var weekIndex: Int
    var startColumn: Int
    var span: Int
    var lane: Int
    var isDimmed: Bool

    var id: String {
        "\(event.id.uuidString)-\(weekIndex)-\(lane)"
    }
}

struct CalendarEventSegmentButton: View {
    var segment: CalendarEventSegment
    var isDisabled: Bool
    var width: CGFloat
    var height: CGFloat
    var xOffset: CGFloat
    var yOffset: CGFloat
    var onEdit: (CalendarEvent) -> Void
    var onDelete: (CalendarEvent) -> Void

    var body: some View {
        Button {
            onEdit(segment.event)
        } label: {
            EventSpanBar(event: segment.event, isDimmed: segment.isDimmed)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isDisabled)
        .frame(width: width, height: height)
        .offset(x: xOffset, y: yOffset)
        .contextMenu {
            Button(role: .destructive) {
                onDelete(segment.event)
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }
}

struct MonthDayCell: View {
    var date: Date
    var visibleMonth: Date
    var selectedDate: Date
    var placementMode: Bool
    var isPlacementSelected: Bool
    var specialDays: [SpecialDay]
    var onSelect: () -> Void
    var onAddEvent: () -> Void

    @State private var isHovered = false

    private var isCurrentMonth: Bool {
        DayKey.isSameMonth(date, visibleMonth)
    }

    private var isSelected: Bool {
        DayKey.key(for: date) == DayKey.key(for: selectedDate)
    }

    private var primarySpecialDay: SpecialDay? {
        specialDays.first
    }

    private var hasPublicHoliday: Bool {
        specialDays.contains { $0.isPublicHoliday }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(DayKey.dayNumber(date))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(dayForeground)
                        .frame(width: 24, height: 24)
                        .background(dayBackground, in: Circle())

                    if let primarySpecialDay {
                        Text(primarySpecialDay.name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(specialDayForeground(primarySpecialDay))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if specialDays.count > 1 {
                            Text("+\(specialDays.count - 1)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(AppTheme.columnTodo, in: Capsule())
                        }
                    }

                    Spacer()
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(cellBackground)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(AppTheme.border)
                    .frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppTheme.border)
                    .frame(height: 1)
            }
            .overlay {
                if isPlacementSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(AppTheme.event, lineWidth: 2)
                        .padding(2)
                }
            }

            if isHovered, !placementMode {
                Button {
                    onAddEvent()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .foregroundStyle(AppTheme.eventText)
                        .background(AppTheme.event, in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppTheme.border, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .padding(7)
                .help("이 날짜에 이벤트 추가")
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    private var cellBackground: Color {
        if isPlacementSelected {
            return AppTheme.selectedTab
        }
        if isSelected, !placementMode {
            return AppTheme.selectedTab
        }
        return isCurrentMonth ? AppTheme.panel : AppTheme.columnTodo
    }

    private var dayBackground: Color {
        if isPlacementSelected || (!placementMode && isSelected) || DayKey.isToday(date) {
            return AppTheme.event
        }
        return Color.clear
    }

    private var dayForeground: Color {
        if isPlacementSelected || (!placementMode && isSelected) || DayKey.isToday(date) {
            return AppTheme.eventText
        }
        if hasPublicHoliday, isCurrentMonth {
            return Color(red: 0.98, green: 0.40, blue: 0.42)
        }
        return isCurrentMonth ? AppTheme.primaryText : AppTheme.secondaryText.opacity(0.45)
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

struct EventSpanBar: View {
    var event: CalendarEvent
    var isDimmed: Bool

    var body: some View {
        Text(event.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.eventText)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CalendarEventPalette.color(for: event.color).opacity(isDimmed ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 3))
    }
}

extension View {
    func calendarToolbarButtonBackground(isPrimary: Bool = false) -> some View {
        self
            .foregroundStyle(AppTheme.primaryText)
            .background(
                isPrimary ? AppTheme.selectedTab : AppTheme.panel,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
    }
}
