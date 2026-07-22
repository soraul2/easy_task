#if os(iOS)
import EasyTaskCore
import SwiftUI

struct MobileArchiveFilterSheet: View {
    @Binding var filter: ArchiveFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("기간") {
                    Picker("조회 기간", selection: $filter.period) {
                        ForEach(ArchivePeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }

                    if filter.period == .custom {
                        DatePicker(
                            "시작",
                            selection: $filter.customStartDate,
                            displayedComponents: .date
                        )
                        DatePicker(
                            "종료",
                            selection: $filter.customEndDate,
                            displayedComponents: .date
                        )
                    }
                }
                .listRowBackground(AppTheme.panel)

                Section("검색 대상") {
                    Picker("검색 대상", selection: $filter.scope) {
                        ForEach(ArchiveScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(AppTheme.panel)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .foregroundStyle(AppTheme.primaryText)
            .tint(AppTheme.event)
            .navigationTitle("검색 필터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("초기화") {
                        filter.reset()
                    }
                    .disabled(!filter.hasActiveCriteria)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.background)
    }
}
#endif
