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
        let foreground = resolvedDoneForeground
        let level1 = done.blended(with: foreground, amount: 0.08)
        let level2 = done.blended(with: foreground, amount: 0.18)
        let level3 = done.blended(with: foreground, amount: 0.28)
        let level4 = done.blended(with: foreground, amount: 0.38)
        return ActivityHeatmapColorTokens(
            empty: input,
            level1: level1,
            level2: level2,
            level3: level3,
            level4: level4,
            streakStroke: resolvedSemanticForeground(selectedTab, on: input),
            todayStroke: resolvedSemanticForeground(primaryText, on: input),
            selectionStroke: resolvedSemanticForeground(primaryText, on: input),
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
