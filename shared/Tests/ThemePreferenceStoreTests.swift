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

    #expect(selectedThemeID == "appleSystem")
    #expect(store.activityStyle(for: "navyBlush") == .emoji)
    #expect(store.activityEmoji(for: "navyBlush") == "🧭")

    cloud.set("not-a-theme", forKey: ThemePreferenceRules.selectedThemeCloudKey)
    cloud.set("letters", forKey: emojiKey)
    _ = store.applyCloudChanges(
        changedKeys: [ThemePreferenceRules.selectedThemeCloudKey, emojiKey]
    )

    #expect(store.selectedThemeID == "appleSystem")
    #expect(store.activityEmoji(for: "navyBlush") == "🧭")
}

@Test @MainActor
func legacyThemeMigrationPreservesSelectedAliasSettingsOfflineAndIsIdempotent() {
    let local = InMemoryThemePreferenceStore()
    local.set("navyBlush", forKey: AppTheme.storageKey)
    local.set("emoji", forKey: ThemePreferenceRules.activityStyleKey(themeID: "navyBlush"))
    local.set("🐬", forKey: ThemePreferenceRules.activityEmojiKey(themeID: "navyBlush"))
    local.set("🍎", forKey: ThemePreferenceRules.activityEmojiKey(themeID: "apple2020"))
    let store = ThemePreferenceStore(localStore: local, cloudStore: nil)
    #expect(store.start(syncsWithICloud: false) == "appleSystem")
    #expect(store.activityMark(for: "appleSystem") == .emoji("🐬"))
    #expect(local.string(forKey: ThemePreferenceRules.activityEmojiKey(themeID: "apple2020")) == "🍎")
    #expect(local.string(forKey: ThemePreferenceRules.activityEmojiKey(themeID: "navyBlush")) == "🐬")
    let revision = store.revision
    #expect(store.start(syncsWithICloud: false) == "appleSystem")
    #expect(store.revision == revision)
}

@Test @MainActor
func canonicalThemePreferencesWinConflictsWithoutDeletingLegacyValues() {
    let local = InMemoryThemePreferenceStore()
    local.set("solarBerry", forKey: AppTheme.storageKey)
    local.set("color", forKey: ThemePreferenceRules.activityStyleKey(themeID: "maroonEmber"))
    local.set("🍑", forKey: ThemePreferenceRules.activityEmojiKey(themeID: "maroonEmber"))
    local.set("emoji", forKey: ThemePreferenceRules.activityStyleKey(themeID: "solarBerry"))
    local.set("🌞", forKey: ThemePreferenceRules.activityEmojiKey(themeID: "solarBerry"))
    let store = ThemePreferenceStore(localStore: local, cloudStore: nil)
    #expect(store.start(syncsWithICloud: false) == "maroonEmber")
    #expect(store.activityStyle(for: "solarBerry") == .color)
    #expect(store.activityEmoji(for: "solarBerry") == "🍑")
    #expect(local.string(forKey: ThemePreferenceRules.activityEmojiKey(themeID: "solarBerry")) == "🌞")
}

@Test @MainActor
func legacyDefaultEmojiIsPreservedWhenNoExplicitEmojiWasStored() {
    let local = InMemoryThemePreferenceStore()
    local.set("navyBlush", forKey: AppTheme.storageKey)
    local.set("emoji", forKey: ThemePreferenceRules.activityStyleKey(themeID: "navyBlush"))
    let store = ThemePreferenceStore(localStore: local, cloudStore: nil)
    _ = store.start(syncsWithICloud: false)
    #expect(store.activityMark(for: "appleSystem") == .emoji("🌊"))
}

@Test @MainActor
func legacyCloudPreferencesConvergeAcrossDevicesAndCanonicalEditsWinLater() {
    let cloud = InMemoryThemePreferenceStore()
    cloud.set("solarBerry", forKey: ThemePreferenceRules.selectedThemeCloudKey)
    cloud.set("emoji", forKey: ThemePreferenceRules.activityStyleKey(themeID: "solarBerry"))
    cloud.set("🌻", forKey: ThemePreferenceRules.activityEmojiKey(themeID: "solarBerry"))
    let first = ThemePreferenceStore(localStore: InMemoryThemePreferenceStore(), cloudStore: cloud)
    #expect(first.start() == "maroonEmber")
    #expect(first.activityMark(for: "maroonEmber") == .emoji("🌻"))
    let second = ThemePreferenceStore(localStore: InMemoryThemePreferenceStore(), cloudStore: cloud)
    #expect(second.start() == "maroonEmber")
    #expect(second.activityMark(for: "maroonEmber") == .emoji("🌻"))
    #expect(second.setActivityEmoji("🍊", for: "maroonEmber"))
    _ = first.refreshFromCloud()
    #expect(first.activityEmoji(for: "maroonEmber") == "🍊")
    let oldKey = ThemePreferenceRules.activityEmojiKey(themeID: "solarBerry")
    cloud.set("🌞", forKey: oldKey)
    _ = first.applyCloudChanges(changedKeys: [oldKey])
    #expect(first.activityEmoji(for: "maroonEmber") == "🍊")
}

@Test @MainActor
func invalidCanonicalValuesAllowValidLegacyFallbackAndCanonicalWrites() {
    let local = InMemoryThemePreferenceStore()
    local.set("apple2020", forKey: AppTheme.storageKey)
    local.set("invalid", forKey: ThemePreferenceRules.activityStyleKey(themeID: "appleSystem"))
    local.set("text", forKey: ThemePreferenceRules.activityEmojiKey(themeID: "appleSystem"))
    local.set("emoji", forKey: ThemePreferenceRules.activityStyleKey(themeID: "apple2020"))
    local.set("🍎", forKey: ThemePreferenceRules.activityEmojiKey(themeID: "apple2020"))
    let store = ThemePreferenceStore(localStore: local, cloudStore: nil)
    _ = store.start(syncsWithICloud: false)
    #expect(store.activityMark(for: "appleSystem") == .emoji("🍎"))
    store.setSelectedThemeID("solarBerry")
    #expect(store.selectedThemeID == "maroonEmber")
    #expect(store.setActivityEmoji("🍊", for: "solarBerry"))
    #expect(store.activityEmoji(for: "maroonEmber") == "🍊")
}
