#if DEBUG && !os(watchOS)
import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

/// Opt-in local UI fixtures. Production launch paths never call this service.
public enum DiscoveryPreviewFixtures {
    @MainActor
    public static func seed(in context: ModelContext, arguments: [String] = ProcessInfo.processInfo.arguments) throws {
        guard arguments.contains("--ui-testing"), arguments.contains("--ui-testing-discovery-fixtures") else { return }
        let marker = "작은 진전을 남긴 하루"
        let seededKey = "PlanBaseDiscoveryFixturesSeeded.v1"
        let preferences = PlanBaseLocalPreferences.current
        guard !preferences.bool(forKey: seededKey) else { return }
        // A mutable review title is not a seed marker: editing it must not duplicate fixtures.
        if try context.fetchCount(FetchDescriptor<DailyReview>()) > 0 {
            preferences.set(true, forKey: seededKey)
            return
        }
        let today = DayKey.startOfDay(for: Date())
        func key(_ days: Int) -> String { DayKey.key(for: DayKey.addingDays(days, to: today)) }
        func task(_ title: String, days: Int, order: Double) -> Task {
            let task = Task(title: title, plannedAt: DayKey.addingDays(days, to: today), order: order)
            context.insert(task)
            return task
        }
        let old = [task("읽던 책 이어 읽기", days: -3, order: 100), task("여행 사진 정리하기", days: -2, order: 200)]
        _ = task("새로 이월된 기획안 다듬기", days: -1, order: 300)
        _ = task("새로 이월된 긴 제목의 작업을 큰 글자에서도 빠짐없이 확인하기", days: -1, order: 400)
        _ = task("오늘 문서 초안 작성", days: 0, order: 100)
        _ = task("오늘 산책하기", days: 0, order: 200)
        let finished = task("마친 작업의 활동 기록", days: 0, order: 300)
        try TaskLifecycleService.applyStatus(.done, to: finished, in: context)

        context.insert(DailyReview(dayKey: key(0), title: marker, weather: "맑음", mood: "차분함",
            content: "서두르지 않고 문서의 첫 문단을 완성했다. 작은 진전도 적어 두니 하루가 선명해진다.\n\n점심 뒤에는 동네를 걸으며 떠오른 생각을 정리했다. 내일은 오늘의 초안에서 한 가지를 골라 더 다듬어 보고 싶다."))
        let photoReview = DailyReview(dayKey: key(-1), content: "")
        context.insert(photoReview)
        let photo = try fixtureImage()
        let info = try DiaryAttachmentService.inspect(photo)
        context.insert(DiaryAttachment(reviewId: photoReview.id, order: 0, originalFileName: "discovery-preview.png",
            mimeType: info.mediaType.rawValue, byteCount: info.byteCount, sha256: info.sha256, data: photo))
        if arguments.contains("--ui-testing-long-discovery") {
            let reviews = try context.fetch(FetchDescriptor<DailyReview>())
            if let review = reviews.first(where: { $0.dayKey == key(0) }) {
                review.title = "긴 제목과 여러 사진이 있는 하루의 회고를 목록에서 살펴보고 전체 내용을 읽기"
                review.content = String(repeating: "차분히 하루를 돌아보며 오늘의 생각과 내일의 계획을 기록했다. ", count: 16) + "마지막 문장까지 보존됩니다."
                for index in 0..<3 {
                    context.insert(DiaryAttachment(reviewId: review.id, order: Double(index),
                        originalFileName: "long-preview-\(index).png", mimeType: info.mediaType.rawValue,
                        byteCount: info.byteCount, sha256: info.sha256, data: photo))
                }
            }
            for (name, count) in [("가장 긴 작업 묶음", 8), ("다음 작업 묶음", 2)] {
                let template = TaskTemplate(name: name, isFavorite: true)
                context.insert(template)
                for index in 1...count {
                    context.insert(TaskTemplateItem(templateId: template.id,
                        title: "\(index)번째 작업의 긴 제목을 읽고 해야 할 일과 관련 자료를 차근차근 확인하기",
                        note: "상세에서 확인할 작업 메모", checklistTitles: ["자료 확인", "검토 완료"],
                        order: Double(index) * 100))
                }
            }
        }
        context.insert(DailyReview(dayKey: key(-2), mood: "뿌듯함", content: ""))
        let legacy = DailyReview(dayKey: key(-3), content: "")
        context.insert(legacy)
        context.insert(DiaryBlock(reviewId: legacy.id, dayKey: legacy.dayKey, type: .text,
                                  text: "이전 형식으로 남긴 생각도 회고 목록에서 다시 읽을 수 있다.", order: 0))
        context.insert(DailyReview(dayKey: key(-4), content: ""))
        for i in 10..<45 {
            context.insert(DailyReview(dayKey: key(-i), title: "오래된 회고 \(i)", content: "그날의 생각을 한 줄씩 남겼다."))
        }
        if arguments.contains("--ui-testing-calendar-wrapping") {
            let month = DayKey.startOfMonth(for: today)
            let fixtures: [(String, Int, Int)] = [
                ("프로젝트 기획 검토", 9, 9),
                ("산책", 10, 10),
                ("Product planning review", 11, 11),
                ("가족과 함께하는 주말 나들이 준비", 12, 12),
                ("저녁 약속", 12, 12),
                ("공백없는아주긴일정제목도두줄안에서확인하기", 16, 16),
                ("여러 날에 걸친 프로젝트 일정", 17, 21),
                ("다일 일정 아래의 하루 일정 확인", 18, 18)
            ] + (0..<6).map { ("겹친 일정 \($0 + 1)", 23, 23) }
            for (title, start, end) in fixtures {
                if let event = CalendarEventRules.makeEvent(
                    title: title, startAt: DayKey.addingDays(start - 1, to: month),
                    endAt: DayKey.addingDays(end - 1, to: month)
                ) { context.insert(event) }
            }
        }
        let receipt = CarryoverInboxReceipt(seen: Set(old.map(CarryoverEntryKey.init)))
        PlanBaseLocalPreferences.current.set(try JSONEncoder().encode(receipt), forKey: "PlanBaseCarryoverInboxReceipt.v1")
        try context.save()
        preferences.set(true, forKey: seededKey)
    }

    private static func fixtureImage() throws -> Data {
        enum Failure: Error { case image }
        guard let canvas = CGContext(data: nil, width: 640, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.image }
        canvas.setFillColor(CGColor(red: 0.53, green: 0.73, blue: 0.87, alpha: 1))
        canvas.fill(CGRect(x: 0, y: 0, width: 640, height: 400))
        canvas.setFillColor(CGColor(red: 0.97, green: 0.85, blue: 0.48, alpha: 1))
        canvas.fillEllipse(in: CGRect(x: 440, y: 230, width: 90, height: 90))
        canvas.setFillColor(CGColor(red: 0.31, green: 0.54, blue: 0.43, alpha: 1))
        canvas.fillEllipse(in: CGRect(x: -100, y: -200, width: 650, height: 420))
        canvas.setFillColor(CGColor(red: 0.19, green: 0.40, blue: 0.35, alpha: 1))
        canvas.fillEllipse(in: CGRect(x: 260, y: -220, width: 620, height: 390))
        let data = NSMutableData()
        guard let image = canvas.makeImage(), let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw Failure.image }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.image }
        return data as Data
    }
}
#endif
