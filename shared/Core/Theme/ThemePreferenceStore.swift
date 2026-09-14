import Foundation
import Observation

public enum ActivityHeatmapMarkStyle: String, CaseIterable, Identifiable, Sendable {
    case color
    case emoji

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .color: "테마 색상"
        case .emoji: "이모지"
        }
    }
}

public enum ActivityHeatmapMark: Equatable, Sendable {
    case color
    case emoji(String)
}

public enum ThemePreferenceRules {
    public static let selectedThemeCloudKey = "planbase.theme.selected.v1"
    public static let activityStyleKeyPrefix = "planbase.theme.activity.style.v1."
    public static let activityEmojiKeyPrefix = "planbase.theme.activity.emoji.v1."

    public static func activityStyleKey(themeID: String) -> String {
        activityStyleKeyPrefix + themeID
    }

    public static func activityEmojiKey(themeID: String) -> String {
        activityEmojiKeyPrefix + themeID
    }

    public static func normalizedEmoji(_ candidate: String?) -> String? {
        guard let candidate else { return nil }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let character = trimmed.first else { return nil }
        let scalars = character.unicodeScalars
        let isEmoji = scalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.value == 0xFE0F
        }
        return isEmoji ? String(character) : nil
    }

    public static func defaultEmoji(for themeID: String) -> String {
        switch themeID {
        case "maroonEmber": "🔥"
        case "navyBlush": "🌊"
        case "plumNight": "🌙"
        case "roseLilac": "🌸"
        case "forestCream": "🌿"
        case "tealPaper": "🫧"
        case "solarBerry": "☀️"
        default: "✨"
        }
    }

    public static func isKnownThemeID(_ themeID: String) -> Bool {
        AppThemePreset.canonicalID(for: themeID) != nil
    }
}

@MainActor
public protocol ThemePreferenceValueStoring: AnyObject {
    func object(forKey key: String) -> Any?
    func string(forKey key: String) -> String?
    func set(_ value: Any?, forKey key: String)
}

@MainActor
public protocol ThemePreferenceCloudStoring: ThemePreferenceValueStoring {
    @discardableResult
    func synchronize() -> Bool
}

extension UserDefaults: ThemePreferenceValueStoring {}
extension NSUbiquitousKeyValueStore: ThemePreferenceCloudStoring {}

@Observable
@MainActor
public final class ThemePreferenceStore {
    public static let shared = ThemePreferenceStore()

    public private(set) var revision = 0

    @ObservationIgnored private let localStore: any ThemePreferenceValueStoring
    @ObservationIgnored private let cloudStore: (any ThemePreferenceCloudStoring)?
    @ObservationIgnored private var cloudSyncEnabled = false

    public init(
        localStore: any ThemePreferenceValueStoring = UserDefaults.standard,
        cloudStore: (any ThemePreferenceCloudStoring)? = NSUbiquitousKeyValueStore.default
    ) {
        self.localStore = localStore
        self.cloudStore = cloudStore
    }

    @discardableResult
    public func start(syncsWithICloud: Bool = true) -> String {
        cloudSyncEnabled = syncsWithICloud
        guard syncsWithICloud, let cloudStore else {
            if migrateLegacyPreferences() { revision &+= 1 }
            return selectedThemeID
        }

        _ = cloudStore.synchronize()
        return reconcileFromCloud(changedKeys: nil, seedsMissingValues: true)
    }

    @discardableResult
    public func refreshFromCloud() -> String {
        guard cloudSyncEnabled, let cloudStore else { return selectedThemeID }
        _ = cloudStore.synchronize()
        return reconcileFromCloud(changedKeys: nil, seedsMissingValues: false)
    }

    @discardableResult
    public func applyCloudChanges(changedKeys: [String]?) -> String {
        guard cloudSyncEnabled else { return selectedThemeID }
        return reconcileFromCloud(
            changedKeys: changedKeys.map(Set.init),
            seedsMissingValues: false
        )
    }

    public var selectedThemeID: String {
        AppThemePreset.preset(for: localStore.string(forKey: AppTheme.storageKey)).id
    }

    public func setSelectedThemeID(_ themeID: String) {
        guard let canonical = AppThemePreset.canonicalID(for: themeID) else { return }
        let migrated = migrateLegacyPreferences(preferredID: themeID)
        let changed = setLocalValue(canonical, key: AppTheme.storageKey)
        if cloudSyncEnabled {
            cloudStore?.set(canonical, forKey: ThemePreferenceRules.selectedThemeCloudKey)
            seedMissingCanonicalPreferences()
        }
        if changed || migrated { revision &+= 1 }
    }

