import Foundation

struct AppearanceThemeCloudSyncResult {
    let message: String
    let didApplyRemoteSettings: Bool
    let didPushLocalSettings: Bool
}

@MainActor
enum AppearanceThemeCloudSync {
    static let enabledKey = "SettingsICloudAppearanceThemeSyncEnabled"
    static let localUpdatedAtKey = "SettingsICloudAppearanceThemeSyncLocalUpdatedAt"
    static let statusKey = "SettingsICloudAppearanceThemeSyncStatus"
    static let lastSyncedAtKey = "SettingsICloudAppearanceThemeSyncLastSyncedAt"

    private static let cloudPrefix = "NVE.AppearanceThemeSettings."
    private static let cloudUpdatedAtKey = "NVE.AppearanceThemeSettings.updatedAt"

    private static let syncedKeys = [
        "SettingsAppearance",
        "EnableTranslucentWindow",
        "SettingsMacTranslucencyMode",
        "SettingsThemeName",
        "SettingsThemeTextColor",
        "SettingsThemeBackgroundColor",
        "SettingsThemeCursorColor",
        "SettingsThemeSelectionColor",
        "SettingsThemeKeywordColor",
        "SettingsThemeStringColor",
        "SettingsThemeNumberColor",
        "SettingsThemeCommentColor",
        "SettingsThemeTypeColor",
        "SettingsThemeBuiltinColor",
        "SavedCustomThemesData",
        "SettingsThemeHexOverrides",
        "SettingsThemeBoldKeywords",
        "SettingsThemeItalicComments",
        "SettingsThemeUnderlineLinks",
        "SettingsThemeBoldMarkdownHeadings",
        "MarkdownPreviewBackgroundStyle"
    ]

    private static let fallbackValues: [String: Any] = [
        "SettingsAppearance": "system",
        "EnableTranslucentWindow": true,
        "SettingsMacTranslucencyMode": "balanced",
        "SettingsThemeName": "Neon Glow",
        "SettingsThemeTextColor": "#EDEDED",
        "SettingsThemeBackgroundColor": "#0E1116",
        "SettingsThemeCursorColor": "#4EA4FF",
        "SettingsThemeSelectionColor": "#2A3340",
        "SettingsThemeKeywordColor": "#F5D90A",
        "SettingsThemeStringColor": "#4EA4FF",
        "SettingsThemeNumberColor": "#FFB86C",
        "SettingsThemeCommentColor": "#7F8C98",
        "SettingsThemeTypeColor": "#32D269",
        "SettingsThemeBuiltinColor": "#EC7887",
        "SavedCustomThemesData": Data(),
        "SettingsThemeHexOverrides": Data(),
        "SettingsThemeBoldKeywords": false,
        "SettingsThemeItalicComments": false,
        "SettingsThemeUnderlineLinks": false,
        "SettingsThemeBoldMarkdownHeadings": false,
        "MarkdownPreviewBackgroundStyle": "automatic"
    ]

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var currentStatus: String {
        UserDefaults.standard.string(forKey: statusKey) ?? "Not synced yet."
    }

    static func setEnabled(_ enabled: Bool) -> AppearanceThemeCloudSyncResult {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        guard enabled else {
            return updateStatus("iCloud sync is off.", didApplyRemoteSettings: false, didPushLocalSettings: false)
        }
        return syncNow()
    }

    static func syncIfEnabled() -> AppearanceThemeCloudSyncResult? {
        guard isEnabled else { return nil }
        return syncNow()
    }

