import PlanBaseCore
import SwiftUI

struct DesktopDiaryWritingPromptPicker: View {
    let content: String
    let onSelect: (DailyReviewWritingPrompt) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("어디서 시작할까요?")
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppTheme.primaryText)

            Text("질문을 고르면 회고에 소제목을 만들어드려요.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(DailyReviewWritingPrompt.allCases) { prompt in
                    let isAdded = DailyReviewWritingRules.contains(prompt, in: content)
                    Button {
                        onSelect(prompt)
                    } label: {
                        Label(
                            prompt.title,
                            systemImage: isAdded ? "checkmark" : "plus"
                        )
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAdded)
                    .accessibilityLabel(
                        isAdded
                            ? "\(prompt.title) 항목 추가됨"
                            : "\(prompt.title) 항목 추가"
                    )
                    .accessibilityHint(
                        isAdded
                            ? ""
                            : "회고 본문에 소제목을 추가하고 입력을 시작합니다"
                    )
                }
            }
        }
        .padding(12)
        .background(AppTheme.input.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .accessibilityIdentifier("desktop-review-writing-prompts")
    }
}
