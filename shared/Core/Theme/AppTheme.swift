import Foundation
import Observation
import SwiftUI

public struct ThemeColorToken: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = Int(cleaned, radix: 16) ?? 0
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    public var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    public var relativeLuminance: Double {
        func convert(_ value: Double) -> Double {
            if value <= 0.03928 {
                return value / 12.92
            }
            return pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * convert(red) + 0.7152 * convert(green) + 0.0722 * convert(blue)
    }

    public func contrastRatio(to other: ThemeColorToken) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

public enum AppThemeAppearance: CaseIterable {
    case light
    case dark

    public init(colorScheme: ColorScheme) {
        self = colorScheme == .light ? .light : .dark
    }
}

public struct AppThemeColorSet: Hashable, Sendable {
    public var backgroundTop: ThemeColorToken
    public var backgroundBottom: ThemeColorToken
    public var panel: ThemeColorToken
    public var input: ThemeColorToken
    public var floatingBar: ThemeColorToken
    public var border: ThemeColorToken

    public var primaryText: ThemeColorToken
    public var secondaryText: ThemeColorToken
    public var cardText: ThemeColorToken
    public var cardMutedText: ThemeColorToken
    public var eventText: ThemeColorToken

    public var selectedTab: ThemeColorToken
    public var columnTodo: ThemeColorToken
    public var columnDoing: ThemeColorToken
    public var columnDone: ThemeColorToken
    public var todo: ThemeColorToken
    public var doing: ThemeColorToken
    public var done: ThemeColorToken
    public var event: ThemeColorToken
    public var eventPalette: [ThemeColorToken]

    public var resolvedDoneForeground: ThemeColorToken {
        resolvedCardForeground(on: done)
    }

    public var resolvedEventForeground: ThemeColorToken {
        resolvedEventForeground(on: event)
    }

    /// Unfilled controls need a different accent from filled buttons, especially on dark surfaces.
    public var resolvedAccentForeground: ThemeColorToken {
        let surfaces = [backgroundTop, backgroundBottom, panel, input, floatingBar, todo, doing, done]
        func isReadable(_ color: ThemeColorToken) -> Bool {
            surfaces.allSatisfy { color.contrastRatio(to: $0) >= 4.5 }
        }
        if isReadable(event) { return event }
        for step in 1...100 {
            let amount = Double(step) / 100
            for target in [1.0, 0.0] {
                let candidate = ThemeColorToken(
                    red: event.red + (target - event.red) * amount,
                    green: event.green + (target - event.green) * amount,
                    blue: event.blue + (target - event.blue) * amount)
                if isReadable(candidate) { return candidate }
            }
        }
        return primaryText
    }

    public func resolvedCardForeground(on background: ThemeColorToken) -> ThemeColorToken {
        resolvedForeground(
            on: background,
            preferred: [cardText, primaryText]
        )
    }

    public func resolvedEventForeground(on background: ThemeColorToken) -> ThemeColorToken {
        resolvedForeground(
            on: background,
            preferred: [eventText, primaryText]
        )
    }

    public func resolvedSemanticForeground(
        _ preferred: ThemeColorToken,
        on background: ThemeColorToken
    ) -> ThemeColorToken {
        resolvedForeground(
            on: background,
            preferred: [preferred, primaryText]
        )
    }

    private func resolvedForeground(
        on background: ThemeColorToken,
        preferred: [ThemeColorToken]
    ) -> ThemeColorToken {
        let fallbackCandidates = [
            ThemeColorToken(hex: "#000000"),
            ThemeColorToken(hex: "#FFFFFF")
        ]
        let candidates = preferred + fallbackCandidates
        if let accessible = candidates.first(where: {
            $0.contrastRatio(to: background) >= 4.5
        }) {
            return accessible
        }
        return candidates.max(by: {
            $0.contrastRatio(to: background) < $1.contrastRatio(to: background)
        }) ?? ThemeColorToken(hex: "#FFFFFF")
    }
}


@MainActor @Observable
private final class AppThemeRuntime {
    var id: String
    var appearance: AppThemeAppearance = .light
    var accent: ThemeColorToken

    init() {
        let storedID = UserDefaults.standard.string(forKey: AppTheme.storageKey) ?? AppThemePreset.defaultID
        id = storedID
        accent = AppThemePreset.preset(for: storedID).colorSet(for: .light).resolvedAccentForeground
    }
}

@MainActor
public enum AppTheme {
    public nonisolated static let storageKey = "todoAppThemeID"
    public nonisolated static let defaultMigrationKey = "todoAppThemeDefaultMigrationVersion"
    public nonisolated static let currentDefaultMigrationVersion = 2
    private static let runtime = AppThemeRuntime()

    public static var current: AppThemePreset {
        AppThemePreset.preset(for: runtime.id)
    }

    public static var colors: AppThemeColorSet {
        current.colorSet(for: runtime.appearance)
    }

    public static func activate(_ id: String, colorScheme: ColorScheme) {
        runtime.id = id
        runtime.appearance = AppThemeAppearance(colorScheme: colorScheme)
        runtime.accent = colors.resolvedAccentForeground
        UserDefaults.standard.set(id, forKey: storageKey)
    }

    public static func migrateStoredDefaultIfNeeded(_ id: String) -> String {
        let migrationVersion = UserDefaults.standard.integer(forKey: defaultMigrationKey)
        guard migrationVersion < currentDefaultMigrationVersion else {
            return id
        }

        UserDefaults.standard.set(currentDefaultMigrationVersion, forKey: defaultMigrationKey)
        UserDefaults.standard.set(AppThemePreset.defaultID, forKey: storageKey)
        return AppThemePreset.defaultID
    }

    public static var background: LinearGradient {
        LinearGradient(
            colors: [colors.backgroundTop.color, colors.backgroundBottom.color],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    public static var primaryText: Color { colors.primaryText.color }
    public static var secondaryText: Color { colors.secondaryText.color }
    public static var border: Color { colors.border.color }

    public static var selectedTab: Color { colors.selectedTab.color }
    public static var floatingBar: Color { colors.floatingBar.color.opacity(0.96) }
    public static var panel: Color { colors.panel.color }
    public static var input: Color { colors.input.color }

    public static var columnTodo: Color { colors.columnTodo.color }
    public static var columnDoing: Color { colors.columnDoing.color }
    public static var columnDone: Color { colors.columnDone.color }

    public static var todo: Color { colors.todo.color }
    public static var doing: Color { colors.doing.color }
    public static var done: Color { colors.done.color }
    public static var doneForeground: Color { colors.resolvedDoneForeground.color }
    public static var event: Color { colors.event.color }
    public static var accent: Color { runtime.accent.color }
    public static var eventText: Color { colors.resolvedEventForeground.color }
    public static var eventForeground: Color { colors.resolvedEventForeground.color }
    public static var cardText: Color { colors.cardText.color }
    public static var cardMutedText: Color { colors.cardMutedText.color }

    public static func eventColor(at index: Int) -> Color {
        let palette = colors.eventPalette
        guard palette.indices.contains(index) else {
            return colors.event.color
        }
        return palette[index].color
    }

    public static func eventForeground(at index: Int) -> Color {
        let palette = colors.eventPalette
        let background = palette.indices.contains(index) ? palette[index] : colors.event
        return colors.resolvedEventForeground(on: background).color
    }
}
