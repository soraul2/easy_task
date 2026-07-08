import SwiftData
import SwiftUI
import EasyTaskCore

enum AppTab: String, CaseIterable, Identifiable {
    case board
    case calendar
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .board: "칸반보드"
        case .calendar: "캘린더"
        case .archive: "기록"
        }
    }

    var symbol: String {
        switch self {
        case .board: "rectangle.3.group"
        case .calendar: "calendar"
        case .archive: "book.pages"
        }
    }
}

struct AppRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [Task]
    @Query private var events: [CalendarEvent]
    @Query private var templates: [TaskTemplate]
    @Query private var reviews: [DailyReview]

    @State private var selectedTab: AppTab = .board
    @State private var selectedBoardDate = DayKey.startOfDay(for: Date())
    @State private var themeRevision = 0
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppThemePreset.defaultID

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: bottomContentInset)
                }
                .id("\(selectedThemeID)-\(colorScheme)-\(themeRevision)")

            HStack(spacing: 14) {
                FloatingTabBar(selectedTab: $selectedTab)
                ThemeSelectorButton(selectedThemeID: $selectedThemeID)
            }
            .padding(.bottom, 20)
        }
        .background(AppTheme.background)
        .foregroundStyle(AppTheme.primaryText)
        .task {
            let migratedThemeID = AppTheme.migrateStoredDefaultIfNeeded(selectedThemeID)
            if migratedThemeID != selectedThemeID {
                selectedThemeID = migratedThemeID
            }
            AppTheme.activate(migratedThemeID, colorScheme: colorScheme)
            themeRevision += 1
            SeedService.seedIfNeeded(
                context: modelContext,
                tasks: tasks,
                events: events,
                templates: templates,
                reviews: reviews
            )
            TaskRules.archiveIfNeeded(tasks)
        }
        .onChange(of: selectedTab) {
            TaskRules.archiveIfNeeded(tasks)
        }
        .onChange(of: selectedThemeID) {
            AppTheme.activate(selectedThemeID, colorScheme: colorScheme)
            themeRevision += 1
        }
        .onChange(of: colorScheme) {
            AppTheme.activate(selectedThemeID, colorScheme: colorScheme)
            themeRevision += 1
        }
    }

    private var bottomContentInset: CGFloat {
        selectedTab == .calendar ? 0 : 92
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .board:
            BoardView(selectedDate: $selectedBoardDate)
        case .calendar:
            CalendarView()
        case .archive:
            ArchiveView { date in
                selectedBoardDate = date
                selectedTab = .board
            }
        }
    }
}

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

    private let columns = [
        GridItem(.adaptive(minimum: 240), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("테마")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("Apple System과 Color Hunt 기반 테마를 현재 화면 모드에 맞게 보정했습니다.")
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

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(AppThemePreset.all) { preset in
                        ThemePresetCard(
                            preset: preset,
                            isSelected: selectedThemeID == preset.id
                        ) {
                            AppTheme.activate(preset.id, colorScheme: colorScheme)
                            selectedThemeID = preset.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(22)
        .frame(minWidth: 620, idealWidth: 720, minHeight: 480, idealHeight: 560)
        .background(AppTheme.panel)
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
                        .foregroundStyle(AppTheme.primaryText)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.primaryText)
                    }
                }

                HStack(spacing: 0) {
                    ForEach(Array(preset.sourceColors.enumerated()), id: \.offset) { _, color in
                        color
                    }
                }
                .frame(height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 5))

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colors.todo.color)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colors.doing.color)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colors.done.color)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colors.event.color)
                }
                .frame(height: 34)

                HStack(spacing: 6) {
                    Text("Aa")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(colors.primaryText.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(colors.panel.color, in: Capsule())
                    Text("WCAG 4.5:1")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer()
                }
            }
            .padding(12)
            .background(
                isSelected ? AppTheme.selectedTab.opacity(0.30) : AppTheme.input,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? AppTheme.primaryText.opacity(0.55) : AppTheme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 54, height: 44)
                        .background(tab == selectedTab ? AppTheme.selectedTab : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(tab == selectedTab ? AppTheme.primaryText : AppTheme.secondaryText)
                .keyboardShortcut(shortcut(for: tab), modifiers: .command)
                .help(tab.title)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(8)
        .background(AppTheme.floatingBar, in: Capsule())
        .overlay {
            Capsule().stroke(AppTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.42), radius: 18, x: 0, y: 8)
    }

    private func shortcut(for tab: AppTab) -> KeyEquivalent {
        switch tab {
        case .board: "1"
        case .calendar: "2"
        case .archive: "3"
        }
    }
}
