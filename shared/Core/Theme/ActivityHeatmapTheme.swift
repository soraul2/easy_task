import SwiftUI

public struct ActivityHeatmapColorTokens: Hashable, Sendable {
    public var empty: ThemeColorToken
    public var level1: ThemeColorToken
    public var level2: ThemeColorToken
    public var level3: ThemeColorToken
    public var level4: ThemeColorToken
    public var streakStroke: ThemeColorToken
    public var todayStroke: ThemeColorToken
    public var selectionStroke: ThemeColorToken
    public var future: ThemeColorToken

    public init(
        empty: ThemeColorToken,
        level1: ThemeColorToken,
        level2: ThemeColorToken,
        level3: ThemeColorToken,
        level4: ThemeColorToken,
        streakStroke: ThemeColorToken,
        todayStroke: ThemeColorToken,
        selectionStroke: ThemeColorToken,
        future: ThemeColorToken
    ) {
        self.empty = empty
        self.level1 = level1
        self.level2 = level2
        self.level3 = level3
        self.level4 = level4
        self.streakStroke = streakStroke
        self.todayStroke = todayStroke
        self.selectionStroke = selectionStroke
        self.future = future
    }

    public var palette: ActivityHeatmapPalette {
        ActivityHeatmapPalette(
            empty: empty.color,
            level1: level1.color,
            level2: level2.color,
            level3: level3.color,
            level4: level4.color,
            streakStroke: streakStroke.color,
            todayStroke: todayStroke.color,
            selectionStroke: selectionStroke.color,
            future: future.color
        )
    }
}

public extension AppThemeColorSet {
    var activityHeatmap: ActivityHeatmapColorTokens {
        let level1 = input.blended(with: event, amount: 0.18)
        let level2 = input.blended(with: event, amount: 0.34)
        let level3 = input.blended(with: event, amount: 0.50)
        let level4 = input.blended(with: event, amount: 0.66)
        let outline = resolvedSemanticForeground(primaryText, on: input)
        return ActivityHeatmapColorTokens(
            empty: input,
            level1: level1,
            level2: level2,
            level3: level3,
            level4: level4,
            streakStroke: outline,
            todayStroke: outline,
            selectionStroke: outline,
            future: panel
        )
    }
}

@MainActor
public extension AppTheme {
    static var activityHeatmapPalette: ActivityHeatmapPalette {
        colors.activityHeatmap.palette
    }
}

private extension ThemeColorToken {
    func blended(with other: ThemeColorToken, amount: Double) -> ThemeColorToken {
        let value = min(max(amount, 0), 1)
        return ThemeColorToken(
            red: red + (other.red - red) * value,
            green: green + (other.green - green) * value,
            blue: blue + (other.blue - blue) * value
        )
    }
}
