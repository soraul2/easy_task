#if os(iOS) || os(macOS)
import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Uses the same semibold font as the calendar bars to decide whether a title wraps.
@MainActor
public enum CalendarEventTitleMetrics {
    public static func needsTwoLines(_ title: String, width: CGFloat, fontSize: CGFloat) -> Bool {
        guard width > 0 else { return false }
        return title.contains(where: \.isNewline)
            || (title as NSString).size(withAttributes: [.font: font(size: fontSize)]).width > width
    }

    public static func lineHeight(fontSize: CGFloat) -> CGFloat {
        let font = font(size: fontSize)
        #if os(iOS)
        return ceil(font.lineHeight)
        #else
        return ceil(font.ascender - font.descender + font.leading)
        #endif
    }

    #if os(iOS)
    private static func font(size: CGFloat) -> UIFont {
        .systemFont(ofSize: size, weight: .semibold)
    }
    #else
    private static func font(size: CGFloat) -> NSFont {
        .systemFont(ofSize: size, weight: .semibold)
    }
    #endif
}
#endif
