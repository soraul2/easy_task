import Foundation
import Observation
import Testing
@testable import EasyTaskCore

@Test
func unfilledControlsAndPrimaryButtonsRemainReadableInEveryPalette() {
    for preset in AppThemePreset.all {
        let colors = preset.colorSet(for: .light)
        for surface in [colors.backgroundTop, colors.backgroundBottom, colors.panel, colors.input,
                        colors.floatingBar, colors.selectedTab, colors.todo, colors.doing, colors.done] {
            #expect(colors.resolvedAccentForeground.contrastRatio(to: surface) >= 4.5)
        }
        #expect(colors.resolvedEventForeground.contrastRatio(to: colors.event) >= 4.5)
        #expect(colors.onAccent.contrastRatio(to: colors.accentFill) >= 4.5)
    }
}

@Test @MainActor
func themeChangesInvalidateObservedColorsWithoutReplacingViewIdentity() async {
    let previous = AppTheme.current.id
    defer { AppTheme.activate(previous, colorScheme: .light) }
    AppTheme.activate("appleSystem", colorScheme: .light)
    await confirmation("An existing view is notified when the palette changes") { changed in
        withObservationTracking {
            _ = AppTheme.colors
        } onChange: {
            changed()
        }
        AppTheme.activate("midnightBlue", colorScheme: .light)
    }
    #expect(AppTheme.colors == AppThemePreset.preset(for: "midnightBlue").colorSet(for: .dark))
}

@Test
func appThemePresetsMeetTextContrastTarget() {
    #expect(AppThemePreset.defaultID == "appleSystem")
    #expect(AppThemePreset.all.first?.id == AppThemePreset.defaultID)

    for preset in AppThemePreset.all {
        for appearance in AppThemeAppearance.allCases {
            let colors = preset.colorSet(for: appearance)
            let sharedSurfaces = [
                colors.backgroundTop,
                colors.backgroundBottom,
                colors.panel,
                colors.input,
                colors.floatingBar,
                colors.selectedTab,
                colors.columnTodo,
                colors.columnDoing,
                colors.columnDone
            ]

            for surface in sharedSurfaces {
                #expect(colors.primaryText.contrastRatio(to: surface) >= 4.5)
                #expect(colors.secondaryText.contrastRatio(to: surface) >= 4.5)
            }

            for cardSurface in [colors.todo, colors.doing, colors.done] {
                #expect(colors.cardText.contrastRatio(to: cardSurface) >= 4.5)
                #expect(colors.cardMutedText.contrastRatio(to: cardSurface) >= 4.5)
            }

            for eventColor in colors.eventPalette {
                #expect(
                    colors.resolvedEventForeground(on: eventColor)
                        .contrastRatio(to: eventColor) >= 4.5
                )
            }
        }
    }
}

@Test
func widgetSemanticForegroundsRemainReadableAcrossEveryTheme() {
    for preset in AppThemePreset.all {
        for appearance in AppThemeAppearance.allCases {
            let colors = preset.colorSet(for: appearance)
            let sundayRed = colors.eventPalette[CalendarEventColor.red.paletteIndex]

            for surface in [colors.panel, colors.input] {
                let foreground = colors.resolvedSemanticForeground(
                    sundayRed,
                    on: surface
                )
                #expect(foreground.contrastRatio(to: surface) >= 4.5)
            }
        }
    }
}

@Test
func unknownThemeIdentifierFallsBackToDefaultPreset() {
    #expect(
        AppThemePreset.preset(for: "unknown-widget-theme").id
            == AppThemePreset.defaultID
    )
}

@Test
func themeColorSetsStayFixedAcrossSystemAppearances() {
    for preset in AppThemePreset.all {
        #expect(preset.colorSet(for: .light) == preset.colorSet(for: .dark))
    }
}

@Test
func fixedThemePalettesUseTheirCanonicalBrightSurfaces() {
    let expectedBackgroundTop = Dictionary(uniqueKeysWithValues:
        ["appleSystem", "maroonEmber", "plumNight", "roseLilac", "forestCream", "tealPaper"]
            .map { ($0, ThemeColorToken(hex: "#FFFFFF")) })

    let brightPresets = AppThemePreset.all.filter { !$0.isDarkTheme }
    #expect(brightPresets.count == expectedBackgroundTop.count)

    for preset in brightPresets {
        let colors = preset.colorSet(for: .dark)
        #expect(colors.backgroundTop == expectedBackgroundTop[preset.id])
        #expect(colors.backgroundTop.relativeLuminance >= 0.95)
        #expect(colors.panel == ThemeColorToken(hex: "#FFFFFF"))
        #expect(preset.sourcePaletteHexes.first == "#FFFFFF")
        #expect(preset.preferredColorScheme == .light)
        #expect(colors.primaryText.relativeLuminance < colors.backgroundTop.relativeLuminance)
    }
}

