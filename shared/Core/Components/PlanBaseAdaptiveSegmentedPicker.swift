#if os(iOS) || os(macOS)
import SwiftUI

public extension View {
    /// Native segmented labels do not grow to accessibility text sizes.
    func planBaseAdaptiveSegmentedPicker() -> some View {
        modifier(PlanBaseAdaptiveSegmentedPicker())
    }
}

private struct PlanBaseAdaptiveSegmentedPicker: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            content.pickerStyle(.menu)
        } else {
            content.pickerStyle(.segmented)
        }
    }
}
#endif
