import Foundation
import SwiftUI

public struct AppThemePreset: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var sourcePaletteHexes: [String]

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

    public var selectedTab: ThemeColorToken
    public var columnTodo: ThemeColorToken
    public var columnDoing: ThemeColorToken
    public var columnDone: ThemeColorToken
    public var todo: ThemeColorToken
    public var doing: ThemeColorToken
    public var done: ThemeColorToken
    public var event: ThemeColorToken
    public var eventPalette: [ThemeColorToken]

    public var sourceColors: [Color] {
        sourcePaletteHexes.map { ThemeColorToken(hex: $0).color }
    }

    public var targetsWCAGTextContrast: Bool {
        true
    }

    public var isDarkTheme: Bool {
        id == "midnightBlue" || id == "charcoalRose"
    }

    public var preferredColorScheme: ColorScheme {
        isDarkTheme ? .dark : .light
    }

    public func colorSet(for _: AppThemeAppearance) -> AppThemeColorSet {
        isDarkTheme ? darkColorSet : lightColorSet
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
                backgroundTop: "#FFFFFF",
                backgroundBottom: "#F5F9FF",
                panel: "#FFFFFF",
                input: "#F6F8FB",
                floatingBar: "#FFFFFF",
                border: "#CDD6E2",
                selectedTab: "#DDEBFF",
                columnTodo: "#F0F3F7",
                columnDoing: "#E6F1FF",
                columnDone: "#E8F4EC",
                todo: "#F8FAFC",
                doing: "#DCEBFF",
                done: "#DFF2E6",
                event: "#2563A8",
                eventPalette: ["#2563A8", "#A74463", "#2F7352", "#7354A3", "#9A5B22", "#26717A"]
            )
        case "apple2020":
            return light(
                backgroundTop: "#FFFFFF",
                backgroundBottom: "#F2F2F7",
                panel: "#FFFFFF",
                input: "#F2F2F7",
                floatingBar: "#FFFFFF",
                border: "#D1D1D6",
                selectedTab: "#D6E8FF",
                columnTodo: "#F2F2F7",
                columnDoing: "#E5F1FF",
                columnDone: "#E6F4EA",
                todo: "#F8F8FA",
                doing: "#D9ECFF",
                done: "#DFF3E5",
                event: "#007AFF",
                eventPalette: ["#007AFF", "#D12E26", "#248A3D", "#8944AB", "#C93400", "#007B8A"],
                primaryText: "#1C1C1E",
                secondaryText: "#55555A",
                cardText: "#1C1C1E",
                cardMutedText: "#55555A"
            )
        case "navyBlush":
            return light(
                backgroundTop: "#FCFEFF",
                backgroundBottom: "#EAF6FF",
                panel: "#FFFFFF",
                input: "#F4FAFF",
                floatingBar: "#F8FCFF",
                border: "#BCD9EE",
                selectedTab: "#D6EDFF",
                columnTodo: "#EFF6FA",
                columnDoing: "#DFF1FF",
                columnDone: "#E4F3EA",
                todo: "#F8FCFF",
                doing: "#CCE9FF",
                done: "#DDF2E5",
                event: "#2373A8",
                eventPalette: ["#2373A8", "#9A5572", "#347358", "#6F5AA3", "#94601F", "#28727A"]
            )
        case "plumNight":
            return light(
                backgroundTop: "#FFFDFF",
                backgroundBottom: "#F3EEFF",
                panel: "#FFFFFF",
                input: "#FAF7FF",
                floatingBar: "#FCFAFF",
                border: "#D9CBEF",
                selectedTab: "#E9DFFF",
                columnTodo: "#F4F0FA",
                columnDoing: "#ECE2FF",
                columnDone: "#E5F2EA",
                todo: "#FCFAFF",
                doing: "#E3D5FF",
                done: "#DDF0E5",
                event: "#7554A3",
                eventPalette: ["#7554A3", "#9A527A", "#39705B", "#586AA3", "#936020", "#2F707A"]
            )
        case "roseLilac":
            return light(
                backgroundTop: "#FFFDFE",
                backgroundBottom: "#FFEFF6",
                panel: "#FFFFFF",
                input: "#FFF7FA",
                floatingBar: "#FFFAFC",
                border: "#EAC8D7",
                selectedTab: "#FFDDEA",
                columnTodo: "#FAF0F4",
                columnDoing: "#FFE4EE",
                columnDone: "#E8F3EC",
                todo: "#FFFAFC",
                doing: "#FFD6E5",
                done: "#E0F1E6",
                event: "#A94F73",
                eventPalette: ["#A94F73", "#A65259", "#39705B", "#7657A0", "#94601F", "#326D7A"]
            )
        case "forestCream":
            return light(
                backgroundTop: "#FDFFFE",
                backgroundBottom: "#ECFAF4",
                panel: "#FFFFFF",
                input: "#F5FCF8",
                floatingBar: "#F8FDFB",
                border: "#BFDCCE",
                selectedTab: "#D9F2E6",
                columnTodo: "#EFF7F3",
                columnDoing: "#E1F5EB",
                columnDone: "#E6F1EA",
                todo: "#FAFFFC",
                doing: "#CFEEDF",
                done: "#E0F1E6",
                event: "#37745A",
                eventPalette: ["#37745A", "#9B566A", "#2F6E78", "#7057A0", "#8D641F", "#3C6598"]
            )
        case "tealPaper":
            return light(
                backgroundTop: "#FCFFFF",
                backgroundBottom: "#EAFBFB",
                panel: "#FFFFFF",
                input: "#F4FCFC",
                floatingBar: "#F8FFFF",
                border: "#BDDCDD",
                selectedTab: "#D6F2F2",
                columnTodo: "#EEF7F7",
                columnDoing: "#DDF4F4",
                columnDone: "#E7F2EA",
                todo: "#F9FDFD",
                doing: "#CDEDEE",
                done: "#DFF0E4",
                event: "#2B7076",
                eventPalette: ["#2B7076", "#9B536B", "#397054", "#7157A0", "#8E631F", "#3B6597"]
            )
        case "solarBerry":
            return light(
                backgroundTop: "#FFFDF8",
                backgroundBottom: "#FFF4DE",
                panel: "#FFFFFF",
                input: "#FFFAF0",
                floatingBar: "#FFFCF6",
                border: "#E9D0A7",
                selectedTab: "#FFE7B7",
                columnTodo: "#F8F2E7",
                columnDoing: "#FFE9CA",
                columnDone: "#E6F1E8",
                todo: "#FFFCF7",
                doing: "#FFE0B8",
                done: "#DFF0E3",
                event: "#9A6424",
                eventPalette: ["#9A6424", "#A4515E", "#397052", "#7357A0", "#3E6597", "#2F7078"]
            )
        default:
            return light(
                backgroundTop: "#FFFDFC",
                backgroundBottom: "#FFF2ED",
                panel: "#FFFFFF",
                input: "#FFF8F5",
                floatingBar: "#FFFBF9",
                border: "#E8CFC5",
                selectedTab: "#FFE0D4",
                columnTodo: "#FAF0EC",
                columnDoing: "#FFE7DE",
                columnDone: "#E7F2E9",
                todo: "#FFFAF8",
                doing: "#FFDCCF",
                done: "#DFF0E3",
                event: "#A94F4F",
                eventPalette: ["#A94F4F", "#9A526B", "#2F7352", "#76569A", "#95611F", "#2D6E7A"]
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
        eventPalette: [String],
        primaryText: String = "#1F1A1C",
        secondaryText: String = "#5F5558",
        cardText: String = "#1F1A1C",
        cardMutedText: String = "#61575A",
        eventText: String = "#FFFFFF"
    ) -> AppThemeColorSet {
        AppThemeColorSet(
            backgroundTop: ThemeColorToken(hex: backgroundTop),
            backgroundBottom: ThemeColorToken(hex: backgroundBottom),
            panel: ThemeColorToken(hex: panel),
            input: ThemeColorToken(hex: input),
            floatingBar: ThemeColorToken(hex: floatingBar),
            border: ThemeColorToken(hex: border),
            primaryText: ThemeColorToken(hex: primaryText),
            secondaryText: ThemeColorToken(hex: secondaryText),
            cardText: ThemeColorToken(hex: cardText),
            cardMutedText: ThemeColorToken(hex: cardMutedText),
            eventText: ThemeColorToken(hex: eventText),
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

    public static let defaultID = "appleSystem"
    public static let legacyDefaultID = "maroonEmber"

    public static let all: [AppThemePreset] = [
        AppThemePreset(
            id: "appleSystem",
            name: "Clean White",
            sourcePaletteHexes: ["#FFFFFF", "#F5F9FF", "#DCEBFF", "#2563A8"],
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
            id: "apple2020",
            name: "Apple 2020",
            sourcePaletteHexes: ["#FFFFFF", "#F2F2F7", "#D9ECFF", "#007AFF"],
            backgroundTop: ThemeColorToken(hex: "#FFFFFF"),
            backgroundBottom: ThemeColorToken(hex: "#F2F2F7"),
            panel: ThemeColorToken(hex: "#FFFFFF"),
            input: ThemeColorToken(hex: "#F2F2F7"),
            floatingBar: ThemeColorToken(hex: "#FFFFFF"),
            border: ThemeColorToken(hex: "#D1D1D6"),
            primaryText: ThemeColorToken(hex: "#1C1C1E"),
            secondaryText: ThemeColorToken(hex: "#55555A"),
            cardText: ThemeColorToken(hex: "#1C1C1E"),
            cardMutedText: ThemeColorToken(hex: "#55555A"),
            selectedTab: ThemeColorToken(hex: "#D6E8FF"),
            columnTodo: ThemeColorToken(hex: "#F2F2F7"),
            columnDoing: ThemeColorToken(hex: "#E5F1FF"),
            columnDone: ThemeColorToken(hex: "#E6F4EA"),
            todo: ThemeColorToken(hex: "#F8F8FA"),
            doing: ThemeColorToken(hex: "#D9ECFF"),
            done: ThemeColorToken(hex: "#DFF3E5"),
            event: ThemeColorToken(hex: "#007AFF"),
            eventPalette: [
                ThemeColorToken(hex: "#007AFF"),
                ThemeColorToken(hex: "#D12E26"),
                ThemeColorToken(hex: "#248A3D"),
                ThemeColorToken(hex: "#8944AB"),
                ThemeColorToken(hex: "#C93400"),
                ThemeColorToken(hex: "#007B8A")
            ]
        ),
        AppThemePreset(
            id: "maroonEmber",
            name: "Peach Cream",
            sourcePaletteHexes: ["#FFFFFF", "#FFF2ED", "#FFDCCF", "#A94F4F"],
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
            name: "Sky Blue",
            sourcePaletteHexes: ["#FFFFFF", "#EAF6FF", "#CCE9FF", "#2373A8"],
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
            name: "Lavender Cloud",
            sourcePaletteHexes: ["#FFFFFF", "#F3EEFF", "#E3D5FF", "#7554A3"],
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
            id: "roseLilac",
            name: "Blush Pink",
            sourcePaletteHexes: ["#FFFFFF", "#FFEFF6", "#FFD6E5", "#A94F73"],
            backgroundTop: ThemeColorToken(hex: "#181417"),
            backgroundBottom: ThemeColorToken(hex: "#211A20"),
            panel: ThemeColorToken(hex: "#2B2229"),
            input: ThemeColorToken(hex: "#332830"),
            floatingBar: ThemeColorToken(hex: "#30262E"),
            border: ThemeColorToken(hex: "#655363"),
            primaryText: ThemeColorToken(hex: "#FFF4F7"),
            secondaryText: ThemeColorToken(hex: "#FFF4F7"),
            cardText: ThemeColorToken(hex: "#FFF8FA"),
            cardMutedText: ThemeColorToken(hex: "#FFF4F7"),
            selectedTab: ThemeColorToken(hex: "#675872"),
            columnTodo: ThemeColorToken(hex: "#30282F"),
            columnDoing: ThemeColorToken(hex: "#3F2D35"),
            columnDone: ThemeColorToken(hex: "#3A3143"),
            todo: ThemeColorToken(hex: "#282126"),
            doing: ThemeColorToken(hex: "#543840"),
            done: ThemeColorToken(hex: "#4B3F57"),
            event: ThemeColorToken(hex: "#9B6688"),
            eventPalette: [
                ThemeColorToken(hex: "#9B6688"),
                ThemeColorToken(hex: "#A9686D"),
                ThemeColorToken(hex: "#806891"),
                ThemeColorToken(hex: "#8B674F"),
                ThemeColorToken(hex: "#52766D"),
                ThemeColorToken(hex: "#5E6688")
            ]
        ),
        AppThemePreset(
            id: "forestCream",
            name: "Mint Cream",
            sourcePaletteHexes: ["#FFFFFF", "#ECFAF4", "#CFEEDF", "#37745A"],
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
            name: "Aqua Mist",
            sourcePaletteHexes: ["#FFFFFF", "#EAFBFB", "#CDEDEE", "#2B7076"],
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
            name: "Sunny Apricot",
            sourcePaletteHexes: ["#FFFFFF", "#FFF4DE", "#FFE0B8", "#9A6424"],
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
        ),
        AppThemePreset(
            id: "midnightBlue",
            name: "Midnight Blue",
            sourcePaletteHexes: ["#08101D", "#121E32", "#173E68", "#69A9FF"],
            backgroundTop: ThemeColorToken(hex: "#08101D"),
            backgroundBottom: ThemeColorToken(hex: "#101B30"),
            panel: ThemeColorToken(hex: "#121E32"),
            input: ThemeColorToken(hex: "#17253B"),
            floatingBar: ThemeColorToken(hex: "#111D30"),
            border: ThemeColorToken(hex: "#314763"),
            primaryText: ThemeColorToken(hex: "#F4F8FF"),
            secondaryText: ThemeColorToken(hex: "#BAC8DB"),
            cardText: ThemeColorToken(hex: "#F7FAFF"),
            cardMutedText: ThemeColorToken(hex: "#B9C7DA"),
            selectedTab: ThemeColorToken(hex: "#234E7D"),
            columnTodo: ThemeColorToken(hex: "#151F2D"),
            columnDoing: ThemeColorToken(hex: "#142B46"),
            columnDone: ThemeColorToken(hex: "#173226"),
            todo: ThemeColorToken(hex: "#111A27"),
            doing: ThemeColorToken(hex: "#173E68"),
            done: ThemeColorToken(hex: "#1D4D34"),
            event: ThemeColorToken(hex: "#2F68A1"),
            eventPalette: [
                ThemeColorToken(hex: "#2F68A1"),
                ThemeColorToken(hex: "#9C405B"),
                ThemeColorToken(hex: "#2D704E"),
                ThemeColorToken(hex: "#684A9C"),
                ThemeColorToken(hex: "#8E5A22"),
                ThemeColorToken(hex: "#236B75")
            ]
        ),
        AppThemePreset(
            id: "charcoalRose",
            name: "Charcoal Rose",
            sourcePaletteHexes: ["#121014", "#251E25", "#5B2F43", "#E38AAA"],
            backgroundTop: ThemeColorToken(hex: "#121014"),
            backgroundBottom: ThemeColorToken(hex: "#1D171D"),
            panel: ThemeColorToken(hex: "#251E25"),
            input: ThemeColorToken(hex: "#2E252D"),
            floatingBar: ThemeColorToken(hex: "#211A21"),
            border: ThemeColorToken(hex: "#51404D"),
            primaryText: ThemeColorToken(hex: "#FFF7FA"),
            secondaryText: ThemeColorToken(hex: "#D6C3CB"),
            cardText: ThemeColorToken(hex: "#FFF8FB"),
            cardMutedText: ThemeColorToken(hex: "#D5C0C9"),
            selectedTab: ThemeColorToken(hex: "#5A3245"),
            columnTodo: ThemeColorToken(hex: "#282229"),
            columnDoing: ThemeColorToken(hex: "#35232D"),
            columnDone: ThemeColorToken(hex: "#1F3029"),
            todo: ThemeColorToken(hex: "#211C22"),
            doing: ThemeColorToken(hex: "#5B2F43"),
            done: ThemeColorToken(hex: "#264A37"),
            event: ThemeColorToken(hex: "#A84970"),
            eventPalette: [
                ThemeColorToken(hex: "#A84970"),
                ThemeColorToken(hex: "#A34445"),
                ThemeColorToken(hex: "#377153"),
                ThemeColorToken(hex: "#6F4A92"),
                ThemeColorToken(hex: "#8B5A27"),
                ThemeColorToken(hex: "#2C6B77")
            ]
        )
    ]

    public static func preset(for id: String?) -> AppThemePreset {
        all.first { $0.id == id } ?? all.first { $0.id == defaultID } ?? all[0]
    }
}
