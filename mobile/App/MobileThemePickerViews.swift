#if os(iOS)
import PlanBaseCore
import SwiftUI

struct MobileThemePickerSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedThemeID: String
    @State private var selectedSection = MobileThemePickerSection.palette

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 12)]
    }

    private var brightPresets: [AppThemePreset] {
        AppThemePreset.all.filter { !$0.isDarkTheme }
    }

    private var darkPresets: [AppThemePreset] {
        AppThemePreset.all.filter(\.isDarkTheme)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("테마 설정", selection: $selectedSection) {
                    ForEach(MobileThemePickerSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .planBaseAdaptiveSegmentedPicker()
                .accessibilityIdentifier("theme-section-picker")
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                switch selectedSection {
                case .palette:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(AppThemePreset.preset(for: selectedThemeID).name, systemImage: AppThemePreset.preset(for: selectedThemeID).isDarkTheme ? "moon.stars.fill" : "sun.max.fill")
                                    .accessibilityIdentifier("theme-current-selection")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.primaryText)

                                Text("선택한 테마의 밝기와 색상은 시스템 모드와 관계없이 동일하게 유지됩니다.")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Label("밝은 테마", systemImage: "sun.max.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.secondaryText)
                            themeGrid(brightPresets)

                            Label("다크 테마", systemImage: "moon.stars.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.secondaryText)
                            themeGrid(darkPresets)
                        }
                        .padding(16)
                    }
                case .activity:
                    ActivityHeatmapThemeEditor(themeID: selectedThemeID)
                        .padding(16)
                }
            }
            .background(AppTheme.background)
            .navigationTitle("테마")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { doneToolbar }
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(AppThemePreset.preset(for: selectedThemeID).preferredColorScheme)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.background)
    }

    @ToolbarContentBuilder
    private var doneToolbar: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) { doneButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) { doneButton }
        }
    }

    private var doneButton: some View {
        Button("완료") { dismiss() }
            .buttonStyle(PlanBaseButtonStyle())
    }

    private func themeGrid(_ presets: [AppThemePreset]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(presets) { preset in
                MobileThemePresetCard(
                    preset: preset,
                    appearance: AppThemeAppearance(colorScheme: colorScheme),
                    isSelected: selectedThemeID == preset.id
                ) {
                    ThemePreferenceStore.shared.setSelectedThemeID(preset.id)
                    AppTheme.activate(preset.id, colorScheme: colorScheme)
                    selectedThemeID = preset.id
                }
            }
        }
    }
}

private enum MobileThemePickerSection: String, CaseIterable, Identifiable {
    case palette
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .palette: "앱 색상"
        case .activity: "활동 그래프"
        }
    }
}

private struct MobileThemePresetCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var preset: AppThemePreset
    var appearance: AppThemeAppearance
    var isSelected: Bool
    var action: () -> Void

    private var colors: AppThemeColorSet {
        preset.colorSet(for: appearance)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text(preset.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(colors.primaryText.color)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? colors.resolvedAccentForeground.color : colors.secondaryText.color)
                }

                ThemePalettePreview(preset: preset)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .background(colors.panel.color, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? colors.resolvedAccentForeground.color : colors.border.color,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("theme-preset-\(preset.id)")
        .accessibilityLabel("\(preset.name) 테마")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "선택됨" : "")
        .accessibilityHint(isSelected ? "현재 적용된 테마" : "두 번 탭하여 테마 적용")
    }

}
#endif
