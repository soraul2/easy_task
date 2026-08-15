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
        AppThemePreset.all.contains { $0.id == themeID }
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
        let stored = localStore.string(forKey: AppTheme.storageKey)
        return ThemePreferenceRules.isKnownThemeID(stored ?? "")
            ? stored ?? AppThemePreset.defaultID
            : AppThemePreset.defaultID
    }

    public func setSelectedThemeID(_ themeID: String) {
        guard ThemePreferenceRules.isKnownThemeID(themeID) else { return }
        let changed = localStore.string(forKey: AppTheme.storageKey) != themeID
        localStore.set(themeID, forKey: AppTheme.storageKey)
        if cloudSyncEnabled {
            cloudStore?.set(themeID, forKey: ThemePreferenceRules.selectedThemeCloudKey)
        }
        if changed { revision &+= 1 }
    }

    public func activityStyle(for themeID: String) -> ActivityHeatmapMarkStyle {
        _ = revision
        let key = ThemePreferenceRules.activityStyleKey(themeID: themeID)
        return localStore.string(forKey: key)
            .flatMap(ActivityHeatmapMarkStyle.init(rawValue:)) ?? .color
    }

    public func setActivityStyle(
        _ style: ActivityHeatmapMarkStyle,
        for themeID: String
    ) {
        guard ThemePreferenceRules.isKnownThemeID(themeID) else { return }
        let key = ThemePreferenceRules.activityStyleKey(themeID: themeID)
        let changed = localStore.string(forKey: key) != style.rawValue
        localStore.set(style.rawValue, forKey: key)
        if cloudSyncEnabled {
            cloudStore?.set(style.rawValue, forKey: key)
        }
        if changed { revision &+= 1 }
    }

    public func activityEmoji(for themeID: String) -> String {
        _ = revision
        let key = ThemePreferenceRules.activityEmojiKey(themeID: themeID)
        return ThemePreferenceRules.normalizedEmoji(localStore.string(forKey: key))
            ?? ThemePreferenceRules.defaultEmoji(for: themeID)
    }

    @discardableResult
    public func setActivityEmoji(_ emoji: String, for themeID: String) -> Bool {
        guard ThemePreferenceRules.isKnownThemeID(themeID),
              let normalized = ThemePreferenceRules.normalizedEmoji(emoji) else {
            return false
        }
        let key = ThemePreferenceRules.activityEmojiKey(themeID: themeID)
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
            ThemePreferenceRules.defaultEmoji(for: themeID),
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

        for preset in AppThemePreset.all {
            let styleKey = ThemePreferenceRules.activityStyleKey(themeID: preset.id)
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

            let emojiKey = ThemePreferenceRules.activityEmojiKey(themeID: preset.id)
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

        if didChangeLocalValue { revision &+= 1 }
        return selectedThemeID
    }

    func setLocalValue(_ value: String, key: String) -> Bool {
        guard localStore.string(forKey: key) != value else { return false }
        localStore.set(value, forKey: key)
        return true
    }
}
