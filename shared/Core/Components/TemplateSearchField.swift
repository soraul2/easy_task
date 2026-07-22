import SwiftUI

public struct TemplateSearchField: View {
    @Binding var text: String

    public init(text: Binding<String>) {
        _text = text
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.secondaryText)

            TextField("템플릿 검색", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(AppTheme.primaryText)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppTheme.secondaryText)
                .help("검색어 지우기")
            }
        }
        .padding(10)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}
