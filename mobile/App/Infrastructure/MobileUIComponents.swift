#if os(iOS)
import PlanBaseCore
import SwiftUI

typealias TodoTask = Task

enum MobileLayout {
    // System tab bars already contribute their own safe-area inset, including
    // side-mounted bars. Keep only breathing room for the last row.
    static let bottomTabClearance: CGFloat = 20
}

/// One navigation hierarchy for both a list/detail pair and its collapsed form.
/// Changing the available space never creates a second copy of an editor.
struct MobileAdaptiveSplitView<Sidebar: View, Detail: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var minimumColumnWidth = 320.0
    @Binding var compactColumn: NavigationSplitViewColumn
    var sidebarIdealWidth: CGFloat = 360
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail
    @State private var visibility: NavigationSplitViewVisibility = .all

    var body: some View {
        GeometryReader { geometry in
            let idealColumnWidth = max(minimumColumnWidth, sidebarIdealWidth)
            let usesColumns = horizontalSizeClass == .regular
                && !dynamicTypeSize.isAccessibilitySize
                && geometry.size.width >= minimumColumnWidth * 2

            NavigationSplitView(
                columnVisibility: $visibility,
                preferredCompactColumn: $compactColumn
            ) {
                sidebar()
                    .navigationSplitViewColumnWidth(
                        min: minimumColumnWidth,
                        ideal: idealColumnWidth,
                        max: max(idealColumnWidth, geometry.size.width * 0.6)
                    )
            } detail: {
                detail()
            }
            .navigationSplitViewStyle(.balanced)
            .transformEnvironment(\.horizontalSizeClass) { sizeClass in
                // Preserve the system's trait when it already fits. Only
                // constrain regular-width content that cannot fit two columns.
                if !usesColumns, sizeClass == .regular { sizeClass = .compact }
            }
            .onChange(of: usesColumns) { _, expanded in
                if expanded { visibility = .all }
            }
        }
    }
}

#if DEBUG
/// Deterministic resizing of the same view tree in UI tests. This exercises
/// layout/state continuity; it does not simulate Duo hardware or its fold.
struct MobileAdaptiveLayoutTestModifier: ViewModifier {
    @State private var compact = false

    func body(content: Content) -> some View {
        if PlanBaseLaunchEnvironment.isUITesting,
           ProcessInfo.processInfo.arguments.contains("--ui-testing-adaptive-layout") {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    HStack {
                        Button("좁은 테스트 영역") { compact = true }
                            .accessibilityIdentifier("layout-test-compact")
                        Button("넓은 테스트 영역") { compact = false }
                            .accessibilityIdentifier("layout-test-expanded")
                    }
                    .buttonStyle(.bordered)
                    content
                        .frame(width: compact ? min(390, geometry.size.width) : geometry.size.width)
                        .frame(maxHeight: .infinity)
                        .environment(\.horizontalSizeClass, compact ? .compact : .regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            content
        }
    }
}
#endif

enum MobileNoticeTone {
    case success, information, error

    var symbol: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .information: "info.circle.fill"
        case .error: "exclamationmark.circle.fill"
        }
    }
}

struct MobileNoticeBanner: View {
    var message: String
    var tone: MobileNoticeTone = .success

    var body: some View {
        Label {
            Text(message)
                .foregroundStyle(AppTheme.primaryText)
        } icon: {
            Image(systemName: tone.symbol)
                .foregroundStyle(tone == .error ? Color.red : AppTheme.accent)
        }
        .font(.subheadline.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(AppTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .accessibilityValue(tone == .error ? "오류" : "")
        .onAppear { AccessibilityNotification.Announcement(message).post() }
        .onChange(of: message) { _, message in
            AccessibilityNotification.Announcement(message).post()
        }
    }
}

extension View {
    func mobileSavedNotice(_ message: Binding<String?>) -> some View {
        modifier(MobileSavedNoticeModifier(message: message))
    }
}

private struct MobileSavedNoticeModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    MobileNoticeBanner(message: message)
                        .padding(16)
                        .accessibilityIdentifier("review-saved-notice")
                }
            }
            .task(id: message) {
                guard message != nil else { return }
                do { try await _Concurrency.Task.sleep(for: .seconds(4)) }
                catch { return }
                message = nil
            }
    }
}

struct MobileChecklistProgressChip: View {
    var progress: ChecklistProgress

    var body: some View {
        if !progress.isEmpty {
            Label(
                "\(progress.completedCount)/\(progress.totalCount)",
                systemImage: progress.isComplete ? "checkmark.circle.fill" : "checklist"
            )
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(AppTheme.cardMutedText)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(AppTheme.panel.opacity(0.52), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("checklist-progress")
            .accessibilityLabel("체크리스트 진행률")
            .accessibilityValue(
                "\(progress.completedCount)개 완료, 전체 \(progress.totalCount)개"
            )
        }
    }
}

struct MobileThemeButton: View {
    var action: () -> Void
    var minimumHitSize: CGFloat = PlanBaseControlMetrics.minimumTargetSize

    var body: some View {
        Button(action: action) {
            Image(systemName: "paintpalette")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: minimumHitSize, height: minimumHitSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("테마 선택")
        .accessibilityHint("앱 색상 테마 변경")
    }
}
#endif
