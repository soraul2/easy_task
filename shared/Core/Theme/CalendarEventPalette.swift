import SwiftUI

public enum CalendarEventColor: String, CaseIterable, Identifiable {
    case blue
    case red
    case green
    case purple
    case orange
    case teal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .blue: "파랑"
        case .red: "빨강"
        case .green: "초록"
        case .purple: "보라"
        case .orange: "주황"
        case .teal: "청록"
        }
    }

    public var paletteIndex: Int {
        switch self {
        case .blue: 0
        case .red: 1
        case .green: 2
        case .purple: 3
        case .orange: 4
        case .teal: 5
        }
    }

    @MainActor
    public var color: Color {
        AppTheme.eventColor(at: paletteIndex)
    }

    @MainActor
    public var foregroundColor: Color {
        AppTheme.eventForeground(at: paletteIndex)
    }
}

public enum CalendarEventPalette {
    public static let defaultColor = CalendarEventColor.blue.rawValue

    @MainActor
    public static func color(for colorID: String?) -> Color {
        CalendarEventColor(rawValue: colorID ?? defaultColor)?.color ?? CalendarEventColor.blue.color
    }

    @MainActor
    public static func foreground(for colorID: String?) -> Color {
        CalendarEventColor(rawValue: colorID ?? defaultColor)?.foregroundColor
            ?? CalendarEventColor.blue.foregroundColor
    }
}
