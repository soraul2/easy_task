public enum EstimatedTimeFormatter {
    public static func short(_ minutes: Int) -> String {
        if minutes >= 60, minutes % 60 == 0 {
            return "\(minutes / 60)시간"
        }
        if minutes > 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)시간 \(remainingMinutes)분"
        }
        return "\(minutes)분"
    }
}