    public func activityStyle(for themeID: String) -> ActivityHeatmapMarkStyle {
        _ = revision
        return preferenceSourceIDs(for: themeID).lazy.compactMap { id in
            self.localStore.string(forKey: ThemePreferenceRules.activityStyleKey(themeID: id))
                .flatMap(ActivityHeatmapMarkStyle.init(rawValue:))
        }.first ?? .color
    }

    public func setActivityStyle(
        _ style: ActivityHeatmapMarkStyle,
        for themeID: String
    ) {
        guard let canonical = AppThemePreset.canonicalID(for: themeID) else { return }
        let key = ThemePreferenceRules.activityStyleKey(themeID: canonical)
        let changed = localStore.string(forKey: key) != style.rawValue
        localStore.set(style.rawValue, forKey: key)
        if cloudSyncEnabled {
            cloudStore?.set(style.rawValue, forKey: key)
        }
        if changed { revision &+= 1 }
    }

    public func activityEmoji(for themeID: String) -> String {
        _ = revision
        return preferenceSourceIDs(for: themeID).lazy.compactMap { id in
            ThemePreferenceRules.normalizedEmoji(self.localStore.string(
                forKey: ThemePreferenceRules.activityEmojiKey(themeID: id)))
        }.first ?? ThemePreferenceRules.defaultEmoji(for: AppThemePreset.preset(for: themeID).id)
    }

    @discardableResult
    public func setActivityEmoji(_ emoji: String, for themeID: String) -> Bool {
        guard let canonical = AppThemePreset.canonicalID(for: themeID),
              let normalized = ThemePreferenceRules.normalizedEmoji(emoji) else {
            return false
        }
        let key = ThemePreferenceRules.activityEmojiKey(themeID: canonical)
        let changed = localStore.string(forKey: key) != normalized
        localStore.set(normalized, forKey: key)
        if cloudSyncEnabled {
            cloudStore?.set(normalized, forKey: key)
        }
        if changed { revision &+= 1 }
        return true
    }

    public func resetActivityEmoji(for themeID: String) {
        _ = setActivityEmoji(
            ThemePreferenceRules.defaultEmoji(for: AppThemePreset.preset(for: themeID).id),
            for: themeID
        )
    }

    public func activityMark(for themeID: String) -> ActivityHeatmapMark {
        switch activityStyle(for: themeID) {
        case .color:
            return .color
        case .emoji:
            return .emoji(activityEmoji(for: themeID))
        }
    }
}

private extension ThemePreferenceStore {
    @discardableResult
    func reconcileFromCloud(
        changedKeys: Set<String>?,
        seedsMissingValues: Bool
    ) -> String {
        guard let cloudStore else { return selectedThemeID }
        var didChangeLocalValue = false

        let selectedKey = ThemePreferenceRules.selectedThemeCloudKey
        if changedKeys == nil || changedKeys?.contains(selectedKey) == true {
            if let remoteThemeID = cloudStore.string(forKey: selectedKey),
               ThemePreferenceRules.isKnownThemeID(remoteThemeID) {
                didChangeLocalValue = setLocalValue(
                    remoteThemeID,
                    key: AppTheme.storageKey
                ) || didChangeLocalValue
            } else if seedsMissingValues {
                cloudStore.set(selectedThemeID, forKey: selectedKey)
            }
        }

        // Keep receiving shipped keys from older devices, even when their theme is hidden.
        for id in AppThemePreset.knownIDs {
            let styleKey = ThemePreferenceRules.activityStyleKey(themeID: id)
            if changedKeys == nil || changedKeys?.contains(styleKey) == true {
                if let remoteStyle = cloudStore.string(forKey: styleKey),
                   ActivityHeatmapMarkStyle(rawValue: remoteStyle) != nil {
                    didChangeLocalValue = setLocalValue(
                        remoteStyle,
                        key: styleKey
                    ) || didChangeLocalValue
                } else if seedsMissingValues,
                          let localStyle = localStore.string(forKey: styleKey),
                          ActivityHeatmapMarkStyle(rawValue: localStyle) != nil {
                    cloudStore.set(localStyle, forKey: styleKey)
                }
            }

            let emojiKey = ThemePreferenceRules.activityEmojiKey(themeID: id)
            if changedKeys == nil || changedKeys?.contains(emojiKey) == true {
                if let remoteEmoji = ThemePreferenceRules.normalizedEmoji(
                    cloudStore.string(forKey: emojiKey)
                ) {
                    didChangeLocalValue = setLocalValue(
                        remoteEmoji,
                        key: emojiKey
                    ) || didChangeLocalValue
                } else if seedsMissingValues,
                          let localEmoji = ThemePreferenceRules.normalizedEmoji(
                              localStore.string(forKey: emojiKey)
                          ) {
                    cloudStore.set(localEmoji, forKey: emojiKey)
                }
            }
        }

        didChangeLocalValue = migrateLegacyPreferences() || didChangeLocalValue
        seedMissingCanonicalPreferences()
        if didChangeLocalValue { revision &+= 1 }
        return selectedThemeID
    }

