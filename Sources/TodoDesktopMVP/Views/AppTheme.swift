import Foundation
import SwiftUI

struct ThemeColorToken: Hashable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = Int(cleaned, radix: 16) ?? 0
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var relativeLuminance: Double {
        func convert(_ value: Double) -> Double {
            if value <= 0.03928 {
                return value / 12.92
            }
            return pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * convert(red) + 0.7152 * convert(green) + 0.0722 * convert(blue)
    }

    func contrastRatio(to other: ThemeColorToken) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

enum AppThemeAppearance: CaseIterable {
    case light
    case dark

    init(colorScheme: ColorScheme) {
        self = colorScheme == .light ? .light : .dark
    }
}

struct AppThemeColorSet: Hashable {
    var backgroundTop: ThemeColorToken
    var backgroundBottom: ThemeColorToken
    var panel: ThemeColorToken
    var input: ThemeColorToken
    var floatingBar: ThemeColorToken
    var border: ThemeColorToken

    var primaryText: ThemeColorToken
    var secondaryText: ThemeColorToken
    var cardText: ThemeColorToken
    var cardMutedText: ThemeColorToken
    var eventText: ThemeColorToken

    var selectedTab: ThemeColorToken
    var columnTodo: ThemeColorToken
    var columnDoing: ThemeColorToken
    var columnDone: ThemeColorToken
    var todo: ThemeColorToken
    var doing: ThemeColorToken
    var done: ThemeColorToken
    var event: ThemeColorToken
    var eventPalette: [ThemeColorToken]
}

struct AppThemePreset: Identifiable, Hashable {
    var id: String
    var name: String
    var sourcePaletteHexes: [String]

    var backgroundTop: ThemeColorToken
    var backgroundBottom: ThemeColorToken
    var panel: ThemeColorToken
    var input: ThemeColorToken
    var floatingBar: ThemeColorToken
    var border: ThemeColorToken

    var primaryText: ThemeColorToken
    var secondaryText: ThemeColorToken
    var cardText: ThemeColorToken
    var cardMutedText: ThemeColorToken

    var selectedTab: ThemeColorToken
    var columnTodo: ThemeColorToken
    var columnDoing: ThemeColorToken
    var columnDone: ThemeColorToken
    var todo: ThemeColorToken
    var doing: ThemeColorToken
    var done: ThemeColorToken
    var event: ThemeColorToken
    var eventPalette: [ThemeColorToken]

    var sourceColors: [Color] {
        sourcePaletteHexes.map { ThemeColorToken(hex: $0).color }
    }

    func colorSet(for appearance: AppThemeAppearance) -> AppThemeColorSet {
        switch appearance {
        case .dark:
            return darkColorSet
        case .light:
            return lightColorSet
        }
    }

    private var darkColorSet: AppThemeColorSet {
        AppThemeColorSet(
            backgroundTop: backgroundTop,
            backgroundBottom: backgroundBottom,
            panel: panel,
            input: input,
            floatingBar: floatingBar,
            border: border,
            primaryText: primaryText,
            secondaryText: secondaryText,
            cardText: cardText,
            cardMutedText: cardMutedText,
            eventText: ThemeColorToken(hex: "#FFFFFF"),
            selectedTab: selectedTab,
            columnTodo: columnTodo,
            columnDoing: columnDoing,
            columnDone: columnDone,
            todo: todo,
            doing: doing,
            done: done,
            event: event,
            eventPalette: eventPalette
        )
    }

    private var lightColorSet: AppThemeColorSet {
        switch id {
        case "appleSystem":
            return light(
                backgroundTop: "#F1F3F6",
                backgroundBottom: "#ECEFF3",
                panel: "#FFFFFF",
                input: "#F7F8FA",
                floatingBar: "#F9FAFC",
                border: "#C8CED8",
                selectedTab: "#C9DFFF",
                columnTodo: "#E6E8ED",
                columnDoing: "#D9E9FF",
                columnDone: "#D6EBDD",
                todo: "#F7F8FA",
                doing: "#D6E8FF",
                done: "#D6ECD8",
                event: "#0066CC",
                eventPalette: ["#0066CC", "#B4232F", "#1F7A36", "#6E3BC6", "#B45309", "#007C89"]
            )
        case "navyBlush":
            return light(
                backgroundTop: "#F2F6FC",
                backgroundBottom: "#DFE8F5",
                panel: "#FFFFFF",
                input: "#F5F7FC",
                floatingBar: "#F0F5FC",
                border: "#B7CAE4",
                selectedTab: "#C5D6EF",
                columnTodo: "#E5EAF3",
                columnDoing: "#D6E2F7",
                columnDone: "#F0D7D8",
                todo: "#F7F9FD",
                doing: "#D4E0F5",
                done: "#EFD4D5",
                event: "#1A2A4F",
                eventPalette: ["#1A2A4F", "#842A3B", "#436850", "#6A1E55", "#A3485A", "#295F4E"]
            )
        case "plumNight":
            return light(
                backgroundTop: "#FFF4FB",
                backgroundBottom: "#EEDDEA",
                panel: "#FFFFFF",
                input: "#FFF4FB",
                floatingBar: "#FFF0FA",
                border: "#D3B1CB",
                selectedTab: "#E5CADC",
                columnTodo: "#EFE2EE",
                columnDoing: "#E8D2E4",
                columnDone: "#DCEBE2",
                todo: "#FCF8FC",
                doing: "#E3CCE0",
                done: "#D7E9DF",
                event: "#6A1E55",
                eventPalette: ["#3B1C32", "#6A1E55", "#A64D79", "#842A3B", "#436850", "#1A2A4F"]
            )
        case "forestCream":
            return light(
                backgroundTop: "#F7FCF2",
                backgroundBottom: "#E1EEDB",
                panel: "#FFFFFF",
                input: "#F4FAEF",
                floatingBar: "#F1F8ED",
                border: "#B4D2AA",
                selectedTab: "#CFE5C6",
                columnTodo: "#E4EEDF",
                columnDoing: "#D6E8D8",
                columnDone: "#EAE4CD",
                todo: "#F8FBF5",
                doing: "#D1E6D1",
                done: "#E8E0C8",
                event: "#436850",
                eventPalette: ["#12372A", "#436850", "#295F4E", "#662222", "#6A1E55", "#1A2A4F"]
            )
        case "tealPaper":
            return light(
                backgroundTop: "#F8F6EF",
                backgroundBottom: "#E2EFE9",
                panel: "#FFFFFF",
                input: "#F3F8F5",
                floatingBar: "#F1F8F4",
                border: "#B0D2C4",
                selectedTab: "#C7E1D5",
                columnTodo: "#E4ECE8",
                columnDoing: "#CFE7DD",
                columnDone: "#E9DFC8",
                todo: "#F8FAF6",
                doing: "#C9E4D8",
                done: "#E5DABB",
                event: "#295F4E",
                eventPalette: ["#323232", "#295F4E", "#436850", "#842A3B", "#6A1E55", "#1A2A4F"]
            )
        case "solarBerry":
            return light(
                backgroundTop: "#FFF4EE",
                backgroundBottom: "#F1DDD5",
                panel: "#FFFFFF",
                input: "#FFF3EE",
                floatingBar: "#FFF0EA",
                border: "#DDAEA5",
                selectedTab: "#EACBC5",
                columnTodo: "#F0E1DD",
                columnDoing: "#EFCFD9",
                columnDone: "#EEE1B8",
                todo: "#FFFAF8",
                doing: "#EBCAD4",
                done: "#E8D9A8",
                event: "#900C3F",
                eventPalette: ["#900C3F", "#C70039", "#9A351E", "#5C4A08", "#436850", "#1A2A4F"]
            )
        default:
            return light(
                backgroundTop: "#FFF4ED",
                backgroundBottom: "#F0DDD7",
                panel: "#FFFDFB",
                input: "#FFF5F2",
                floatingBar: "#FFF0EC",
                border: "#D8B0B8",
                selectedTab: "#E7C6CD",
                columnTodo: "#F0E3DF",
                columnDoing: "#EED3DC",
                columnDone: "#DDEBDF",
                todo: "#FFF9F6",
                doing: "#EDD0DA",
                done: "#D8EADF",
                event: "#842A3B",
                eventPalette: ["#842A3B", "#A3485A", "#436850", "#6A1E55", "#C70039", "#295F4E"]
            )
        }
    }

    private func light(
        backgroundTop: String,
        backgroundBottom: String,
        panel: String,
        input: String,
        floatingBar: String,
        border: String,
        selectedTab: String,
        columnTodo: String,
        columnDoing: String,
        columnDone: String,
        todo: String,
        doing: String,
        done: String,
        event: String,
        eventPalette: [String]
    ) -> AppThemeColorSet {
        AppThemeColorSet(
            backgroundTop: ThemeColorToken(hex: backgroundTop),
            backgroundBottom: ThemeColorToken(hex: backgroundBottom),
            panel: ThemeColorToken(hex: panel),
            input: ThemeColorToken(hex: input),
            floatingBar: ThemeColorToken(hex: floatingBar),
            border: ThemeColorToken(hex: border),
            primaryText: ThemeColorToken(hex: "#1F1A1C"),
            secondaryText: ThemeColorToken(hex: "#5F5558"),
            cardText: ThemeColorToken(hex: "#1F1A1C"),
            cardMutedText: ThemeColorToken(hex: "#61575A"),
            eventText: ThemeColorToken(hex: "#FFFFFF"),
            selectedTab: ThemeColorToken(hex: selectedTab),
            columnTodo: ThemeColorToken(hex: columnTodo),
            columnDoing: ThemeColorToken(hex: columnDoing),
            columnDone: ThemeColorToken(hex: columnDone),
            todo: ThemeColorToken(hex: todo),
            doing: ThemeColorToken(hex: doing),
            done: ThemeColorToken(hex: done),
            event: ThemeColorToken(hex: event),
            eventPalette: eventPalette.map(ThemeColorToken.init(hex:))
        )
    }

    static let defaultID = "appleSystem"
    static let legacyDefaultID = "maroonEmber"

    static let all: [AppThemePreset] = [
        AppThemePreset(
            id: "appleSystem",
            name: "Apple System",
            sourcePaletteHexes: ["#007AFF", "#34C759", "#FF9500", "#AF52DE"],
            backgroundTop: ThemeColorToken(hex: "#1C1C1E"),
            backgroundBottom: ThemeColorToken(hex: "#202124"),
            panel: ThemeColorToken(hex: "#2C2C2E"),
            input: ThemeColorToken(hex: "#242426"),
            floatingBar: ThemeColorToken(hex: "#242426"),
            border: ThemeColorToken(hex: "#48484A"),
            primaryText: ThemeColorToken(hex: "#F5F5F7"),
            secondaryText: ThemeColorToken(hex: "#D1D1D6"),
            cardText: ThemeColorToken(hex: "#FFFFFF"),
            cardMutedText: ThemeColorToken(hex: "#D1D1D6"),
            selectedTab: ThemeColorToken(hex: "#0A3A69"),
            columnTodo: ThemeColorToken(hex: "#2A2A2D"),
            columnDoing: ThemeColorToken(hex: "#182D44"),
            columnDone: ThemeColorToken(hex: "#1C3326"),
            todo: ThemeColorToken(hex: "#1F1F21"),
            doing: ThemeColorToken(hex: "#12365A"),
            done: ThemeColorToken(hex: "#1B4A2A"),
            event: ThemeColorToken(hex: "#0057B8"),
            eventPalette: [
                ThemeColorToken(hex: "#0057B8"),
                ThemeColorToken(hex: "#B4232F"),
                ThemeColorToken(hex: "#1E7F39"),
                ThemeColorToken(hex: "#6E3BC6"),
                ThemeColorToken(hex: "#B45309"),
                ThemeColorToken(hex: "#007C89")
            ]
        ),
        AppThemePreset(
            id: "maroonEmber",
            name: "Maroon Ember",
            sourcePaletteHexes: ["#662222", "#842A3B", "#A3485A", "#F5DAA7"],
            backgroundTop: ThemeColorToken(hex: "#120D0F"),
            backgroundBottom: ThemeColorToken(hex: "#1C1012"),
            panel: ThemeColorToken(hex: "#221416"),
            input: ThemeColorToken(hex: "#2A1A1D"),
            floatingBar: ThemeColorToken(hex: "#28191C"),
            border: ThemeColorToken(hex: "#4A3035"),
            primaryText: ThemeColorToken(hex: "#F6F1EA"),
            secondaryText: ThemeColorToken(hex: "#D8CCC4"),
            cardText: ThemeColorToken(hex: "#FFF8F0"),
            cardMutedText: ThemeColorToken(hex: "#E4D6CD"),
            selectedTab: ThemeColorToken(hex: "#842A3B"),
            columnTodo: ThemeColorToken(hex: "#241B1E"),
            columnDoing: ThemeColorToken(hex: "#2D1822"),
            columnDone: ThemeColorToken(hex: "#17261E"),
            todo: ThemeColorToken(hex: "#1B1719"),
            doing: ThemeColorToken(hex: "#3B1C32"),
            done: ThemeColorToken(hex: "#12372A"),
            event: ThemeColorToken(hex: "#A3485A"),
            eventPalette: [
                ThemeColorToken(hex: "#842A3B"),
                ThemeColorToken(hex: "#A3485A"),
                ThemeColorToken(hex: "#436850"),
                ThemeColorToken(hex: "#6A1E55"),
                ThemeColorToken(hex: "#C70039"),
                ThemeColorToken(hex: "#295F4E")
            ]
        ),
        AppThemePreset(
            id: "navyBlush",
            name: "Navy Blush",
            sourcePaletteHexes: ["#1A2A4F", "#F7A5A5", "#FFDBB6", "#FFF2EF"],
            backgroundTop: ThemeColorToken(hex: "#0B1020"),
            backgroundBottom: ThemeColorToken(hex: "#10192E"),
            panel: ThemeColorToken(hex: "#151F34"),
            input: ThemeColorToken(hex: "#172238"),
            floatingBar: ThemeColorToken(hex: "#172238"),
            border: ThemeColorToken(hex: "#32415F"),
            primaryText: ThemeColorToken(hex: "#F4F7FA"),
            secondaryText: ThemeColorToken(hex: "#D5DCE6"),
            cardText: ThemeColorToken(hex: "#F7FAFD"),
            cardMutedText: ThemeColorToken(hex: "#D9E0E8"),
            selectedTab: ThemeColorToken(hex: "#1A2A4F"),
            columnTodo: ThemeColorToken(hex: "#1B2230"),
            columnDoing: ThemeColorToken(hex: "#172944"),
            columnDone: ThemeColorToken(hex: "#162B24"),
            todo: ThemeColorToken(hex: "#141923"),
            doing: ThemeColorToken(hex: "#1A2A4F"),
            done: ThemeColorToken(hex: "#12372A"),
            event: ThemeColorToken(hex: "#842A3B"),
            eventPalette: [
                ThemeColorToken(hex: "#1A2A4F"),
                ThemeColorToken(hex: "#842A3B"),
                ThemeColorToken(hex: "#436850"),
                ThemeColorToken(hex: "#6A1E55"),
                ThemeColorToken(hex: "#A3485A"),
                ThemeColorToken(hex: "#295F4E")
            ]
        ),
        AppThemePreset(
            id: "plumNight",
            name: "Plum Night",
            sourcePaletteHexes: ["#1A1A1D", "#3B1C32", "#6A1E55", "#A64D79"],
            backgroundTop: ThemeColorToken(hex: "#101012"),
            backgroundBottom: ThemeColorToken(hex: "#181219"),
            panel: ThemeColorToken(hex: "#1D1720"),
            input: ThemeColorToken(hex: "#231B25"),
            floatingBar: ThemeColorToken(hex: "#211A24"),
            border: ThemeColorToken(hex: "#443148"),
            primaryText: ThemeColorToken(hex: "#F7F4F8"),
            secondaryText: ThemeColorToken(hex: "#DDD4E1"),
            cardText: ThemeColorToken(hex: "#FFF7FF"),
            cardMutedText: ThemeColorToken(hex: "#E7DCEB"),
            selectedTab: ThemeColorToken(hex: "#6A1E55"),
            columnTodo: ThemeColorToken(hex: "#201B22"),
            columnDoing: ThemeColorToken(hex: "#28172B"),
            columnDone: ThemeColorToken(hex: "#17261E"),
            todo: ThemeColorToken(hex: "#18161A"),
            doing: ThemeColorToken(hex: "#3B1C32"),
            done: ThemeColorToken(hex: "#12372A"),
            event: ThemeColorToken(hex: "#A64D79"),
            eventPalette: [
                ThemeColorToken(hex: "#3B1C32"),
                ThemeColorToken(hex: "#6A1E55"),
                ThemeColorToken(hex: "#A64D79"),
                ThemeColorToken(hex: "#842A3B"),
                ThemeColorToken(hex: "#436850"),
                ThemeColorToken(hex: "#1A2A4F")
            ]
        ),
        AppThemePreset(
            id: "forestCream",
            name: "Forest Cream",
            sourcePaletteHexes: ["#12372A", "#436850", "#ADBC9F", "#FBFADA"],
            backgroundTop: ThemeColorToken(hex: "#07150F"),
            backgroundBottom: ThemeColorToken(hex: "#0E2018"),
            panel: ThemeColorToken(hex: "#13271E"),
            input: ThemeColorToken(hex: "#172C22"),
            floatingBar: ThemeColorToken(hex: "#172C22"),
            border: ThemeColorToken(hex: "#365346"),
            primaryText: ThemeColorToken(hex: "#F4F8EE"),
            secondaryText: ThemeColorToken(hex: "#D6E1CE"),
            cardText: ThemeColorToken(hex: "#FAFFF5"),
            cardMutedText: ThemeColorToken(hex: "#DFEAD8"),
            selectedTab: ThemeColorToken(hex: "#436850"),
            columnTodo: ThemeColorToken(hex: "#17231D"),
            columnDoing: ThemeColorToken(hex: "#183427"),
            columnDone: ThemeColorToken(hex: "#173323"),
            todo: ThemeColorToken(hex: "#111A16"),
            doing: ThemeColorToken(hex: "#12372A"),
            done: ThemeColorToken(hex: "#1F4B33"),
            event: ThemeColorToken(hex: "#436850"),
            eventPalette: [
                ThemeColorToken(hex: "#12372A"),
                ThemeColorToken(hex: "#436850"),
                ThemeColorToken(hex: "#295F4E"),
                ThemeColorToken(hex: "#662222"),
                ThemeColorToken(hex: "#6A1E55"),
                ThemeColorToken(hex: "#1A2A4F")
            ]
        ),
        AppThemePreset(
            id: "tealPaper",
            name: "Teal Paper",
            sourcePaletteHexes: ["#323232", "#295F4E", "#6DB193", "#F4E5C2"],
            backgroundTop: ThemeColorToken(hex: "#101312"),
            backgroundBottom: ThemeColorToken(hex: "#151C1A"),
            panel: ThemeColorToken(hex: "#1C2421"),
            input: ThemeColorToken(hex: "#202923"),
            floatingBar: ThemeColorToken(hex: "#202923"),
            border: ThemeColorToken(hex: "#3D4D47"),
            primaryText: ThemeColorToken(hex: "#F4F1EA"),
            secondaryText: ThemeColorToken(hex: "#DCD6CA"),
            cardText: ThemeColorToken(hex: "#FFF9EF"),
            cardMutedText: ThemeColorToken(hex: "#E7DED0"),
            selectedTab: ThemeColorToken(hex: "#295F4E"),
            columnTodo: ThemeColorToken(hex: "#202322"),
            columnDoing: ThemeColorToken(hex: "#172C27"),
            columnDone: ThemeColorToken(hex: "#183225"),
            todo: ThemeColorToken(hex: "#171A19"),
            doing: ThemeColorToken(hex: "#295F4E"),
            done: ThemeColorToken(hex: "#12372A"),
            event: ThemeColorToken(hex: "#295F4E"),
            eventPalette: [
                ThemeColorToken(hex: "#323232"),
                ThemeColorToken(hex: "#295F4E"),
                ThemeColorToken(hex: "#436850"),
                ThemeColorToken(hex: "#842A3B"),
                ThemeColorToken(hex: "#6A1E55"),
                ThemeColorToken(hex: "#1A2A4F")
            ]
        ),
        AppThemePreset(
            id: "solarBerry",
            name: "Solar Berry",
            sourcePaletteHexes: ["#900C3F", "#C70039", "#FF5733", "#FFC300"],
            backgroundTop: ThemeColorToken(hex: "#170A12"),
            backgroundBottom: ThemeColorToken(hex: "#221016"),
            panel: ThemeColorToken(hex: "#29161A"),
            input: ThemeColorToken(hex: "#30191D"),
            floatingBar: ThemeColorToken(hex: "#30191D"),
            border: ThemeColorToken(hex: "#5A3034"),
            primaryText: ThemeColorToken(hex: "#FFF6EF"),
            secondaryText: ThemeColorToken(hex: "#E6D4C9"),
            cardText: ThemeColorToken(hex: "#FFF9F4"),
            cardMutedText: ThemeColorToken(hex: "#EADBD0"),
            selectedTab: ThemeColorToken(hex: "#900C3F"),
            columnTodo: ThemeColorToken(hex: "#26191A"),
            columnDoing: ThemeColorToken(hex: "#351226"),
            columnDone: ThemeColorToken(hex: "#252415"),
            todo: ThemeColorToken(hex: "#1D1718"),
            doing: ThemeColorToken(hex: "#900C3F"),
            done: ThemeColorToken(hex: "#5C4A08"),
            event: ThemeColorToken(hex: "#C70039"),
            eventPalette: [
                ThemeColorToken(hex: "#900C3F"),
                ThemeColorToken(hex: "#C70039"),
                ThemeColorToken(hex: "#9A351E"),
                ThemeColorToken(hex: "#5C4A08"),
                ThemeColorToken(hex: "#436850"),
                ThemeColorToken(hex: "#1A2A4F")
            ]
        )
    ]

    static func preset(for id: String?) -> AppThemePreset {
        all.first { $0.id == id } ?? all.first { $0.id == defaultID } ?? all[0]
    }
}

@MainActor
enum AppTheme {
    nonisolated static let storageKey = "todoAppThemeID"
    nonisolated static let defaultMigrationKey = "todoAppThemeDefaultMigrationVersion"
    nonisolated static let currentDefaultMigrationVersion = 2
    private static var activeID = UserDefaults.standard.string(forKey: storageKey) ?? AppThemePreset.defaultID
    private static var activeAppearance: AppThemeAppearance = .dark

    static var current: AppThemePreset {
        AppThemePreset.preset(for: activeID)
    }

    static var colors: AppThemeColorSet {
        current.colorSet(for: activeAppearance)
    }

    static func activate(_ id: String, colorScheme: ColorScheme) {
        activeID = id
        activeAppearance = AppThemeAppearance(colorScheme: colorScheme)
        UserDefaults.standard.set(id, forKey: storageKey)
    }

    static func migrateStoredDefaultIfNeeded(_ id: String) -> String {
        let migrationVersion = UserDefaults.standard.integer(forKey: defaultMigrationKey)
        guard migrationVersion < currentDefaultMigrationVersion else {
            return id
        }

        UserDefaults.standard.set(currentDefaultMigrationVersion, forKey: defaultMigrationKey)
        UserDefaults.standard.set(AppThemePreset.defaultID, forKey: storageKey)
        return AppThemePreset.defaultID
    }

    static var background: LinearGradient {
        LinearGradient(
            colors: [colors.backgroundTop.color, colors.backgroundBottom.color],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var primaryText: Color { colors.primaryText.color }
    static var secondaryText: Color { colors.secondaryText.color }
    static var border: Color { colors.border.color }

    static var selectedTab: Color { colors.selectedTab.color }
    static var floatingBar: Color { colors.floatingBar.color.opacity(0.96) }
    static var panel: Color { colors.panel.color }
    static var input: Color { colors.input.color }

    static var columnTodo: Color { colors.columnTodo.color }
    static var columnDoing: Color { colors.columnDoing.color }
    static var columnDone: Color { colors.columnDone.color }

    static var todo: Color { colors.todo.color }
    static var doing: Color { colors.doing.color }
    static var done: Color { colors.done.color }
    static var event: Color { colors.event.color }
    static var eventText: Color { colors.eventText.color }
    static var cardText: Color { colors.cardText.color }
    static var cardMutedText: Color { colors.cardMutedText.color }

    static func eventColor(at index: Int) -> Color {
        let palette = colors.eventPalette
        guard palette.indices.contains(index) else {
            return colors.event.color
        }
        return palette[index].color
    }
}
