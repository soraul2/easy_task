public struct ArchiveRecordSummary: Equatable, Sendable {
    public var dayCount: Int
    public var reviewCount: Int
    public var completedTaskCount: Int

    public init(
        dayCount: Int,
        reviewCount: Int,
        completedTaskCount: Int
    ) {
        self.dayCount = dayCount
        self.reviewCount = reviewCount
        self.completedTaskCount = completedTaskCount
    }

    public init(records: [ArchiveDayRecord]) {
        dayCount = records.count
        reviewCount = records.lazy.filter { $0.review != nil }.count
        completedTaskCount = records.lazy.reduce(0) { $0 + $1.tasks.count }
    }
}
