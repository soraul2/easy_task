#if os(iOS)
import PlanBaseCore
import SwiftUI

typealias TodoTask = Task

enum MobileLayout {
    static let bottomTabClearance: CGFloat = 96
}

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
