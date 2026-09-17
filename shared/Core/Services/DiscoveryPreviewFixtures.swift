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
        context.insert(DailyReview(dayKey: key(-2), mood: "뿌듯함", content: ""))
        let legacy = DailyReview(dayKey: key(-3), content: "")
        context.insert(legacy)
        context.insert(DiaryBlock(reviewId: legacy.id, dayKey: legacy.dayKey, type: .text,
                                  text: "이전 형식으로 남긴 생각도 회고 목록에서 다시 읽을 수 있다.", order: 0))
        context.insert(DailyReview(dayKey: key(-4), content: ""))
        for i in 10..<45 {
            context.insert(DailyReview(dayKey: key(-i), title: "오래된 회고 \(i)", content: "그날의 생각을 한 줄씩 남겼다."))
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
