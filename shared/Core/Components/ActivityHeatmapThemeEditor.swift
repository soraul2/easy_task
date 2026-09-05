import SwiftUI

public struct ActivityHeatmapThemeEditor: View {
    public var themeID: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var emojiFocused: Bool

    @State private var preferenceStore = ThemePreferenceStore.shared
    @State private var emojiDraft = ""

    private static let suggestions = ["✨", "🌿", "🔥", "🌙", "🌸", "☀️", "🫧", "🐾"]

    public init(themeID: String) {
        self.themeID = themeID
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("활동 그래프")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("완료한 날을 테마 색상이나 나만의 이모지로 표시합니다.")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("표현 방식")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)

                    Picker("표현 방식", selection: styleBinding) {
                        ForEach(ActivityHeatmapMarkStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
#if os(watchOS)
                    .pickerStyle(.navigationLink)
#else
                    .planBaseAdaptiveSegmentedPicker()
#endif
                    .labelsHidden()
                    .accessibilityIdentifier("activity-heatmap-style-picker")
                }

                if currentStyle == .emoji {
                    emojiEditor
                }

                preview

                Label(
                    "같은 iCloud 계정의 Mac, iPhone, iPad에서 이 설정을 함께 사용합니다.",
                    systemImage: "icloud"
                )
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(2)
        }
        .onAppear(perform: reloadDraft)
        .onChange(of: themeID) {
            reloadDraft()
        }
        .onChange(of: preferenceStore.revision) {
            guard !emojiFocused else { return }
            let storedEmoji = preferenceStore.activityEmoji(for: themeID)
            if emojiDraft != storedEmoji {
                emojiDraft = storedEmoji
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { emojiFocused = false }
                    .accessibilityIdentifier("activity-emoji-keyboard-dismiss")
            }
        }
        #endif
    }
}

private extension ActivityHeatmapThemeEditor {
    var currentStyle: ActivityHeatmapMarkStyle {
        preferenceStore.activityStyle(for: themeID)
    }

    var currentMark: ActivityHeatmapMark {
        preferenceStore.activityMark(for: themeID)
    }

    var styleBinding: Binding<ActivityHeatmapMarkStyle> {
        Binding(
            get: { preferenceStore.activityStyle(for: themeID) },
            set: { preferenceStore.setActivityStyle($0, for: themeID) }
        )
    }

    var emojiEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    Text("나의 이모지")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("이모지 하나를 입력하세요")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                if !dynamicTypeSize.isAccessibilitySize { Spacer() }

                TextField("이모지", text: $emojiDraft)
                    .focused($emojiFocused)
                    .font(.system(size: 28))
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
                    .frame(minHeight: PlanBaseControlMetrics.minimumTargetSize)
                    .padding(.vertical, 6)
                    .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                emojiDraft.isEmpty || isDraftValid ? AppTheme.border : Color.red.opacity(0.72),
                                lineWidth: 1
                            )
                    }
                    .onChange(of: emojiDraft) { oldValue, newValue in
                        saveChangedEmoji(from: newValue, replacing: oldValue)
                    }
                    .accessibilityIdentifier("activity-heatmap-emoji-field")

                Button("기본값") {
                    preferenceStore.resetActivityEmoji(for: themeID)
                    reloadDraft()
                }
                .buttonStyle(.bordered)
                .frame(minHeight: PlanBaseControlMetrics.minimumTargetSize)
            }

            if !emojiDraft.isEmpty && !isDraftValid {
                Label("이모지 하나를 입력해 주세요.", systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("activity-emoji-validation")
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Self.suggestions, id: \.self) { emoji in
                        Button {
                            emojiDraft = emoji
                            _ = preferenceStore.setActivityEmoji(emoji, for: themeID)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 22))
                                .frame(width: max(38, PlanBaseControlMetrics.minimumTargetSize),
                                       height: max(36, PlanBaseControlMetrics.minimumTargetSize))
                                .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(
                                            emojiDraft == emoji
                                                ? AppTheme.primaryText.opacity(0.65)
                                                : AppTheme.border,
                                            lineWidth: 1
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(emoji) 이모지 사용")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    var preview: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("미리보기")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            HStack(spacing: 8) {
                ForEach(ActivityIntensityLevel.allCases, id: \.rawValue) { level in
                    ActivityHeatmapMarkSample(
                        level: level,
                        palette: AppTheme.activityHeatmapPalette,
                        mark: currentMark,
                        size: 28
                    )
                }
            }

            HStack(spacing: 5) {
                Text("적음")
                Spacer(minLength: 8)
                Text("많음")
            }
            .font(.caption2)
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: 172)
        }
        .padding(14)
        .background(AppTheme.input.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }

    var isDraftValid: Bool {
        ThemePreferenceRules.normalizedEmoji(emojiDraft) != nil
    }

    func reloadDraft() {
        emojiDraft = preferenceStore.activityEmoji(for: themeID)
    }

    func saveChangedEmoji(from value: String, replacing previousValue: String) {
        guard !value.isEmpty else { return }
        let previousEmoji = ThemePreferenceRules.normalizedEmoji(previousValue)
        let candidates = value.compactMap { character in
            ThemePreferenceRules.normalizedEmoji(String(character))
        }
        // Keep invalid input visible so the user can correct it instead of
        // silently restoring an emoji that was already in the field.
        guard candidates.count == value.count else { return }
        guard let emoji = candidates.last(where: { $0 != previousEmoji })
            ?? candidates.last else {
            return
        }
        if emojiDraft != emoji {
            emojiDraft = emoji
        }
        _ = preferenceStore.setActivityEmoji(emoji, for: themeID)
    }
}