    static func recordLocalChangeAndPush() -> AppearanceThemeCloudSyncResult? {
        guard isEnabled else { return nil }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: localUpdatedAtKey)
        return pushLocalSettings()
    }

    static func syncNow() -> AppearanceThemeCloudSyncResult {
        let defaults = UserDefaults.standard
        let store = NSUbiquitousKeyValueStore.default
        let didReachStore = store.synchronize()

        let localUpdatedAt = defaults.double(forKey: localUpdatedAtKey)
        let cloudUpdatedAt = store.double(forKey: cloudUpdatedAtKey)

        if cloudUpdatedAt > localUpdatedAt {
            return pullRemoteSettings(cloudUpdatedAt: cloudUpdatedAt)
        }

        if localUpdatedAt == 0 {
            defaults.set(Date().timeIntervalSince1970, forKey: localUpdatedAtKey)
        }
        let result = pushLocalSettings()
        if !didReachStore {
            return updateStatus("iCloud sync queued locally; iCloud did not confirm immediately.", didApplyRemoteSettings: result.didApplyRemoteSettings, didPushLocalSettings: result.didPushLocalSettings)
        }
        return result
    }

    static func pullRemoteSettings() -> AppearanceThemeCloudSyncResult {
        let store = NSUbiquitousKeyValueStore.default
        let didReachStore = store.synchronize()
        if !didReachStore {
            return updateStatus("iCloud pull queued locally; iCloud did not confirm immediately.", didApplyRemoteSettings: false, didPushLocalSettings: false)
        }
        return pullRemoteSettings(cloudUpdatedAt: store.double(forKey: cloudUpdatedAtKey))
    }

    static func pushLocalSettings() -> AppearanceThemeCloudSyncResult {
        let defaults = UserDefaults.standard
        let store = NSUbiquitousKeyValueStore.default
        let updatedAt = max(defaults.double(forKey: localUpdatedAtKey), Date().timeIntervalSince1970)
        defaults.set(updatedAt, forKey: localUpdatedAtKey)

        for key in syncedKeys {
            guard let value = defaults.object(forKey: key) ?? fallbackValues[key] else { continue }
            setCloudValue(value, forKey: cloudKey(for: key), in: store)
        }

        store.set(updatedAt, forKey: cloudUpdatedAtKey)
        let didReachStore = store.synchronize()
        guard didReachStore else {
            return updateStatus("iCloud push queued locally; iCloud did not confirm immediately.", didApplyRemoteSettings: false, didPushLocalSettings: true)
        }
        return updateStatus("Appearance and theme settings pushed to iCloud.", didApplyRemoteSettings: false, didPushLocalSettings: true)
    }

    private static func pullRemoteSettings(cloudUpdatedAt: TimeInterval) -> AppearanceThemeCloudSyncResult {
        guard cloudUpdatedAt > 0 else {
            return pushLocalSettings()
        }

        let defaults = UserDefaults.standard
        let store = NSUbiquitousKeyValueStore.default
        var didApplyRemoteSettings = false

        for key in syncedKeys {
            guard let value = store.object(forKey: cloudKey(for: key)) else { continue }
            defaults.set(value, forKey: key)
            didApplyRemoteSettings = true
        }

        defaults.set(cloudUpdatedAt, forKey: localUpdatedAtKey)
        return updateStatus(
            didApplyRemoteSettings ? "Appearance and theme settings updated from iCloud." : "No iCloud appearance or theme settings found.",
            didApplyRemoteSettings: didApplyRemoteSettings,
            didPushLocalSettings: false
        )
    }

    private static func updateStatus(
        _ message: String,
        didApplyRemoteSettings: Bool,
        didPushLocalSettings: Bool
    ) -> AppearanceThemeCloudSyncResult {
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastSyncedAtKey)
        let formattedMessage = "\(message) Last sync: \(DateFormatter.localizedString(from: now, dateStyle: .short, timeStyle: .short))."
        UserDefaults.standard.set(formattedMessage, forKey: statusKey)
        return AppearanceThemeCloudSyncResult(
            message: formattedMessage,
            didApplyRemoteSettings: didApplyRemoteSettings,
            didPushLocalSettings: didPushLocalSettings
        )
    }

    private static func cloudKey(for defaultsKey: String) -> String {
        cloudPrefix + defaultsKey
    }

    private static func setCloudValue(_ value: Any, forKey key: String, in store: NSUbiquitousKeyValueStore) {
        switch value {
        case let string as String:
            store.set(string, forKey: key)
        case let bool as Bool:
            store.set(bool, forKey: key)
        case let int as Int:
            store.set(Int64(int), forKey: key)
        case let double as Double:
            store.set(double, forKey: key)
        case let data as Data:
            store.set(data, forKey: key)
        case let number as NSNumber:
            store.set(number, forKey: key)
        default:
            break
        }
    }
}
