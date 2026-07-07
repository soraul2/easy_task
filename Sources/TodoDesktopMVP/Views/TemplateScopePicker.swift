import SwiftUI

struct TemplateScopePicker: View {
    @Binding var scope: TemplateListScope

    var body: some View {
        Picker("템플릿 보기", selection: $scope) {
            ForEach(TemplateListScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
    }
}
