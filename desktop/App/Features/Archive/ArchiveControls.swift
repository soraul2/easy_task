import PlanBaseCore
import SwiftUI

struct ArchiveSearchToolbar: View {
    @Binding var text: String
    @Binding var period: ArchivePeriod
    @Binding var scope: ArchiveScope
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var showingFilter: Bool
    @FocusState.Binding var searchFocused: Bool

    private var hasActiveFilterOptions: Bool {
        period != .all || scope != .all
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ArchiveSearchField(text: $text, searchFocused: $searchFocused)

                Button {
                    showingFilter.toggle()
                } label: {
                    Label(
                        "필터",
                        systemImage: hasActiveFilterOptions
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .calendarToolbarButtonBackground()
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingFilter, arrowEdge: .top) {
                    ArchiveFilterPopover(
                        period: $period,
                        scope: $scope,
                        startDate: $startDate,
                        endDate: $endDate
                    )
                }
            }

            if hasActiveFilterOptions {
                HStack(spacing: 8) {
                    if period != .all {
                        ArchiveFilterChip(title: period.title) {
                            period = .all
                        }
                    }
                    if scope != .all {
                        ArchiveFilterChip(title: scope.title) {
                            scope = .all
                        }
                    }
                    Button("모두 지우기") {
                        period = .all
                        scope = .all
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct ArchiveFilterPopover: View {
    @Binding var period: ArchivePeriod
    @Binding var scope: ArchiveScope
    @Binding var startDate: Date
    @Binding var endDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("기록 필터")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                if period != .all || scope != .all {
                    Button("초기화") {
                        period = .all
                        scope = .all
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primaryText)
                }
            }

            FilterPicker(title: "기간") {
                Picker("기간", selection: $period) {
                    ForEach(ArchivePeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }

            FilterPicker(title: "검색 대상") {
                Picker("검색 대상", selection: $scope) {
                    ForEach(ArchiveScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }

            if period == .custom {
                HStack(spacing: 12) {
                    DatePicker("시작", selection: $startDate, displayedComponents: .date)
                    DatePicker("종료", selection: $endDate, displayedComponents: .date)
                }
                .datePickerStyle(.compact)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(18)
        .frame(width: 400)
        .background(AppTheme.panel)
    }
}

private struct ArchiveFilterChip: View {
    var title: String
    var onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(AppTheme.selectedTab, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("\(title) 필터 제거")
    }
}

private struct FilterPicker<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 56, alignment: .leading)
            content
        }
    }
}

private struct ArchiveSearchField: View {
    @Binding var text: String
    @FocusState.Binding var searchFocused: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)

            TextField("작업 제목, 메모, 회고 검색", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.primaryText)
                .focused($searchFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 44)
        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
    }
}

struct ArchiveMessageView: View {
    var message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(AppTheme.secondaryText)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.columnTodo, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border, lineWidth: 1)
            }
    }
}

struct ArchiveSkeletonCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .frame(width: 220, height: 15)
                RoundedRectangle(cornerRadius: 4)
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .frame(width: 360, height: 12)
            }
        }
        .foregroundStyle(AppTheme.input)
        .padding(18)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("기록 불러오는 중")
    }
}