@Test
func fixedDarkThemesUseLowLuminanceSurfacesAndDarkSystemChrome() {
    let expectedBackgroundTop: [String: ThemeColorToken] = [
        "midnightBlue": ThemeColorToken(hex: "#08101D"),
        "charcoalRose": ThemeColorToken(hex: "#121014")
    ]
    let darkPresets = AppThemePreset.all.filter(\.isDarkTheme)

    #expect(darkPresets.count == expectedBackgroundTop.count)
    for preset in darkPresets {
        let colors = preset.colorSet(for: .light)
        #expect(colors.backgroundTop == expectedBackgroundTop[preset.id])
        #expect(colors.backgroundTop.relativeLuminance < 0.02)
        #expect(colors.panel.relativeLuminance < 0.03)
        #expect(colors.primaryText.contrastRatio(to: colors.backgroundTop) >= 4.5)
        #expect(colors.primaryText.contrastRatio(to: colors.panel) >= 4.5)
        #expect(preset.preferredColorScheme == .dark)
    }
}

@Test
func roseLilacThemeUsesRequestedBrightPinkPalette() {
    let preset = AppThemePreset.preset(for: "roseLilac")

    #expect(preset.id == "roseLilac")
    #expect(preset.name == "Blush Pink")
    #expect(preset.sourcePaletteHexes == ["#FFFFFF", "#FFF1F6", "#FFE5EF", "#C32F72"])
    #expect(preset.targetsWCAGTextContrast)

    for appearance in AppThemeAppearance.allCases {
        let colors = preset.colorSet(for: appearance)
        for eventColor in colors.eventPalette {
            #expect(
                colors.resolvedEventForeground(on: eventColor)
                    .contrastRatio(to: eventColor) >= 4.5
            )
        }
    }
}

@Test
func consolidatedThemesResolveLegacySelectionAndWidgetIdentifiers() {
    #expect(AppThemePreset.all.count == 8)
    #expect(Set(AppThemePreset.all.map(\.name)) == Set([
        "Clean White", "Apricot", "Lavender Cloud", "Blush Pink", "Mint Cream", "Aqua Mist",
        "Midnight Blue", "Charcoal Rose"
    ]))
    for (legacy, canonical) in [("apple2020", "appleSystem"), ("navyBlush", "appleSystem"),
                                ("solarBerry", "maroonEmber")] {
        #expect(ThemePreferenceRules.isKnownThemeID(legacy))
        #expect(!AppThemePreset.all.contains { $0.id == legacy })
        #expect(AppThemePreset.preset(for: legacy) == AppThemePreset.preset(for: canonical))
    }
}

