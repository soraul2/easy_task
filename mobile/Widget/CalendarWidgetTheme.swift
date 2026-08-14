import Foundation
import PlanBaseCore
import SwiftUI
import WidgetKit

struct CalendarWidgetTheme {
    let colors: AppThemeColorSet
    let renderingMode: WidgetRenderingMode

    init(
        themeID: String?,
        colorScheme: ColorScheme,
        renderingMode: WidgetRenderingMode
    ) {
        colors = AppThemePreset
            .preset(for: themeID)
            .colorSet(for: AppThemeAppearance(colorScheme: colorScheme))
        self.renderingMode = renderingMode
    }

    var background: LinearGradient {
        LinearGradient(
            colors: [colors.backgroundTop.color, colors.backgroundBottom.color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var primaryText: Color {
        usesFullColorPalette ? colors.primaryText.color : .primary
    }

    var secondaryText: Color {
        usesFullColorPalette ? colors.secondaryText.color : .secondary
    }

    var panel: Color {
        usesFullColorPalette ? colors.panel.color : Color.primary.opacity(0.08)
    }

    var input: Color {
        usesFullColorPalette ? colors.input.color : Color.primary.opacity(0.05)
    }

    var border: Color {
        usesFullColorPalette ? colors.border.color : Color.primary.opacity(0.22)
    }

    var accent: Color {
        usesFullColorPalette ? colors.event.color : .accentColor
    }

    var accentForeground: Color {
        guard usesFullColorPalette else { return .primary }
        return colors.resolvedEventForeground(on: colors.event).color
    }

    var sundayText: Color {
        guard usesFullColorPalette else { return .primary }
        return colors.resolvedSemanticForeground(
            eventToken(CalendarEventColor.red.rawValue),
            on: colors.panel
        ).color
    }

    func eventColor(_ colorID: String) -> Color {
        usesFullColorPalette ? eventToken(colorID).color : .accentColor
    }

    func eventForeground(_ colorID: String) -> Color {
        guard usesFullColorPalette else { return .primary }
        let background = eventToken(colorID)
        return colors.resolvedEventForeground(on: background).color
    }

    private var usesFullColorPalette: Bool {
        renderingMode == .fullColor
    }

    private func eventToken(_ colorID: String) -> ThemeColorToken {
        let index = CalendarEventColor(rawValue: colorID)?.paletteIndex ?? 0
        guard colors.eventPalette.indices.contains(index) else {
            return colors.event
        }
        return colors.eventPalette[index]
    }
}

extension CalendarWidgetSnapshot {
    static func empty(
        at date: Date,
        themeID: String? = AppThemePreset.defaultID
    ) -> CalendarWidgetSnapshot {
        CalendarWidgetSnapshot(
            generatedAt: date,
            themeID: themeID,
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
