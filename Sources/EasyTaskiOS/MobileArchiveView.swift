#if os(iOS)
#if !XCODE_APP_BUNDLE
import EasyTaskCore
#endif
import SwiftData
import SwiftUI
import UIKit

struct MobileArchiveView: View {
    var onOpenBoardDate: (Date) -> Void
    @Query private var tasks: [TodoTask]
    @Query private var reviews: [DailyReview]
    @State private var searchText = ""
    @State private var scope: ArchiveScope = .all
    @State private var showingFilter = false

    enum ArchiveScope: String, CaseIterable, Identifiable {
        case all
        case tasks
        case reviews

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "전체"
            case .tasks: "작업"
            case .reviews: "회고"
            }
        }
    }

    struct Group: Identifiable {
        var dayKey: String
        var tasks: [TodoTask]
        var review: DailyReview?
        var id: String { dayKey }
    }

    private var groups: [Group] {
        let completed = tasks.filter { $0.status == TaskStatus.done.rawValue }
        let tasksByDay = Dictionary(grouping: completed, by: { $0.completedDayKey ?? $0.archivedDayKey ?? $0.plannedDayKey })
        let reviewsByDay = Dictionary(grouping: reviews.filter { DailyReviewRules.hasContent($0) }, by: \.dayKey)
            .mapValues { $0.sorted { $0.updatedAt > $1.updatedAt }.first }
        let keys = Set(tasksByDay.keys).union(reviewsByDay.keys)
        return keys
            .sorted(by: >)
            .map { key in
                Group(
                    dayKey: key,
                    tasks: (scope == .reviews ? [] : tasksByDay[key] ?? []).sorted {
                        ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
                    },
                    review: scope == .tasks ? nil : reviewsByDay[key] ?? nil
                )
            }
            .filter(matchesSearch)
            .filter { !$0.tasks.isEmpty || $0.review != nil }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { group in
                    MobileArchiveGroupView(group: group, onOpenBoardDate: onOpenBoardDate)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                if groups.isEmpty {
                    ContentUnavailableView("기록 없음", systemImage: "book.pages")
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "작업, 회고 검색")
            .navigationTitle("기록")
            .toolbar {
                Button { showingFilter = true } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("기록 필터")
            }
            .sheet(isPresented: $showingFilter) {
                ArchiveFilterSheet(scope: $scope, isPresented: $showingFilter)
            }
        }
    }

    private func matchesSearch(_ group: Group) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if group.dayKey.localizedCaseInsensitiveContains(query) { return true }
        if group.review?.title.localizedCaseInsensitiveContains(query) == true { return true }
        if group.review?.weather.localizedCaseInsensitiveContains(query) == true { return true }
        if group.review?.mood.localizedCaseInsensitiveContains(query) == true { return true }
        if group.review?.content.localizedCaseInsensitiveContains(query) == true { return true }
        return group.tasks.contains {
            $0.title.localizedCaseInsensitiveContains(query) ||
                ($0.note?.localizedCaseInsensitiveContains(query) == true)
        }
    }
}

private struct ArchiveFilterSheet: View {
    @Binding var scope: MobileArchiveView.ArchiveScope
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                Picker("검색 대상", selection: $scope) {
                    ForEach(MobileArchiveView.ArchiveScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
            }
            .navigationTitle("검색 필터")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct MobileArchiveGroupView: View {
    var group: MobileArchiveView.Group
    var onOpenBoardDate: (Date) -> Void
    @State private var expandedTasks = false

    private var title: String {
        let reviewTitle = group.review?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !reviewTitle.isEmpty { return reviewTitle }
        return group.review == nil ? "작업 기록" : "하루 회고"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: group.review == nil ? "checkmark.circle" : "book.closed")
                    .foregroundStyle(AppTheme.event)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                    Text(group.dayKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    if let date = DayKey.date(from: group.dayKey) {
                        onOpenBoardDate(date)
                    }
                } label: {
                    Image(systemName: "rectangle.3.group")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("해당 날짜 칸반 열기")
            }

            if let review = group.review {
                if !review.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(review.content)
                        .font(.subheadline)
                        .lineLimit(6)
                }
                if !review.imageFileNames.isEmpty {
                    MobileArchiveImageStrip(fileNames: review.imageFileNames)
                }
            }

            if !group.tasks.isEmpty {
                Button {
                    expandedTasks.toggle()
                } label: {
                    HStack {
                        Label("그날 한 일", systemImage: "checkmark.circle")
                        Text("\(group.tasks.count)")
                        Spacer()
                        Image(systemName: expandedTasks ? "chevron.down" : "chevron.right")
                    }
                    .font(.caption.weight(.bold))
                }
                ForEach(expandedTasks ? group.tasks : Array(group.tasks.prefix(3))) { task in
                    Text(task.title)
                        .font(.caption)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.input, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(14)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct MobileArchiveImageStrip: View {
    var fileNames: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(fileNames, id: \.self) { fileName in
                    MobileArchiveImagePreview(fileName: fileName)
                }
            }
        }
    }
}

private struct MobileArchiveImagePreview: View {
    var fileName: String

    var body: some View {
        if let image = UIImage(contentsOfFile: DiaryImageFileStore.imageURL(
            for: fileName,
            appSupportFolder: MobileImageStorage.appSupportFolder
           ).path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 148, height: 104)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            MobileMissingImagePlaceholder(message: "이미지를 불러올 수 없음", minHeight: 104)
                .frame(width: 148, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
#endif
