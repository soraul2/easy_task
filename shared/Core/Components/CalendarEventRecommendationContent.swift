#if os(iOS) || os(macOS)
import SwiftUI

/// Shared presentation; each editor remains responsible for its unsaved draft.
public struct CalendarEventRecommendationContent: View {
    public let session: CalendarEventRecommendationSession
    private let onApply: (CalendarEventRecommendation) -> Void
    private let onReplaceNote: () -> Void
    private let onUndo: () -> Void
    @State private var expandedNoteID: UUID?

    public init(
        session: CalendarEventRecommendationSession,
        onApply: @escaping (CalendarEventRecommendation) -> Void,
        onReplaceNote: @escaping () -> Void,
        onUndo: @escaping () -> Void
    ) {
        self.session = session
        self.onApply = onApply
        self.onReplaceNote = onReplaceNote
        self.onUndo = onUndo
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.isPresented {
                HStack(alignment: .firstTextBaseline) {
                    Text("최근 일정에서 가져오기")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button { session.dismissRecommendations() } label: {
                        Text("닫기")
                            .frame(minWidth: PlanBaseControlMetrics.minimumTargetSize,
                                   minHeight: PlanBaseControlMetrics.minimumTargetSize)
                            .contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        .accessibilityLabel("최근 일정 추천 닫기")
                        .accessibilityIdentifier("event-recommendation-dismiss")
                }
                switch session.state {
                case .loading:
                    ProgressView("최근 일정을 찾고 있어요")
                        .font(.caption)
                        .controlSize(.small)
                case .empty:
                    Text("최근 일정에서 일치하는 항목이 없어요")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        .accessibilityIdentifier("event-recommendation-empty")
                case .failed:
                    Text("최근 일정을 불러오지 못했어요")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        .accessibilityIdentifier("event-recommendation-error")
                    Button("다시 시도") { session.retry() }
                        .buttonStyle(PlanBaseButtonStyle(.secondary))
                        .accessibilityIdentifier("event-recommendation-retry")
                case .results:
                    ForEach(session.recommendations) { recommendation in
                        candidate(recommendation).id(recommendation.id)
                    }
                    #if os(macOS)
                    Text("↑↓로 선택 · Return으로 입력 · Esc로 닫기")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    #endif
                default:
                    EmptyView()
                }
            }
            if let feedback = session.feedback {
                Text(feedback)
                    .font(.caption.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityIdentifier("event-recommendation-feedback")
                if session.lastApplication?.canReplaceNote == true {
                    Button("추천 메모로 바꾸기", action: onReplaceNote)
                        .buttonStyle(PlanBaseButtonStyle(.secondary))
                        .accessibilityIdentifier("event-recommendation-replace-note")
                }
                if session.lastApplication?.canUndo == true {
                    Button("되돌리기", action: onUndo)
                        .buttonStyle(PlanBaseButtonStyle(.secondary))
                        .accessibilityLabel("최근 일정 적용 되돌리기")
                        .accessibilityIdentifier("event-recommendation-undo")
                }
            }
        }
        .foregroundStyle(AppTheme.primaryText)
        .onChange(of: session.recommendations.map(\.id)) { expandedNoteID = nil }
    }

    private func candidate(_ recommendation: CalendarEventRecommendation) -> some View {
        let selected = session.selectedID == recommendation.id
        return VStack(alignment: .leading, spacing: 4) {
            Button { onApply(recommendation) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.title)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recommendation.details)
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                    Text(recommendation.note ?? "메모 없음")
                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .frame(minHeight: PlanBaseControlMetrics.minimumTargetSize)
                .background(selected ? AppTheme.selectedTab : AppTheme.input,
                            in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("event-recommendation-\(recommendation.instanceID.uuidString)")
            .accessibilityLabel("최근 일정 적용. \(recommendation.summary). \(recommendation.note ?? "")")
            .accessibilityHint("제목, 기간, 색상을 입력하고 현재 시작일과 작성한 메모는 유지합니다")
            .accessibilityAddTraits(selected ? .isSelected : [])
            if let note = recommendation.note {
                Button {
                    expandedNoteID = expandedNoteID == recommendation.id ? nil : recommendation.id
                } label: {
                    Text(expandedNoteID == recommendation.id ? "메모 접기" : "메모 전문 보기")
                        .font(.caption)
                        .frame(minHeight: PlanBaseControlMetrics.minimumTargetSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(recommendation.title) 메모 \(expandedNoteID == recommendation.id ? "접기" : "전문 보기")")
                .accessibilityIdentifier("event-recommendation-note-\(recommendation.id.uuidString)")
                if expandedNoteID == recommendation.id {
                    Text(note)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("event-recommendation-full-note")
                }
            }
        }
    }
}
#endif
