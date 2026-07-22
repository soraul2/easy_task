#if os(iOS)
import PlanBaseCore
import SwiftData
import SwiftUI
import WidgetKit

struct CalendarWidgetSnapshotPublisher: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var events: [CalendarEvent]
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = AppThemePreset.defaultID

    private var eventFingerprint: String {
        events.map { event in
            [
                event.id.uuidString,
                event.title,
                event.startDayKey,
                event.endDayKey,
                event.color ?? "",
                String(event.updatedAt.timeIntervalSinceReferenceDate),
                String(event.supersededAt?.timeIntervalSinceReferenceDate ?? 0)
            ].joined(separator: "|")
        }
        .sorted()
        .joined(separator: ";")
    }

    private var snapshotFingerprint: String {
        "\(selectedThemeID)|\(eventFingerprint)"
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: snapshotFingerprint) {
                publishSnapshot()
            }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                publishSnapshot()
            }
    }

    @MainActor
    private func publishSnapshot() {
        do {
            let snapshot = CalendarWidgetSnapshot.make(
                events: events,
                themeID: selectedThemeID
            )
            if try CalendarWidgetSnapshotStore.writeIfChanged(snapshot) {
                WidgetCenter.shared.reloadTimelines(ofKind: CalendarWidgetConstants.kind)
            }
        } catch {
            print("캘린더 위젯 데이터를 갱신하지 못했습니다: \(error.localizedDescription)")
        }
    }
}
#endif
