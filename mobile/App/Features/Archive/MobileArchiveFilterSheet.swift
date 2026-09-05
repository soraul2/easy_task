#if os(iOS)
import PlanBaseCore
import SwiftUI

struct MobileArchiveFilterSheet: View {
    @Binding var filter: ArchiveFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("기록 보기") {
                    Picker("기록 보기", selection: $filter.contentMode) {
                        ForEach(ArchiveContentMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .planBaseAdaptiveSegmentedPicker()
                    .accessibilityIdentifier("archive-content-mode-picker")
                    Text(
                        filter.contentMode == .dailyActivity
                            ? "진행·완료·집중 기록이 있는 날을 보여줍니다. 회고는 선택이에요."
                            : "완료한 작업을 선택한 날짜 기준으로 모아봅니다."
                    )
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                }
                .listRowBackground(AppTheme.panel)

                if filter.contentMode == .completionHistory {
                    Section("날짜 기준") {
                        ViewThatFits(in: .horizontal) {
                            Picker("날짜 기준", selection: $filter.dateBasis) {
                                ForEach(TaskHistoryDateBasis.allCases) { basis in
                                    Text(basis.title).tag(basis)
                                }
                            }
                            .planBaseAdaptiveSegmentedPicker()

                            Picker("날짜 기준", selection: $filter.dateBasis) {
                                ForEach(TaskHistoryDateBasis.allCases) { basis in
                                    Text(basis.title).tag(basis)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .accessibilityIdentifier("archive-date-basis-picker")
                    }
                    .listRowBackground(AppTheme.panel)

                }

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
                    .planBaseAdaptiveSegmentedPicker()
                }
                .listRowBackground(AppTheme.panel)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .foregroundStyle(AppTheme.primaryText)
            .tint(AppTheme.accent)
            .navigationTitle("검색 필터")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("초기화") {
                        filter.reset()
                    }
                    .disabled(!filter.hasActiveCriteria && filter.contentMode == .dailyActivity)
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
