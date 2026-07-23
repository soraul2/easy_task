import AppKit
import PlanBaseCore
import SwiftUI

struct DailyReviewSheet: View {
    var selectedDate: Date
    @Environment(\.dismiss) private var dismiss
    @State private var hasUnsavedChanges = false
    @State private var isSaving = false
    @State private var showsDiscardConfirmation = false

    private var preferredHeight: CGFloat {
        let availableHeight = NSScreen.main?.visibleFrame.height ?? 820
        return min(max(availableHeight * 0.72, 480), 760)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("취소", action: requestDismiss)
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(width: 150, alignment: .leading)
                    .disabled(isSaving)
                    .keyboardShortcut(.cancelAction)

                Text("회고 작성")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(DayKey.display(selectedDate))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 150, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .frame(height: 58)

            Divider()
                .overlay(AppTheme.border)

            DiaryView(
                initialDate: selectedDate,
                showsHeader: false,
                onDirtyChange: { hasUnsavedChanges = $0 },
                onSavingChange: { isSaving = $0 }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: preferredHeight)
        .background(AppTheme.panel)
        .interactiveDismissDisabled(hasUnsavedChanges || isSaving)
        .alert(
            "변경사항을 버릴까요?",
            isPresented: $showsDiscardConfirmation
        ) {
            Button("변경사항 버리기", role: .destructive) {
                hasUnsavedChanges = false
                dismiss()
            }
            Button("계속 작성", role: .cancel) {}
        } message: {
            Text("저장하지 않은 회고 내용과 이미지 변경사항이 사라집니다.")
        }
    }

    private func requestDismiss() {
        if hasUnsavedChanges {
            showsDiscardConfirmation = true
        } else {
            dismiss()
        }
    }
}
