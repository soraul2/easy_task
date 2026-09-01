import Foundation
import Testing
@testable import EasyTaskCore

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
    let expectedBackgroundTop: [String: ThemeColorToken] = [
        "appleSystem": ThemeColorToken(hex: "#FFFFFF"),
        "apple2020": ThemeColorToken(hex: "#FFFFFF"),
        "maroonEmber": ThemeColorToken(hex: "#FFFDFC"),
        "navyBlush": ThemeColorToken(hex: "#FCFEFF"),
        "plumNight": ThemeColorToken(hex: "#FFFDFF"),
        "roseLilac": ThemeColorToken(hex: "#FFFDFE"),
        "forestCream": ThemeColorToken(hex: "#FDFFFE"),
        "tealPaper": ThemeColorToken(hex: "#FCFFFF"),
        "solarBerry": ThemeColorToken(hex: "#FFFDF8")
    ]

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
    #expect(preset.sourcePaletteHexes == ["#FFFFFF", "#FFEFF6", "#FFD6E5", "#A94F73"])
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
func apple2020ThemeUsesClassicGroupedSurfacesAndSystemBlue() {
    let preset = AppThemePreset.preset(for: "apple2020")
    let colors = preset.colorSet(for: .light)

    #expect(preset.name == "Apple 2020")
    #expect(colors.backgroundBottom == ThemeColorToken(hex: "#F2F2F7"))
    #expect(colors.panel == ThemeColorToken(hex: "#FFFFFF"))
    #expect(colors.event == ThemeColorToken(hex: "#007AFF"))
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
