import Foundation
import Testing
@testable import EasyTaskCore

@MainActor
private final class InMemoryThemePreferenceStore: ThemePreferenceCloudStoring {
    var values: [String: Any] = [:]
    var synchronizationCount = 0

    func object(forKey key: String) -> Any? {
        values[key]
    }

    func string(forKey key: String) -> String? {
        values[key] as? String
    }

    func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }

    func synchronize() -> Bool {
        synchronizationCount += 1
        return true
    }
}

@Test
func activityHeatmapEmojiValidationAcceptsOneRenderedEmoji() {
    #expect(ThemePreferenceRules.normalizedEmoji("🌿") == "🌿")
    #expect(ThemePreferenceRules.normalizedEmoji(" 👨‍👩‍👧‍👦 ") == "👨‍👩‍👧‍👦")
    #expect(ThemePreferenceRules.normalizedEmoji("☀️") == "☀️")
    #expect(ThemePreferenceRules.normalizedEmoji("A") == nil)
    #expect(ThemePreferenceRules.normalizedEmoji("🌿🔥") == nil)
    #expect(ThemePreferenceRules.normalizedEmoji("") == nil)
}

@Test @MainActor
func themePreferencesRoundTripBetweenTwoDevicesThroughCloudStore() {
    let cloud = InMemoryThemePreferenceStore()
    let firstLocal = InMemoryThemePreferenceStore()
    let firstDevice = ThemePreferenceStore(
        localStore: firstLocal,
        cloudStore: cloud
    )

    _ = firstDevice.start()
    firstDevice.setSelectedThemeID("forestCream")
    firstDevice.setActivityStyle(.emoji, for: "forestCream")
    #expect(firstDevice.setActivityEmoji("🐢", for: "forestCream"))

    let secondLocal = InMemoryThemePreferenceStore()
    let secondDevice = ThemePreferenceStore(
        localStore: secondLocal,
        cloudStore: cloud
    )
    let selectedThemeID = secondDevice.start()

    #expect(selectedThemeID == "forestCream")
    #expect(secondDevice.activityStyle(for: "forestCream") == .emoji)
    #expect(secondDevice.activityEmoji(for: "forestCream") == "🐢")
    #expect(secondDevice.activityMark(for: "forestCream") == .emoji("🐢"))
    #expect(cloud.synchronizationCount == 2)
}

@Test @MainActor
func externalThemePreferenceChangesUpdateOnlyValidLocalValues() {
    let local = InMemoryThemePreferenceStore()
    let cloud = InMemoryThemePreferenceStore()
    let store = ThemePreferenceStore(localStore: local, cloudStore: cloud)
    _ = store.start()

    let styleKey = ThemePreferenceRules.activityStyleKey(themeID: "navyBlush")
    let emojiKey = ThemePreferenceRules.activityEmojiKey(themeID: "navyBlush")
    cloud.set("navyBlush", forKey: ThemePreferenceRules.selectedThemeCloudKey)
    cloud.set(ActivityHeatmapMarkStyle.emoji.rawValue, forKey: styleKey)
    cloud.set("🧭", forKey: emojiKey)

    let selectedThemeID = store.applyCloudChanges(
        changedKeys: [
            ThemePreferenceRules.selectedThemeCloudKey,
            styleKey,
            emojiKey
        ]
    )

    #expect(selectedThemeID == "navyBlush")
    #expect(store.activityStyle(for: "navyBlush") == .emoji)
    #expect(store.activityEmoji(for: "navyBlush") == "🧭")

    cloud.set("not-a-theme", forKey: ThemePreferenceRules.selectedThemeCloudKey)
    cloud.set("letters", forKey: emojiKey)
    _ = store.applyCloudChanges(
        changedKeys: [ThemePreferenceRules.selectedThemeCloudKey, emojiKey]
    )

    #expect(store.selectedThemeID == "navyBlush")
    #expect(store.activityEmoji(for: "navyBlush") == "🧭")
}
