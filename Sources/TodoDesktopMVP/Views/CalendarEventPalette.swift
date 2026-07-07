import SwiftUI

enum CalendarEventColor: String, CaseIterable, Identifiable {
    case blue
    case red
    case green
    case purple
    case orange
    case teal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: "파랑"
        case .red: "빨강"
        case .green: "초록"
        case .purple: "보라"
        case .orange: "주황"
        case .teal: "청록"
        }
    }

    var paletteIndex: Int {
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
    var color: Color {
        AppTheme.eventColor(at: paletteIndex)
    }
}

enum CalendarEventPalette {
    static let defaultColor = CalendarEventColor.blue.rawValue

    @MainActor
    static func color(for colorID: String?) -> Color {
        CalendarEventColor(rawValue: colorID ?? defaultColor)?.color ?? CalendarEventColor.blue.color
    }
}
