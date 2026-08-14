import Testing
@testable import EasyTaskCore

@Test
func activityThemePaletteUsesOrderedThemeAccentBlendsForEveryPreset() {
    for preset in AppThemePreset.all {
        for appearance in AppThemeAppearance.allCases {
            let colors = preset.colorSet(for: appearance)
            let palette = colors.activityHeatmap
            let distances = [
                colorDistance(palette.empty, palette.level1),
                colorDistance(palette.level1, palette.level2),
                colorDistance(palette.level2, palette.level3),
                colorDistance(palette.level3, palette.level4)
            ]

            #expect(distances.allSatisfy { $0 > 0.04 }, "\(preset.id) \(appearance)")
            #expect(palette.empty == colors.input)
            let accentDistances = [
                colorDistance(palette.level1, colors.event),
                colorDistance(palette.level2, colors.event),
                colorDistance(palette.level3, colors.event),
                colorDistance(palette.level4, colors.event)
            ]
            #expect(
                zip(accentDistances, accentDistances.dropFirst()).allSatisfy {
                    $0.0 > $0.1
                },
                "\(preset.id) \(appearance) accent progression"
            )
            #expect(palette.todayStroke.contrastRatio(to: palette.empty) >= 4.5)
            #expect(palette.selectionStroke.contrastRatio(to: palette.empty) >= 4.5)
            let fills = [
                palette.empty,
                palette.level1,
                palette.level2,
                palette.level3,
                palette.level4
            ]
            for fill in fills {
                #expect(
                    palette.streakStroke.contrastRatio(to: fill) >= 3,
                    "\(preset.id) \(appearance) streak"
                )
                #expect(
                    palette.todayStroke.contrastRatio(to: fill) >= 3,
                    "\(preset.id) \(appearance) today"
                )
                #expect(
                    palette.selectionStroke.contrastRatio(to: fill) >= 3,
                    "\(preset.id) \(appearance) selection"
                )
            }
        }
    }
}

private func colorDistance(_ lhs: ThemeColorToken, _ rhs: ThemeColorToken) -> Double {
    let red = lhs.red - rhs.red
    let green = lhs.green - rhs.green
    let blue = lhs.blue - rhs.blue
    return (red * red + green * green + blue * blue).squareRoot()
}
