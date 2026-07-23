import Foundation
import PlanBaseCore
import SwiftUI

struct CalendarWidgetTheme {
    let colors: AppThemeColorSet

    init(themeID: String?, colorScheme: ColorScheme) {
        colors = AppThemePreset
            .preset(for: themeID)
            .colorSet(for: AppThemeAppearance(colorScheme: colorScheme))
    }

    var background: LinearGradient {
        LinearGradient(
            colors: [colors.backgroundTop.color, colors.backgroundBottom.color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var primaryText: Color { colors.primaryText.color }
    var secondaryText: Color { colors.secondaryText.color }
    var panel: Color { colors.panel.color }
    var input: Color { colors.input.color }
    var border: Color { colors.border.color }
    var accent: Color { colors.event.color }
    var accentForeground: Color { readableForeground(on: colors.event) }
    var sundayText: Color { eventToken(CalendarEventColor.red.rawValue).color }

    func eventColor(_ colorID: String) -> Color {
        eventToken(colorID).color
    }

    func eventForeground(_ colorID: String) -> Color {
        readableForeground(on: eventToken(colorID))
    }

    private func eventToken(_ colorID: String) -> ThemeColorToken {
        let index = CalendarEventColor(rawValue: colorID)?.paletteIndex ?? 0
        guard colors.eventPalette.indices.contains(index) else {
            return colors.event
        }
        return colors.eventPalette[index]
    }

    private func readableForeground(on background: ThemeColorToken) -> Color {
        let black = ThemeColorToken(hex: "#000000")
        let white = ThemeColorToken(hex: "#FFFFFF")
        let candidates = [colors.eventText, colors.primaryText, black, white]
        let token = candidates.first {
            $0.contrastRatio(to: background) >= 4.5
        } ?? candidates.max {
            $0.contrastRatio(to: background) < $1.contrastRatio(to: background)
        } ?? white
        return token.color
    }
}

extension CalendarWidgetSnapshot {
    static func empty(at date: Date) -> CalendarWidgetSnapshot {
        CalendarWidgetSnapshot(
            generatedAt: date,
            themeID: AppThemePreset.defaultID,
            events: []
        )
    }

    static var preview: CalendarWidgetSnapshot {
        let today = Date()
        let todayKey = DayKey.key(for: today)
        let tomorrowKey = DayKey.key(for: DayKey.addingDays(1, to: today))
        return CalendarWidgetSnapshot(
            generatedAt: today,
            themeID: "roseLilac",
            events: [
                CalendarWidgetEventSnapshot(
                    id: UUID(),
                    title: "프로젝트 정리",
                    startDayKey: todayKey,
                    endDayKey: todayKey,
                    colorID: CalendarEventColor.blue.rawValue
                ),
                CalendarWidgetEventSnapshot(
                    id: UUID(),
                    title: "운동 루틴",
                    startDayKey: todayKey,
                    endDayKey: tomorrowKey,
                    colorID: CalendarEventColor.green.rawValue
                )
            ]
        )
    }
}
