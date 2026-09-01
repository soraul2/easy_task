import PlanBaseCore
import SwiftUI

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
        case .memo: "4"
        }
    }
}
