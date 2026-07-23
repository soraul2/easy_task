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
func roseLilacThemeUsesRequestedSoftPalette() {
    let preset = AppThemePreset.preset(for: "roseLilac")

    #expect(preset.id == "roseLilac")
    #expect(preset.sourcePaletteHexes == ["#FBEFEF", "#FFE2E2", "#F5CBCB", "#C5B3D3"])
    #expect(!preset.targetsWCAGTextContrast)

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
func lightThemeStatusColorsAreDistinctWithinEachPreset() {
    func distance(_ lhs: ThemeColorToken, _ rhs: ThemeColorToken) -> Double {
        let red = lhs.red - rhs.red
        let green = lhs.green - rhs.green
        let blue = lhs.blue - rhs.blue
        return (red * red + green * green + blue * blue).squareRoot()
    }

    for preset in AppThemePreset.all {
        let colors = preset.colorSet(for: .light)

        #expect(distance(colors.columnTodo, colors.columnDoing) >= 0.06)
        #expect(distance(colors.columnTodo, colors.columnDone) >= 0.06)
        #expect(distance(colors.columnDoing, colors.columnDone) >= 0.06)
        #expect(distance(colors.todo, colors.doing) >= 0.06)
        #expect(distance(colors.todo, colors.done) >= 0.06)
        #expect(distance(colors.doing, colors.done) >= 0.06)
    }
}
