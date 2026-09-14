import Foundation
import SwiftUI

/// A fixed appearance with one canonical palette. Legacy IDs resolve at the boundary.
public struct AppThemePreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let isDarkTheme: Bool
    private let palette: AppThemeColorSet

    public var preferredColorScheme: ColorScheme { isDarkTheme ? .dark : .light }
    public var targetsWCAGTextContrast: Bool { true }

    /// Preview colors come from the same tokens as the actual interface.
    public var sourcePaletteHexes: [String] {
        [palette.panel, palette.backgroundBottom, palette.selectedTab, palette.accentFill].map(\.hexString)
    }
    public var sourceColors: [Color] {
        [palette.panel, palette.backgroundBottom, palette.selectedTab, palette.accentFill].map(\.color)
    }
    public func colorSet(for _: AppThemeAppearance) -> AppThemeColorSet { palette }

    public static let defaultID = "appleSystem"
    public static let legacyDefaultID = "maroonEmber"

    /// Preserve shipped IDs for preferences, old devices, and widget snapshots.
    public static let legacyAliases = [
        "apple2020": "appleSystem",
        "navyBlush": "appleSystem",
        "solarBerry": "maroonEmber"
    ]
    public static var knownIDs: [String] { all.map(\.id) + legacyAliases.keys.sorted() }

    public static func canonicalID(for id: String?) -> String? {
        guard let id else { return nil }
        if let canonical = legacyAliases[id] { return canonical }
        return all.contains { $0.id == id } ? id : nil
    }

    public static func aliases(for id: String) -> [String] {
        legacyAliases.keys.filter { legacyAliases[$0] == id }.sorted()
    }

    public static func preset(for id: String?) -> AppThemePreset {
        let canonical = canonicalID(for: id) ?? defaultID
        return all.first { $0.id == canonical } ?? all[0]
    }

    public static let all: [AppThemePreset] = [
        light(id: "appleSystem", name: "Clean White",
              bottom: "#F6F8FC", input: "#F3F6FC", border: "#CDD6E2",
              selection: "#E6EEFF", column: "#EDF2FC", doing: "#DDE8FF",
              fill: "#2563EB", ink: "#194BC2", darkInk: "#78B4FF"),
        light(id: "maroonEmber", name: "Apricot",
              bottom: "#FFF5E9", input: "#FFF8F0", border: "#E8CDB4",
              selection: "#FFEAD6", column: "#FFF0E2", doing: "#FFE4CB",
              fill: "#C45119", ink: "#9C340A", darkInk: "#FFAA70"),
        light(id: "plumNight", name: "Lavender Cloud",
              bottom: "#F5F0FF", input: "#F9F6FF", border: "#D9CAED",
              selection: "#EEE5FF", column: "#F1EAFC", doing: "#E8DCFF",
              fill: "#7C3AED", ink: "#6522CC", darkInk: "#BF9BFF"),
        light(id: "roseLilac", name: "Blush Pink",
              bottom: "#FFF1F6", input: "#FFF7FA", border: "#EAC6D7",
              selection: "#FFE5EF", column: "#FCEBF2", doing: "#FFDFEC",
              fill: "#C32F72", ink: "#A51F5A", darkInk: "#FF91BF"),
        light(id: "forestCream", name: "Mint Cream",
              bottom: "#F0F9F2", input: "#F5FAF5", border: "#BEDBC8",
              selection: "#DDF3E4", column: "#E8F5EB", doing: "#CDEEDF",
              fill: "#147D52", ink: "#0E613F", darkInk: "#66D6A0"),
        light(id: "tealPaper", name: "Aqua Mist",
              bottom: "#EFF9FC", input: "#F4FBFD", border: "#BFDCE5",
              selection: "#DCF1F7", column: "#E7F4F8", doing: "#D0EDF2",
              fill: "#007D91", ink: "#006172", darkInk: "#59CEE6"),
        dark(id: "midnightBlue", name: "Midnight Blue",
             top: "#08101D", bottom: "#101B30", panel: "#121E32", input: "#17253B",
             border: "#314763", text: "#F4F8FF", muted: "#BAC8DB",
             selection: "#1F3553", columnTodo: "#151F2D", columnDoing: "#142B46",
             todo: "#111A27", doing: "#173E68", accent: "#78B4FF", lightInk: "#194BC2"),
        dark(id: "charcoalRose", name: "Charcoal Rose",
             top: "#121014", bottom: "#1D171D", panel: "#251E25", input: "#2E252D",
             border: "#51404D", text: "#FFF7FA", muted: "#D6C3CB",
             selection: "#4A293A", columnTodo: "#282229", columnDoing: "#35232D",
             todo: "#211C22", doing: "#5B2F43", accent: "#F08DB3", lightInk: "#A51F5A")
    ]

    /// Classification colors deliberately retain their hue across all themes.
    private static let calendarColors = ["#2563A8", "#B33442", "#2F7352", "#7554A3", "#A75113", "#007780"]
        .map(ThemeColorToken.init(hex:))

    private static func light(
        id: String, name: String, bottom: String, input: String, border: String,
        selection: String, column: String, doing: String, fill: String, ink: String, darkInk: String
    ) -> AppThemePreset {
        let white = ThemeColorToken(hex: "#FFFFFF")
        let text = ThemeColorToken(hex: "#202127")
        let muted = ThemeColorToken(hex: "#565A65")
        return AppThemePreset(id: id, name: name, isDarkTheme: false, palette: AppThemeColorSet(
            backgroundTop: white, backgroundBottom: ThemeColorToken(hex: bottom),
            panel: white, input: ThemeColorToken(hex: input), floatingBar: white,
            border: ThemeColorToken(hex: border), primaryText: text, secondaryText: muted,
            cardText: text, cardMutedText: muted, eventText: white,
            accentFill: ThemeColorToken(hex: fill), onAccent: white,
            accentOnLight: ThemeColorToken(hex: ink), accentOnDark: ThemeColorToken(hex: darkInk),
            semanticRed: ThemeColorToken(hex: "#B42335"),
            selectedTab: ThemeColorToken(hex: selection),
            columnTodo: ThemeColorToken(hex: "#F1F3F6"), columnDoing: ThemeColorToken(hex: column),
            columnDone: ThemeColorToken(hex: "#EAF3EE"),
            todo: ThemeColorToken(hex: "#F8FAFC"), doing: ThemeColorToken(hex: doing),
            done: ThemeColorToken(hex: "#E3F0E8"), event: calendarColors[0], eventPalette: calendarColors
        ))
    }

    private static func dark(
        id: String, name: String, top: String, bottom: String, panel: String, input: String,
        border: String, text: String, muted: String, selection: String,
        columnTodo: String, columnDoing: String, todo: String, doing: String, accent: String, lightInk: String
    ) -> AppThemePreset {
        let ink = ThemeColorToken(hex: text)
        let secondary = ThemeColorToken(hex: muted)
        let highlight = ThemeColorToken(hex: accent)
        return AppThemePreset(id: id, name: name, isDarkTheme: true, palette: AppThemeColorSet(
            backgroundTop: ThemeColorToken(hex: top), backgroundBottom: ThemeColorToken(hex: bottom),
            panel: ThemeColorToken(hex: panel), input: ThemeColorToken(hex: input),
            floatingBar: ThemeColorToken(hex: panel), border: ThemeColorToken(hex: border),
            primaryText: ink, secondaryText: secondary, cardText: ink, cardMutedText: secondary,
            eventText: ThemeColorToken(hex: "#FFFFFF"),
            accentFill: highlight, onAccent: ThemeColorToken(hex: top),
            accentOnLight: ThemeColorToken(hex: lightInk), accentOnDark: highlight,
            semanticRed: ThemeColorToken(hex: "#FF8A96"), selectedTab: ThemeColorToken(hex: selection),
            columnTodo: ThemeColorToken(hex: columnTodo), columnDoing: ThemeColorToken(hex: columnDoing),
            columnDone: ThemeColorToken(hex: "#172E23"),
            todo: ThemeColorToken(hex: todo), doing: ThemeColorToken(hex: doing),
            done: ThemeColorToken(hex: "#203E2E"), event: calendarColors[0], eventPalette: calendarColors
        ))
    }
}
