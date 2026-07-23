enum PlanBaseWidgetSnapshotAvailability: Equatable {
    case available
    case missing
    case corrupt
    case staleCoverage
    case unsupportedNewerSchema

    var calendarMessage: String {
        switch self {
        case .available:
            ""
        case .missing, .corrupt, .staleCoverage:
            "PlanBase를 열면 일정을 갱신해요"
        case .unsupportedNewerSchema:
            "PlanBase를 업데이트해 주세요"
        }
    }
}
