import Foundation

public enum ArchiveOverviewMode: String, CaseIterable, Identifiable, Sendable {
    case activity
    case statistics

    public nonisolated static let storageKey = "planbase.archiveOverviewMode"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .activity: "활동"
        case .statistics: "통계"
        }
    }
}
