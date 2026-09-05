import SwiftUI

public struct TemplateScopePicker: View {
    @Binding var scope: TemplateListScope

    public init(scope: Binding<TemplateListScope>) {
        _scope = scope
    }

    public var body: some View {
        Picker("템플릿 보기", selection: $scope) {
            ForEach(TemplateListScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
#if os(watchOS)
        .pickerStyle(.navigationLink)
#else
        .planBaseAdaptiveSegmentedPicker()
#endif
        .frame(width: 220)
    }
}