    /// Existing canonical values win per field. Otherwise prefer the selected legacy
    /// theme, then aliases in a stable order. Never delete or overwrite legacy keys.
    func migrateLegacyPreferences(preferredID: String? = nil) -> Bool {
        let selectedRawID = preferredID ?? localStore.string(forKey: AppTheme.storageKey)
        var changed = false
        for preset in AppThemePreset.all {
            let source = AppThemePreset.canonicalID(for: selectedRawID) == preset.id
                ? selectedRawID ?? preset.id : preset.id
            let ids = preferenceSourceIDs(for: source)
            let styleKey = ThemePreferenceRules.activityStyleKey(themeID: preset.id)
            let emojiKey = ThemePreferenceRules.activityEmojiKey(themeID: preset.id)
            let style = ids.lazy.compactMap { id in
                self.localStore.string(forKey: ThemePreferenceRules.activityStyleKey(themeID: id))
                    .flatMap(ActivityHeatmapMarkStyle.init(rawValue:))
            }.first
            let emoji = ids.lazy.compactMap { id in
                ThemePreferenceRules.normalizedEmoji(self.localStore.string(
                    forKey: ThemePreferenceRules.activityEmojiKey(themeID: id)))
            }.first
            // An emoji style without an explicit emoji used the old theme's default.
            // Materialize that value so a selected Sky Blue does not lose its wave.
            let oldEmojiDefault = ids.first { id in
                localStore.string(forKey: ThemePreferenceRules.activityStyleKey(themeID: id))
                    == ActivityHeatmapMarkStyle.emoji.rawValue
            }.map(ThemePreferenceRules.defaultEmoji(for:))
            if let emoji = emoji ?? oldEmojiDefault {
                changed = setLocalValue(emoji, key: emojiKey) || changed
            }
            if let style { changed = setLocalValue(style.rawValue, key: styleKey) || changed }
        }
        let canonical = AppThemePreset.preset(for: selectedRawID).id
        changed = setLocalValue(canonical, key: AppTheme.storageKey) || changed
        return changed
    }

    func preferenceSourceIDs(for themeID: String) -> [String] {
        let canonical = AppThemePreset.preset(for: themeID).id
        let aliases = AppThemePreset.aliases(for: canonical)
        return [canonical] + (aliases.contains(themeID) ? [themeID] : [])
            + aliases.filter { $0 != themeID }
    }

    func seedMissingCanonicalPreferences() {
        guard cloudSyncEnabled, let cloudStore else { return }
        for preset in AppThemePreset.all {
            let styleKey = ThemePreferenceRules.activityStyleKey(themeID: preset.id)
            if cloudStore.string(forKey: styleKey).flatMap(ActivityHeatmapMarkStyle.init(rawValue:)) == nil,
               let style = localStore.string(forKey: styleKey).flatMap(ActivityHeatmapMarkStyle.init(rawValue:)) {
                cloudStore.set(style.rawValue, forKey: styleKey)
            }
            let emojiKey = ThemePreferenceRules.activityEmojiKey(themeID: preset.id)
            if ThemePreferenceRules.normalizedEmoji(cloudStore.string(forKey: emojiKey)) == nil,
               let emoji = ThemePreferenceRules.normalizedEmoji(localStore.string(forKey: emojiKey)) {
                cloudStore.set(emoji, forKey: emojiKey)
            }
        }
    }

    func setLocalValue(_ value: String, key: String) -> Bool {
        guard localStore.string(forKey: key) != value else { return false }
        localStore.set(value, forKey: key)
        return true
    }
}