@Test
func persistedWidgetSnapshotsResolveRetiredThemeIDsWithoutRewritingPayloads() throws {
    for (legacy, canonical) in [("apple2020", "appleSystem"), ("navyBlush", "appleSystem"),
                                ("solarBerry", "maroonEmber")] {
        let payload = """
        {"schemaVersion":2,"generatedAt":"2026-09-07T00:00:00Z","themeID":"\(legacy)","events":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(CalendarWidgetSnapshot.self, from: Data(payload.utf8))
        #expect(snapshot.themeID == legacy)
        #expect(AppThemePreset.preset(for: snapshot.themeID).id == canonical)
        #expect(AppThemePreset.preset(for: snapshot.themeID).colorSet(for: .dark)
                == AppThemePreset.preset(for: canonical).colorSet(for: .light))
    }
}

@Test
func themeAccentsRetainColorAndContrastOnActualApplicationAndSystemSurfaces() {
    for preset in AppThemePreset.all {
        let colors = preset.colorSet(for: .light)
        for surface in [colors.backgroundTop, colors.backgroundBottom, colors.panel, colors.input,
                        colors.floatingBar, colors.selectedTab, colors.columnTodo, colors.columnDoing,
                        colors.columnDone, colors.todo, colors.doing, colors.done] {
            #expect(colors.accentForeground.contrastRatio(to: surface) >= 4.5, "\(preset.id)")
        }
        #expect(colors.onAccent.contrastRatio(to: colors.accentFill) >= 4.5)
        #expect(colors.accentFill.contrastRatio(to: colors.panel) >= 3)
        #expect(colors.semanticRed.contrastRatio(to: colors.panel) >= 4.5)
        let channels = [colors.accentForeground.red, colors.accentForeground.green, colors.accentForeground.blue]
        #expect(channels.max()! - channels.min()! >= 0.3, "Accent must retain chroma: \(preset.id)")
        for (appearance, surfaces) in [
            (AppThemeAppearance.light, ["#FFFFFF", "#F2F2F7"]),
            (AppThemeAppearance.dark, ["#000000", "#1C1C1E"])
        ] {
            let accent = colors.accent(forSystemAppearance: appearance)
            for hex in surfaces {
                let surface = ThemeColorToken(hex: hex)
                #expect(accent.contrastRatio(to: surface) >= 4.5)
                let buttonSurface = ThemeColorToken(
                    red: surface.red * 0.82 + accent.red * 0.18,
                    green: surface.green * 0.82 + accent.green * 0.18,
                    blue: surface.blue * 0.82 + accent.blue * 0.18)
                #expect(accent.contrastRatio(to: buttonSurface) >= 4.5)
            }
        }
    }
}

@Test
func calendarCategoryHuesAndStoredColorIdentifiersStayStableAcrossThemes() {
    let expectedIDs = ["blue", "red", "green", "purple", "orange", "teal"]
    #expect(CalendarEventColor.allCases.map(\.rawValue) == expectedIDs)
    // Broad hue ranges validate the meaning of the visible names, not specific hex values.
    let hueRanges: [ClosedRange<Double>] = [200...250, 340...365, 120...170, 260...300, 15...45, 175...199]
    for preset in AppThemePreset.all {
        let colors = preset.colorSet(for: .light)
        #expect(colors.eventPalette.count == expectedIDs.count)
        for (index, color) in colors.eventPalette.enumerated() {
            let maxValue = max(color.red, color.green, color.blue)
            let minValue = min(color.red, color.green, color.blue)
            let delta = maxValue - minValue
            #expect(delta > 0.1)
            let sector: Double
            if maxValue == color.red { sector = (color.green - color.blue) / delta }
            else if maxValue == color.green { sector = (color.blue - color.red) / delta + 2 }
            else { sector = (color.red - color.green) / delta + 4 }
            let hue = (sector * 60 + 360).truncatingRemainder(dividingBy: 360)
            #expect(hueRanges[index].contains(hue), "\(preset.name): \(expectedIDs[index])")
            #expect(colors.resolvedEventForeground(on: color).contrastRatio(to: color) >= 4.5)
            let faded = colors.eventBackground(at: index, isDimmed: true)
            #expect(faded != color)
            #expect(colors.resolvedEventForeground(on: faded).contrastRatio(to: faded) >= 4.5)
        }
        var changed = colors
        changed.accentFill = ThemeColorToken(hex: "#FF00FF")
        #expect(changed.eventPalette == colors.eventPalette)
        #expect(changed.event == colors.event)
        #expect(changed.activityHeatmap != colors.activityHeatmap)
    }
}

@Test
func archiveSemanticColorsRemainReadableAcrossEveryTheme() {
    for preset in AppThemePreset.all {
        for appearance in AppThemeAppearance.allCases {
            let colors = preset.colorSet(for: appearance)
            let essentialSurfaces = [
                colors.backgroundTop,
                colors.backgroundBottom,
                colors.panel,
                colors.input,
                colors.floatingBar,
                colors.selectedTab
            ]

            for surface in essentialSurfaces {
                #expect(colors.primaryText.contrastRatio(to: surface) >= 4.5)
                #expect(colors.secondaryText.contrastRatio(to: surface) >= 4.5)
            }
            #expect(colors.resolvedDoneForeground.contrastRatio(to: colors.done) >= 4.5)
            #expect(colors.resolvedEventForeground.contrastRatio(to: colors.event) >= 4.5)
        }
    }
}

@Test
func fixedThemeStatusColorsRemainDistinctWithinEachPreset() {
    func distance(_ lhs: ThemeColorToken, _ rhs: ThemeColorToken) -> Double {
        let red = lhs.red - rhs.red
        let green = lhs.green - rhs.green
        let blue = lhs.blue - rhs.blue
        return (red * red + green * green + blue * blue).squareRoot()
    }

    for preset in AppThemePreset.all {
        let colors = preset.colorSet(for: .light)

        // Canonical fixed column surfaces are intentionally subtle, while cards
        // carry the stronger state distinction.
        #expect(distance(colors.columnTodo, colors.columnDoing) >= 0.01)
        #expect(distance(colors.columnTodo, colors.columnDone) >= 0.01)
        #expect(distance(colors.columnDoing, colors.columnDone) >= 0.01)
        #expect(distance(colors.todo, colors.doing) >= 0.06)
        #expect(distance(colors.todo, colors.done) >= 0.06)
        #expect(distance(colors.doing, colors.done) >= 0.06)
    }
}
