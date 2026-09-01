import PlanBaseCore
import SwiftUI

struct ThemeSelectorButton: View {
    @Binding var selectedThemeID: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "paintpalette")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 54, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.primaryText)
        .padding(8)
        .background(AppTheme.floatingBar, in: Capsule())
        .overlay {
            Capsule().stroke(AppTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 8)
        .help("테마 선택")
        .accessibilityLabel("테마 선택")
        .sheet(isPresented: $isPresented) {
            ThemePickerSheet(selectedThemeID: $selectedThemeID)
        }
    }
}

struct ThemePickerSheet: View {
    @Binding var selectedThemeID: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection = ThemePickerSection.palette

    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 12)]

    private var brightPresets: [AppThemePreset] {
        AppThemePreset.all.filter { !$0.isDarkTheme }
    }

    private var darkPresets: [AppThemePreset] {
        AppThemePreset.all.filter(\.isDarkTheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("테마")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("시스템 모드와 무관하게 유지되는 밝은 테마와 다크 테마를 제공합니다.")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.secondaryText)
            }

            Picker("테마 설정", selection: $selectedSection) {
                ForEach(ThemePickerSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 340)

            switch selectedSection {
            case .palette:
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("밝은 테마", systemImage: "sun.max.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.secondaryText)
                        themeGrid(brightPresets)

                        Label("다크 테마", systemImage: "moon.stars.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .padding(.top, 4)
                        themeGrid(darkPresets)
                    }
                    .padding(.vertical, 2)
                }
            case .activity:
                ActivityHeatmapThemeEditor(themeID: selectedThemeID)
            }
        }
        .padding(22)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 480, idealHeight: 560)
        .background(AppTheme.panel)
    }

    private func themeGrid(_ presets: [AppThemePreset]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(presets) { preset in
                ThemePresetCard(preset: preset, isSelected: selectedThemeID == preset.id) {
                    ThemePreferenceStore.shared.setSelectedThemeID(preset.id)
                    AppTheme.activate(preset.id, colorScheme: colorScheme)
                    selectedThemeID = preset.id
                }
            }
        }
    }
}

private enum ThemePickerSection: String, CaseIterable, Identifiable {
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

struct ThemePresetCard: View {
    @Environment(\.colorScheme) private var colorScheme
    var preset: AppThemePreset
    var isSelected: Bool
    var onSelect: () -> Void

    private var colors: AppThemeColorSet {
        preset.colorSet(for: AppThemeAppearance(colorScheme: colorScheme))
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(preset.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(colors.primaryText.color)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(colors.event.color)
                    }
                }

                HStack(spacing: 0) {
                    ForEach(Array(preset.sourceColors.enumerated()), id: \.offset) { _, color in
                        color.frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(colors.border.color.opacity(0.75), lineWidth: 1)
                }

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6).fill(colors.todo.color)
                    RoundedRectangle(cornerRadius: 6).fill(colors.doing.color)
                    RoundedRectangle(cornerRadius: 6).fill(colors.done.color)
                    RoundedRectangle(cornerRadius: 6).fill(colors.event.color)
                }
                .frame(height: 34)

                HStack(spacing: 6) {
                    Text("Aa")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(colors.primaryText.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(colors.panel.color, in: Capsule())
                    Text(preset.targetsWCAGTextContrast ? "WCAG 4.5:1" : "소프트 대비")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colors.secondaryText.color)
                    Spacer()
                }
            }
            .padding(12)
            .background(colors.panel.color, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? colors.event.color : colors.border.color,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.name) 테마")
        .accessibilityValue(isSelected ? "선택됨" : "")
        .accessibilityHint(isSelected ? "현재 적용된 테마" : "두 번 클릭하여 테마 적용")
    }
}
