import os

/// Lightweight intervals for Instruments. No model data is included in the log.
public enum PlanBasePerformanceTrace {
    private static let log = OSLog(
        subsystem: "com.soraul2.easytask.performance",
        category: .pointsOfInterest
    )

    public static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    public static func end(_ name: StaticString, _ id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}
