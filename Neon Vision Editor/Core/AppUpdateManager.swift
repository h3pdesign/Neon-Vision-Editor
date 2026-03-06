import Foundation
import SwiftUI
import Combine
import CryptoKit
import os
#if canImport(Security)
import Security
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

enum AppUpdateCheckInterval: String, CaseIterable, Identifiable {
    case hourly = "hourly"
    case daily = "daily"
    case weekly = "weekly"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hourly: return "Hourly"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .hourly: return 3600
        case .daily: return 86400
        case .weekly: return 604800
        }
    }
}

@MainActor
final class AppUpdateManager: ObservableObject {
    enum CheckSource {
        case automatic
        case manual
    }

    enum Status {
        case idle
        case checking
        case updateAvailable
        case upToDate
        case failed
    }

    struct ReleaseInfo: Codable, Equatable {
        let version: String
        let build: String?
        let title: String
        let notes: String
        let publishedAt: Date?
        let releaseURL: URL
        let downloadURL: URL?
        let assetName: String?
        let assetSHA256: String?
    }

    private enum UpdateError: LocalizedError {
        case invalidReleaseSource
        case prereleaseRejected
        case draftRejected
        case rateLimited(until: Date?)
        case missingCachedRelease
        case installUnsupported(String)
        case checksumMissing(String)
        case checksumMismatch
        case invalidCodeSignature
        case noDownloadAsset

        var errorDescription: String? {
            switch self {
            case .invalidReleaseSource:
                return "Release source validation failed."
            case .prereleaseRejected:
                return "Latest GitHub release is marked as prerelease and was skipped."
            case .draftRejected:
                return "Latest GitHub release is a draft and was skipped."
            case .rateLimited(let until):
                if let until {
                    return "GitHub API rate limit reached. Retry after \(until.formatted(date: .abbreviated, time: .shortened))."
                }
                return "GitHub API rate limit reached."
            case .missingCachedRelease:
                return "No cached release metadata found for ETag response."
            case .installUnsupported(let reason):
                return reason
            case .checksumMissing(let asset):
                return "Checksum missing for \(asset)."
            case .checksumMismatch:
                return "Downloaded update checksum does not match release metadata."
            case .invalidCodeSignature:
                return "Downloaded app signature validation failed."
            case .noDownloadAsset:
                return "No downloadable ZIP asset found for this release."
            }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var latestRelease: ReleaseInfo?
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var automaticPromptToken: Int = 0
    @Published private(set) var isInstalling: Bool = false
    @Published private(set) var installMessage: String?
    @Published private(set) var installProgress: Double = 0
    @Published private(set) var installPhase: String = ""
    @Published private(set) var awaitingInstallCompletionAction: Bool = false
    @Published private(set) var preparedUpdateAppURL: URL?
    @Published private(set) var lastCheckResultSummary: String = "Never checked"

    private let owner: String
    private let repo: String
    private let defaults: UserDefaults
    private let session: URLSession
    private let appLaunchDate: Date
    private let downloadService = ReleaseAssetDownloadService()
    private var automaticTask: Task<Void, Never>?
    private var pendingAutomaticPrompt: Bool = false
    private var installDispatchScheduled = false

    let currentVersion: String
    let currentBuild: String?

    static let autoCheckEnabledKey = "SettingsAutoCheckForUpdates"
    static let updateIntervalKey = "SettingsUpdateCheckInterval"
    static let autoDownloadEnabledKey = "SettingsAutoDownloadUpdates"
    static let skippedVersionKey = "SettingsSkippedUpdateVersion"
    static let lastCheckedAtKey = "SettingsLastUpdateCheckAt"
    static let remindUntilKey = "SettingsUpdateRemindUntil"
    static let etagKey = "SettingsUpdateETag"
    static let cachedReleaseKey = "SettingsCachedReleaseInfo"
    static let consecutiveFailuresKey = "SettingsUpdateConsecutiveFailures"
    static let pauseUntilKey = "SettingsUpdatePauseUntil"
    static let lastCheckSummaryKey = "SettingsUpdateLastCheckSummary"
    static let stagedUpdatePathKey = "SettingsStagedUpdatePath"

    private static let minAutoPromptUptime: TimeInterval = 90
    private static let circuitBreakerThreshold = 3
    private static let circuitBreakerPause: TimeInterval = 3600

    init(
        owner: String = "h3pdesign",
        repo: String = "Neon-Vision-Editor",
        defaults: UserDefaults = .standard,
        session: URLSession = .shared
    ) {
        self.owner = owner
        self.repo = repo
        self.defaults = defaults
        self.session = session
        self.appLaunchDate = Date()
        self.currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        let resolvedBuild = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentBuild = (resolvedBuild?.isEmpty == false) ? resolvedBuild : nil

        if let timestamp = defaults.object(forKey: Self.lastCheckedAtKey) as? TimeInterval {
            self.lastCheckedAt = Date(timeIntervalSince1970: timestamp)
        }
        if let summary = defaults.string(forKey: Self.lastCheckSummaryKey), !summary.isEmpty {
            self.lastCheckResultSummary = summary
        }
        if Self.isDevelopmentRuntime {
            // Prevent persisted settings from triggering relaunch/install loops during local debugging.
            defaults.set(false, forKey: Self.autoDownloadEnabledKey)
        }
    }

    var autoCheckEnabled: Bool {
        defaults.object(forKey: Self.autoCheckEnabledKey) as? Bool ?? true
    }

    var autoDownloadEnabled: Bool {
        defaults.object(forKey: Self.autoDownloadEnabledKey) as? Bool ?? false
    }

    var updateInterval: AppUpdateCheckInterval {
        let raw = defaults.string(forKey: Self.updateIntervalKey) ?? AppUpdateCheckInterval.daily.rawValue
        return AppUpdateCheckInterval(rawValue: raw) ?? .daily
    }

    var pausedUntil: Date? {
        guard let ts = defaults.object(forKey: Self.pauseUntilKey) as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    var consecutiveFailureCount: Int {
        defaults.object(forKey: Self.consecutiveFailuresKey) as? Int ?? 0
    }

    func setAutoCheckEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.autoCheckEnabledKey)
        rescheduleAutomaticChecks()
    }

    func setAutoDownloadEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.autoDownloadEnabledKey)
    }

    func setUpdateInterval(_ interval: AppUpdateCheckInterval) {
        defaults.set(interval.rawValue, forKey: Self.updateIntervalKey)
        rescheduleAutomaticChecks()
    }

    func startAutomaticChecks() {
        guard ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution else { return }
        rescheduleAutomaticChecks()

        guard autoCheckEnabled else { return }
        if shouldRunInitialCheckNow() {
            Task { await checkForUpdates(source: .automatic) }
        }
    }

    func checkForUpdates(source: CheckSource) async {
        guard ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution else {
            status = .idle
            errorMessage = nil
            return
        }
        guard status != .checking else { return }

        if source == .automatic,
           let pausedUntil,
           pausedUntil > Date() {
            // Respect circuit-breaker/rate-limit pause windows for background checks.
            updateLastSummary("Auto-check paused until \(pausedUntil.formatted(date: .abbreviated, time: .shortened))")
            return
        }

        status = .checking
        errorMessage = nil

        do {
            let release = try await fetchLatestRelease()
            let now = Date()
            lastCheckedAt = now
            defaults.set(now.timeIntervalSince1970, forKey: Self.lastCheckedAtKey)
            defaults.set(0, forKey: Self.consecutiveFailuresKey)
            defaults.removeObject(forKey: Self.pauseUntilKey)

            if Self.compareReleaseToCurrent(
                releaseVersion: release.version,
                releaseBuild: release.build,
                currentVersion: currentVersion,
                currentBuild: currentBuild
            ) == .orderedDescending {
                latestRelease = release
                status = .updateAvailable
                installMessage = nil
                let releaseLabel = Self.releaseTrackingIdentifier(version: release.version, build: release.build)
                updateLastSummary("Update available: \(releaseLabel)")

                if source == .automatic,
                   shouldAutoPrompt(for: release.version, build: release.build) {
                    // Keep install user-driven to avoid replacing app bundles in background.
                    pendingAutomaticPrompt = true
                    automaticPromptToken &+= 1
                }

                if source == .automatic,
                   autoDownloadEnabled,
                   installNowSupported {
                    Task { [weak self] in
                        await self?.attemptAutoInstall(interactive: false)
                    }
                }
            } else {
                latestRelease = nil
                status = .upToDate
                updateLastSummary("Up to date")
            }
        } catch {
            latestRelease = nil
            status = .failed
            errorMessage = error.localizedDescription
            if case let UpdateError.rateLimited(until) = error, let until, until > Date() {
                // Use GitHub-provided reset time when available.
                defaults.set(until.timeIntervalSince1970, forKey: Self.pauseUntilKey)
                updateLastSummary("Rate limited by GitHub. Auto-check paused until \(until.formatted(date: .abbreviated, time: .shortened)).")
            } else {
                let failures = (defaults.object(forKey: Self.consecutiveFailuresKey) as? Int ?? 0) + 1
                defaults.set(failures, forKey: Self.consecutiveFailuresKey)

                if failures >= Self.circuitBreakerThreshold {
                    let until = Date().addingTimeInterval(Self.circuitBreakerPause)
                    defaults.set(until.timeIntervalSince1970, forKey: Self.pauseUntilKey)
                    updateLastSummary("Checks paused after \(failures) failures (until \(until.formatted(date: .abbreviated, time: .shortened))).")
                } else {
                    updateLastSummary("Update check failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func consumeAutomaticPromptIfNeeded() -> Bool {
        guard pendingAutomaticPrompt else { return false }
        pendingAutomaticPrompt = false
        return true
    }

    func skipCurrentVersion() {
        guard let release = latestRelease else { return }
        let skipIdentifier = Self.releaseTrackingIdentifier(version: release.version, build: release.build)
        defaults.set(skipIdentifier, forKey: Self.skippedVersionKey)
    }

    func remindMeTomorrow() {
        let until = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86400)
        defaults.set(until.timeIntervalSince1970, forKey: Self.remindUntilKey)
    }

    func clearSkippedVersion() {
        defaults.removeObject(forKey: Self.skippedVersionKey)
    }

    func openDownloadPage() {
        guard let release = latestRelease else { return }
        openURL(release.downloadURL ?? release.releaseURL)
    }

    func openReleasePage() {
        if let release = latestRelease {
            openURL(release.releaseURL)
            return
        }
        guard let url = URL(string: "https://github.com/\(owner)/\(repo)/releases") else { return }
        openURL(url)
    }

    var updaterLogFileURL: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        return library.appendingPathComponent("Logs/NeonVisionEditorUpdater.log")
    }

    private var updaterLogFileCandidates: [URL] {
        var urls: [URL] = [updaterLogFileURL]
        // Legacy/non-sandbox fallback for older builds.
        urls.append(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/NeonVisionEditorUpdater.log"))
        // Typical sandbox container path fallback.
        let userHome = NSHomeDirectory()
        let containerPath = "\(userHome)/Library/Containers/h3p.Neon-Vision-Editor/Data/Library/Logs/NeonVisionEditorUpdater.log"
        urls.append(URL(fileURLWithPath: containerPath))
        // Keep order stable and unique.
        var unique: [URL] = []
        for url in urls where !unique.contains(url) {
            unique.append(url)
        }
        return unique
    }

    func openUpdaterLog() {
#if os(macOS)
        let fm = FileManager.default
        if let existing = updaterLogFileCandidates.first(where: { fm.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.open(existing)
            return
        }
        let logURL = updaterLogFileURL
        do {
            try fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bootstrap = "[\(ISO8601DateFormatter().string(from: Date()))] Updater log initialized.\n"
            try bootstrap.write(to: logURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(logURL)
        } catch {
            installMessage = "Updater log not found yet at \(logURL.path)."
        }
#endif
    }

    func clearInstallMessage() {
        installMessage = nil
        installProgress = 0
        installPhase = ""
        awaitingInstallCompletionAction = false
        preparedUpdateAppURL = nil
        installDispatchScheduled = false
    }

    func installUpdateNow() async {
        if let reason = installNowDisabledReason {
            installMessage = reason
            return
        }
        await attemptAutoInstall(interactive: true)
    }

    var installNowSupported: Bool {
        installNowDisabledReason == nil
    }

    var installNowDisabledReason: String? {
        guard ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution else {
            return "Updater is disabled for this distribution channel."
        }
        guard !Self.isDevelopmentRuntime else {
            return "Install is unavailable in Xcode/DerivedData runs."
        }
#if os(macOS)
        guard let release = latestRelease else {
            return "No update metadata loaded yet."
        }
        guard release.downloadURL != nil, release.assetName != nil else {
            return "This release does not provide a supported ZIP asset for automatic install."
        }
#endif
        return nil
    }

    func installAndCloseApp() {
        completeInstalledUpdate(restart: false)
    }

    func restartAndInstall() {
        completeInstalledUpdate(restart: true)
    }

    func applicationWillTerminate() {
#if os(macOS)
        guard awaitingInstallCompletionAction else { return }
        _ = launchBackgroundInstaller(relaunch: false)
#endif
    }

    func dismissPreparedUpdatePrompt() {
        awaitingInstallCompletionAction = false
    }

    func completeInstalledUpdate(restart: Bool) {
#if os(macOS)
        if awaitingInstallCompletionAction {
            if requiresPrivilegedInstall,
               !requestInstallerAuthorizationPrompt() {
                return
            }
            guard launchBackgroundInstaller(relaunch: restart) else { return }
            installMessage = restart
                ? "Installing update in background. App will restart after install."
                : "Installing update in background. App will close when install starts."
            NSApp.terminate(nil)
            return
        }
        guard restart else { return }
        let currentApp = Bundle.main.bundleURL.standardizedFileURL
        NSWorkspace.shared.openApplication(at: currentApp, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        NSApp.terminate(nil)
#else
        installMessage = "Automatic install is supported on macOS only."
#endif
    }

#if os(macOS)
    private var requiresPrivilegedInstall: Bool {
        let fm = FileManager.default
        let targetAppURL = Bundle.main.bundleURL.standardizedFileURL
        let destinationDir = targetAppURL.deletingLastPathComponent()
        let destinationWritable = fm.isWritableFile(atPath: destinationDir.path)
        let appBundleWritable = fm.isWritableFile(atPath: targetAppURL.path)
        let appBundleDeletable = fm.isDeletableFile(atPath: targetAppURL.path)
        return !(destinationWritable && (appBundleWritable || appBundleDeletable))
    }

    private func requestInstallerAuthorizationPrompt() -> Bool {
        do {
            let process = Process()
            let stderrPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "do shell script \"/usr/bin/true\" with administrator privileges"]
            process.standardError = stderrPipe
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return true
            }
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if stderrText.localizedCaseInsensitiveContains("User canceled")
                || stderrText.localizedCaseInsensitiveContains("cancelled") {
                installMessage = "Install cancelled. Administrator permission was not granted."
            } else if stderrText.contains("-60005")
                || stderrText.localizedCaseInsensitiveContains("password")
                || stderrText.localizedCaseInsensitiveContains("administrator") {
                installMessage = "Administrator authentication failed. Please retry and enter your macOS admin password."
            } else if !stderrText.isEmpty {
                installMessage = "Failed to verify administrator permission: \(stderrText)"
            } else {
                installMessage = "Failed to verify administrator permission (exit code \(process.terminationStatus))."
            }
            return false
        } catch {
            installMessage = "Failed to request administrator permission: \(error.localizedDescription)"
            return false
        }
    }
#endif

    private func shouldRunInitialCheckNow() -> Bool {
        guard let lastCheckedAt else { return true }
        return Date().timeIntervalSince(lastCheckedAt) >= updateInterval.seconds
    }

    private func shouldAutoPrompt(for version: String, build: String?) -> Bool {
        let identifier = Self.releaseTrackingIdentifier(version: version, build: build)
        if defaults.string(forKey: Self.skippedVersionKey) == identifier { return false }
        if let remindTS = defaults.object(forKey: Self.remindUntilKey) as? TimeInterval,
           Date(timeIntervalSince1970: remindTS) > Date() {
            return false
        }
        let uptime = Date().timeIntervalSince(appLaunchDate)
        return uptime >= Self.minAutoPromptUptime
    }

    private func rescheduleAutomaticChecks() {
        automaticTask?.cancel()
        automaticTask = nil

        guard autoCheckEnabled else { return }
        let intervalSeconds = updateInterval.seconds

        automaticTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let nanos = UInt64(intervalSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                if Task.isCancelled { break }
                await self.checkForUpdates(source: .automatic)
            }
        }
    }

    private func updateLastSummary(_ summary: String) {
        lastCheckResultSummary = summary
        defaults.set(summary, forKey: Self.lastCheckSummaryKey)
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo {
        let endpoint = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NeonVisionEditorUpdater", forHTTPHeaderField: "User-Agent")
        if let etag = defaults.string(forKey: Self.etagKey), !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 304 {
            // ETag hit: reuse previously cached release payload.
            if let cached = cachedReleaseInfo() {
                return cached
            }
            throw UpdateError.missingCachedRelease
        }

        if http.statusCode == 403,
           (http.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "") == "0" {
            let until = Self.rateLimitResetDate(from: http)
            throw UpdateError.rateLimited(until: until)
        }

        guard 200..<300 ~= http.statusCode else {
            throw NSError(
                domain: "AppUpdater",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "GitHub update check failed (HTTP \(http.statusCode))."]
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(GitHubReleasePayload.self, from: data)

        // Enforce repository identity from API payload before using any release data.
        if let apiURL = payload.apiURL,
           !Self.matchesExpectedRepository(url: apiURL, expectedOwner: owner, expectedRepo: repo) {
            throw UpdateError.invalidReleaseSource
        }
        guard !payload.draft else { throw UpdateError.draftRejected }
        guard !payload.prerelease else { throw UpdateError.prereleaseRejected }

        guard let releaseURL = URL(string: payload.htmlURL),
              isTrustedGitHubURL(releaseURL),
              Self.matchesExpectedRepository(url: releaseURL, expectedOwner: owner, expectedRepo: repo) else {
            throw UpdateError.invalidReleaseSource
        }

        let selectedAsset = preferredAsset(from: payload.assets)

        let release = ReleaseInfo(
            version: Self.normalizedVersion(from: payload.tagName),
            build: Self.inferredBuildNumber(tag: payload.tagName, name: payload.name, notes: payload.body).map(String.init),
            title: payload.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? (payload.name ?? payload.tagName)
                : payload.tagName,
            notes: payload.body ?? "",
            publishedAt: payload.publishedAt,
            releaseURL: releaseURL,
            downloadURL: selectedAsset?.url,
            assetName: selectedAsset?.name,
            assetSHA256: selectedAsset?.sha256
        )

        if let etag = http.value(forHTTPHeaderField: "ETag"), !etag.isEmpty {
            defaults.set(etag, forKey: Self.etagKey)
        }
        persistCachedReleaseInfo(release)

        return release
    }

    private func selectedAssetName(from assets: [GitHubAssetPayload]) -> String? {
        let names = assets.map { $0.name }
        return Self.selectPreferredAssetName(from: names)
    }

    private func preferredAsset(from assets: [GitHubAssetPayload]) -> (url: URL, name: String, sha256: String?)? {
        guard let selectedName = selectedAssetName(from: assets),
              let asset = assets.first(where: { $0.name == selectedName }),
              let url = URL(string: asset.browserDownloadURL),
              isTrustedGitHubURL(url),
              Self.matchesExpectedAssetURL(url: url, expectedOwner: owner, expectedRepo: repo) else {
            return nil
        }
        let sha256 = Self.sha256FromAssetDigest(asset.digest)
        return (url: url, name: selectedName, sha256: sha256)
    }

    private func cachedReleaseInfo() -> ReleaseInfo? {
        guard let data = defaults.data(forKey: Self.cachedReleaseKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ReleaseInfo.self, from: data)
    }

    private func persistCachedReleaseInfo(_ release: ReleaseInfo) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(release) {
            defaults.set(data, forKey: Self.cachedReleaseKey)
        }
    }

    private func attemptAutoInstall(interactive: Bool) async {
#if os(macOS)
        guard !isInstalling else { return }
        guard let release = latestRelease else { return }
        guard let downloadURL = release.downloadURL else {
            installMessage = UpdateError.noDownloadAsset.localizedDescription
            return
        }
        guard let assetName = release.assetName else {
            installMessage = UpdateError.noDownloadAsset.localizedDescription
            return
        }

        isInstalling = true
        installProgress = 0.01
        installPhase = "Preparing installer…"
        awaitingInstallCompletionAction = false
        defer { isInstalling = false }

        do {
            // Defense-in-depth:
            // 1) verify artifact checksum from release metadata
            // 2) verify code signature validity + signing identity
            let expectedHash = try Self.resolveExpectedSHA256(
                assetSHA256: release.assetSHA256,
                notes: release.notes,
                preferredAssetName: assetName
            )
            installProgress = 0.12
            installPhase = "Downloading release asset…"
            let manager = self
            let (tmpURL, response) = try await downloadService.download(from: downloadURL, retryNotice: { attempt, waitSeconds, usingResumeData in
                Task { @MainActor in
                    let waitLabel = String(format: "%.1f", waitSeconds)
                    manager.installPhase = usingResumeData
                        ? "Connection interrupted. Resuming download (attempt \(attempt)) in \(waitLabel)s…"
                        : "Connection interrupted. Retrying download (attempt \(attempt)) in \(waitLabel)s…"
                }
            }) { fraction in
                Task { @MainActor in
                    let clamped = min(max(fraction, 0), 1)
                    manager.installProgress = 0.12 + (clamped * 0.28)
                }
            }
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw URLError(.badServerResponse)
            }

            installProgress = 0.40
            installPhase = "Verifying checksum…"
            let actualHash = try Self.sha256Hex(of: tmpURL)
            guard actualHash.caseInsensitiveCompare(expectedHash) == .orderedSame else {
                throw UpdateError.checksumMismatch
            }

            let fileManager = FileManager.default
            let workDir = fileManager.temporaryDirectory.appendingPathComponent("nve-update-\(UUID().uuidString)", isDirectory: true)
            let unzipDir = workDir.appendingPathComponent("unzipped", isDirectory: true)
            try fileManager.createDirectory(at: unzipDir, withIntermediateDirectories: true)

            let downloadedZip = workDir.appendingPathComponent(assetName)
            try fileManager.moveItem(at: tmpURL, to: downloadedZip)

            installProgress = 0.56
            installPhase = "Unpacking update…"
            let unzipStatus = try Self.unzip(zipURL: downloadedZip, to: unzipDir)
            guard unzipStatus == 0 else {
                throw UpdateError.installUnsupported("Failed to unpack update archive.")
            }

            guard let appBundle = Self.findFirstAppBundle(in: unzipDir) else {
                throw UpdateError.installUnsupported("No .app bundle found in downloaded update.")
            }
            installProgress = 0.70
            installPhase = "Verifying app signature…"
            guard try Self.verifyCodeSignatureStrictCLI(of: appBundle) else {
                throw UpdateError.invalidCodeSignature
            }
            // Require the downloaded app to match current Team ID and bundle identifier.
            guard try Self.verifyCodeSignatureStrictCLI(of: Bundle.main.bundleURL) else {
                throw UpdateError.installUnsupported("Current app signature is invalid. Reinstall the app manually before auto-install updates.")
            }
            guard let expectedTeamID = try Self.readTeamIdentifier(of: Bundle.main.bundleURL) else {
                throw UpdateError.installUnsupported("Could not determine local signing team. Use Download Update for manual install.")
            }
            guard try Self.verifyCodeSignature(
                of: appBundle,
                expectedTeamID: expectedTeamID,
                expectedBundleID: Bundle.main.bundleIdentifier
            ) else {
                throw UpdateError.invalidCodeSignature
            }

            installProgress = 0.88
            installPhase = "Staging update…"
            let stagedAppURL = try Self.stagePreparedAppBundle(appBundle, version: release.version)
            preparedUpdateAppURL = stagedAppURL
            defaults.set(stagedAppURL.path, forKey: Self.stagedUpdatePathKey)
            installProgress = 1.0
            installPhase = "Ready to install on app close."
            awaitingInstallCompletionAction = true
            installDispatchScheduled = false
            if interactive {
                installMessage = "Download complete. Update is staged and will install in the background when the app closes."
            } else {
                installMessage = "Update staged. It will install in the background on next app close."
            }
        } catch {
            installProgress = 0
            installPhase = ""
            preparedUpdateAppURL = nil
            installDispatchScheduled = false
            installMessage = error.localizedDescription
        }
#else
        installMessage = "Automatic install is supported on macOS only."
#endif
    }

#if os(macOS)
    private func launchBackgroundInstaller(relaunch: Bool) -> Bool {
        guard awaitingInstallCompletionAction else { return false }
        guard !installDispatchScheduled else { return true }
        guard let stagedUpdateURL = preparedUpdateAppURL else {
            installMessage = "No staged update found. Download and verify the update again."
            return false
        }

        let targetAppURL = Bundle.main.bundleURL.standardizedFileURL

        do {
            let helperScriptURL = try Self.writeInstallerScript(
                sourceAppURL: stagedUpdateURL,
                destinationAppURL: targetAppURL,
                appPID: ProcessInfo.processInfo.processIdentifier,
                relaunchAfterInstall: relaunch,
                expectedVersion: Self.readBundleShortVersionString(of: stagedUpdateURL)
            )
            if !requiresPrivilegedInstall {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = [helperScriptURL.path]
                try process.run()
            } else {
                // Fallback for app locations that require elevated rights (e.g. /Applications).
                let scriptPath = helperScriptURL.path.replacingOccurrences(of: "\"", with: "\\\"")
                let appleScript = "do shell script \"/usr/bin/nohup /bin/sh \" & quoted form of \"\(scriptPath)\" & \" >/dev/null 2>&1 &\" with administrator privileges"
                let process = Process()
                let stderrPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", appleScript]
                process.standardError = stderrPipe
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrText = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if stderrText.localizedCaseInsensitiveContains("User canceled") || stderrText.localizedCaseInsensitiveContains("cancelled") {
                        installMessage = "Install cancelled. Administrator permission was not granted."
                    } else if !stderrText.isEmpty {
                        installMessage = "Failed to start privileged installer: \(stderrText)"
                    } else {
                        installMessage = "Failed to start privileged installer (exit code \(process.terminationStatus))."
                    }
                    return false
                }
            }
            installDispatchScheduled = true
            return true
        } catch {
            installMessage = "Failed to start background installer: \(error.localizedDescription)"
            return false
        }
    }

    private nonisolated static func stagePreparedAppBundle(_ appBundle: URL, version: String) throws -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let root = appSupport
            .appendingPathComponent("NeonVisionEditor", isDirectory: true)
            .appendingPathComponent("Updater", isDirectory: true)
            .appendingPathComponent("Staged", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        // Keep only one staged update to avoid disk buildup.
        if let contents = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for item in contents {
                try? fm.removeItem(at: item)
            }
        }

        let safeVersion = normalizedVersion(from: version).replacingOccurrences(of: "/", with: "-")
        let stagedDir = root.appendingPathComponent("v\(safeVersion)-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagedDir, withIntermediateDirectories: true)
        let stagedAppURL = stagedDir.appendingPathComponent("Neon Vision Editor.app", isDirectory: true)
        let expectedVersion = readBundleShortVersionString(of: appBundle)
        var lastError: Error?

        for attempt in 1...2 {
            do {
                if fm.fileExists(atPath: stagedAppURL.path) {
                    try fm.removeItem(at: stagedAppURL)
                }
                let (dittoStatus, dittoStderr) = runDittoCopy(from: appBundle, to: stagedAppURL)
                if dittoStatus == 0 {
                    appendUpdaterLog("Staging via ditto succeeded (attempt \(attempt)).")
                } else {
                    appendUpdaterLog("Staging via ditto failed (attempt \(attempt), exit \(dittoStatus)). \(dittoStderr)")
                    try fm.copyItem(at: appBundle, to: stagedAppURL)
                    appendUpdaterLog("Staging fallback via FileManager.copyItem succeeded (attempt \(attempt)).")
                }

                guard try verifyCodeSignatureStrictCLI(of: stagedAppURL) else {
                    throw UpdateError.installUnsupported("Staged app failed signature validation.")
                }
                if let expectedVersion {
                    let stagedVersion = readBundleShortVersionString(of: stagedAppURL)
                    guard stagedVersion == expectedVersion else {
                        throw UpdateError.installUnsupported("Staged app version mismatch.")
                    }
                }
                return stagedAppURL
            } catch {
                lastError = error
                appendUpdaterLog("Staging attempt \(attempt) failed: \(error.localizedDescription)")
                try? fm.removeItem(at: stagedAppURL)
            }
        }

        appendUpdaterLog("Staging copy failed after retries. Source: \(appBundle.path)")
        if let lastError {
            throw lastError
        }
        throw UpdateError.installUnsupported("Failed to stage downloaded app for background install.")
    }

    private nonisolated static func runDittoCopy(from sourceURL: URL, to destinationURL: URL) -> (Int32, String) {
        let process = Process()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [sourceURL.path, destinationURL.path]
        process.standardError = stderrPipe
        do {
            try process.run()
            process.waitUntilExit()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, stderrText)
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    private nonisolated static func writeInstallerScript(
        sourceAppURL: URL,
        destinationAppURL: URL,
        appPID: Int32,
        relaunchAfterInstall: Bool,
        expectedVersion: String?
    ) throws -> URL {
        let fm = FileManager.default
        let scriptDir = fm.temporaryDirectory.appendingPathComponent("nve-installer", isDirectory: true)
        try fm.createDirectory(at: scriptDir, withIntermediateDirectories: true)
        let scriptURL = scriptDir.appendingPathComponent("apply-update-\(UUID().uuidString).sh")
        let logPath = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/NeonVisionEditorUpdater.log")
        let script = """
        #!/bin/sh
        set -eu
        SRC=\(shellQuote(sourceAppURL.path))
        DST=\(shellQuote(destinationAppURL.path))
        PID=\(appPID)
        RELAUNCH=\(relaunchAfterInstall ? "1" : "0")
        EXPECTED_VERSION=\(shellQuote(expectedVersion ?? ""))
        LOG=\(shellQuote(logPath))
        TMP="$DST.__new__"
        OLD="$DST.__old__"

        {
          rollback() {
            echo "Rolling back update..."
            if [ -e "$OLD" ]; then
              /bin/rm -rf "$DST"
              /bin/mv "$OLD" "$DST"
            fi
          }

          while /bin/kill -0 "$PID" 2>/dev/null; do
            /bin/sleep 1
          done

          /bin/rm -rf "$TMP"
          if ! /usr/bin/ditto "$SRC" "$TMP"; then
            echo "ditto failed; trying fallback copy."
            /bin/cp -R "$SRC" "$TMP"
          fi
          /bin/rm -rf "$OLD"
          if [ -e "$DST" ]; then
            /bin/mv "$DST" "$OLD"
          fi
          if ! /bin/mv "$TMP" "$DST"; then
            echo "Failed to move new app into destination."
            rollback
            exit 1
          fi

          if ! /usr/bin/codesign --verify --deep --strict "$DST"; then
            echo "Code signature self-test failed after install."
            rollback
            exit 1
          fi

          if [ -n "$EXPECTED_VERSION" ]; then
            INSTALLED_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DST/Contents/Info.plist" 2>/dev/null || true)
            if [ "$INSTALLED_VERSION" != "$EXPECTED_VERSION" ]; then
              echo "Version self-test failed. Expected $EXPECTED_VERSION, got $INSTALLED_VERSION."
              rollback
              exit 1
            fi
          fi

          /bin/rm -rf "$OLD"
          /bin/rm -rf "$SRC"
          if [ "$RELAUNCH" = "1" ]; then
            /usr/bin/open "$DST"
          fi
        } >> "$LOG" 2>&1
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: NSNumber(value: Int16(0o700))], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private nonisolated static func appendUpdaterLog(_ message: String) {
        let logURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/NeonVisionEditorUpdater.log")
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        do {
            try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logURL.path) {
                try line.write(to: logURL, atomically: true, encoding: .utf8)
                return
            }
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            // Logging must never break updater flow.
        }
    }

    private nonisolated static func readBundleShortVersionString(of appBundleURL: URL) -> String? {
        let infoPlistURL = appBundleURL.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: infoPlistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
            let version = plist["CFBundleShortVersionString"] as? String
        else {
            return nil
        }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private nonisolated static func unzip(zipURL: URL, to destination: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zipURL.path, destination.path]
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private nonisolated static func findFirstAppBundle(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "app" {
                return url
            }
        }
        return nil
    }
#endif

    private func openURL(_ url: URL) {
#if canImport(AppKit)
        NSWorkspace.shared.open(url)
#elseif canImport(UIKit)
        UIApplication.shared.open(url)
#endif
    }

    private func isTrustedGitHubURL(_ url: URL) -> Bool {
        guard url.scheme == "https" else { return false }
        return Self.isTrustedGitHubHost(url.host)
    }

    nonisolated static func isTrustedGitHubHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "github.com"
            || host == "objects.githubusercontent.com"
            || host == "github-releases.githubusercontent.com"
    }

    nonisolated static func selectPreferredAssetName(from names: [String]) -> String? {
        if let exact = names.first(where: { $0.caseInsensitiveCompare("Neon.Vision.Editor.app.zip") == .orderedSame }) {
            return exact
        }
        if let appZip = names.first(where: { $0.lowercased().hasSuffix(".app.zip") }) {
            return appZip
        }
        if let neonZip = names.first(where: { $0.lowercased().contains("neon") && $0.lowercased().hasSuffix(".zip") }) {
            return neonZip
        }
        return names.first(where: { $0.lowercased().hasSuffix(".zip") })
    }

    nonisolated static func normalizedVersion(from tag: String) -> String {
        var cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") {
            cleaned.removeFirst()
        }
        if let plus = cleaned.firstIndex(of: "+") {
            cleaned = String(cleaned[..<plus])
        }
        if let dash = cleaned.firstIndex(of: "-") {
            cleaned = String(cleaned[..<dash])
        }
        if let match = firstMatchString(
            in: cleaned,
            pattern: #"(?i)\b\d+(?:\.\d+){0,3}\b"#
        ) {
            return match
        }
        return cleaned
    }

    nonisolated static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftParts = normalizedVersion(from: lhs).split(separator: ".").map { Int($0) ?? 0 }
        let rightParts = normalizedVersion(from: rhs).split(separator: ".").map { Int($0) ?? 0 }
        let maxCount = max(leftParts.count, rightParts.count)

        for index in 0..<maxCount {
            let l = index < leftParts.count ? leftParts[index] : 0
            let r = index < rightParts.count ? rightParts[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }

        let leftIsPrerelease = isPrereleaseVersionTag(lhs)
        let rightIsPrerelease = isPrereleaseVersionTag(rhs)
        if leftIsPrerelease && !rightIsPrerelease { return .orderedAscending }
        if !leftIsPrerelease && rightIsPrerelease { return .orderedDescending }
        return .orderedSame
    }

    nonisolated static func compareReleaseToCurrent(
        releaseVersion: String,
        releaseBuild: String?,
        currentVersion: String,
        currentBuild: String?
    ) -> ComparisonResult {
        let versionResult = compareVersions(releaseVersion, currentVersion)
        if versionResult != .orderedSame {
            return versionResult
        }
        guard let releaseBuildInt = normalizedBuildNumber(from: releaseBuild),
              let currentBuildInt = normalizedBuildNumber(from: currentBuild) else {
            return .orderedSame
        }
        if releaseBuildInt < currentBuildInt { return .orderedAscending }
        if releaseBuildInt > currentBuildInt { return .orderedDescending }
        return .orderedSame
    }

    nonisolated static func releaseTrackingIdentifier(version: String, build: String?) -> String {
        let normalized = normalizedVersion(from: version)
        guard let buildValue = normalizedBuildNumber(from: build) else {
            return normalized
        }
        return "\(normalized)+\(buildValue)"
    }

    nonisolated static func isVersionSkipped(_ version: String, skippedValue: String?) -> Bool {
        skippedValue == version
    }

    nonisolated private static func normalizedBuildNumber(from raw: String?) -> Int? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    nonisolated private static func inferredBuildNumber(tag: String, name: String?, notes: String?) -> Int? {
        let semverPlusPattern = #"(?i)\bv?\d+(?:\.\d+){1,3}\+(\d{1,9})\b"#
        if let build = firstMatchInt(in: tag, pattern: semverPlusPattern) {
            return build
        }
        if let name, let build = firstMatchInt(in: name, pattern: semverPlusPattern) {
            return build
        }

        let buildLabelPattern = #"(?i)\bbuild\s*[:#-]?\s*(\d{1,9})\b"#
        if let build = firstMatchInt(in: tag, pattern: buildLabelPattern) {
            return build
        }
        if let name, let build = firstMatchInt(in: name, pattern: buildLabelPattern) {
            return build
        }
        if let notes, let build = firstMatchInt(in: notes, pattern: buildLabelPattern) {
            return build
        }
        return nil
    }

    nonisolated private static func isPrereleaseVersionTag(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).contains("-")
    }

    nonisolated private static func matchesExpectedRepository(url: URL, expectedOwner: String, expectedRepo: String) -> Bool {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return false }
        if parts[0].caseInsensitiveCompare(expectedOwner) == .orderedSame,
           parts[1].caseInsensitiveCompare(expectedRepo) == .orderedSame {
            return true
        }
        // GitHub REST API paths are /repos/{owner}/{repo}/...
        if parts.count >= 3,
           parts[0].caseInsensitiveCompare("repos") == .orderedSame,
           parts[1].caseInsensitiveCompare(expectedOwner) == .orderedSame,
           parts[2].caseInsensitiveCompare(expectedRepo) == .orderedSame {
            return true
        }
        return false
    }

    nonisolated private static func matchesExpectedAssetURL(url: URL, expectedOwner: String, expectedRepo: String) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "github.com" {
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count >= 4 else { return false }
            guard parts[0].caseInsensitiveCompare(expectedOwner) == .orderedSame,
                  parts[1].caseInsensitiveCompare(expectedRepo) == .orderedSame else {
                return false
            }
            return parts[2].lowercased() == "releases" && parts[3].lowercased() == "download"
        }
        return host == "github-releases.githubusercontent.com"
            || host == "objects.githubusercontent.com"
    }

    nonisolated private static func rateLimitResetDate(from response: HTTPURLResponse) -> Date? {
        guard let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
              let epoch = TimeInterval(reset) else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    nonisolated private static func extractSHA256(from notes: String, preferredAssetName: String) throws -> String {
        let escapedAsset = NSRegularExpression.escapedPattern(for: preferredAssetName)
        let exactAssetPattern = "(?im)\\b\(escapedAsset)\\b[^\\n]*?([A-Fa-f0-9]{64})"
        if let hash = firstMatchGroup(in: notes, pattern: exactAssetPattern) {
            return hash
        }

        let genericPattern = "(?im)sha[- ]?256[^A-Fa-f0-9]*([A-Fa-f0-9]{64})"
        if let hash = firstMatchGroup(in: notes, pattern: genericPattern) {
            return hash
        }

        throw UpdateError.checksumMissing(preferredAssetName)
    }

    nonisolated private static func resolveExpectedSHA256(
        assetSHA256: String?,
        notes: String,
        preferredAssetName: String
    ) throws -> String {
        if let assetSHA256, !assetSHA256.isEmpty {
            return assetSHA256
        }
        return try extractSHA256(from: notes, preferredAssetName: preferredAssetName)
    }

    nonisolated private static func sha256FromAssetDigest(_ digest: String?) -> String? {
        guard let digest else { return nil }
        let trimmed = digest.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.count == 64, trimmed.range(of: "^[A-Fa-f0-9]{64}$", options: .regularExpression) != nil {
            return trimmed.lowercased()
        }
        if trimmed.lowercased().hasPrefix("sha256:") {
            let suffix = String(trimmed.dropFirst("sha256:".count))
            if suffix.count == 64, suffix.range(of: "^[A-Fa-f0-9]{64}$", options: .regularExpression) != nil {
                return suffix.lowercased()
            }
        }
        return nil
    }

    nonisolated private static func firstMatchGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else { return nil }
        let captured = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return captured.isEmpty ? nil : captured
    }

    nonisolated private static func firstMatchInt(in text: String, pattern: String) -> Int? {
        guard let captured = firstMatchGroup(in: text, pattern: pattern) else { return nil }
        return Int(captured)
    }

    nonisolated private static func firstMatchString(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        let captured = ns.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
        return captured.isEmpty ? nil : captured
    }

    nonisolated private static func sha256Hex(of fileURL: URL) throws -> String {
        // Stream hashing avoids loading large zip files fully into memory.
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 64 * 1024)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static var isDevelopmentRuntime: Bool {
#if DEBUG
        return true
#else
        let bundlePath = Bundle.main.bundleURL.path
        if bundlePath.contains("/DerivedData/") { return true }
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return true }
        return false
#endif
    }

#if os(macOS)
    nonisolated private static func verifyCodeSignatureStrictCLI(of appBundle: URL) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", appBundle.path]
        let outputPipe = Pipe()
        process.standardError = outputPipe
        process.standardOutput = outputPipe
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    nonisolated private static func readTeamIdentifier(of appBundle: URL) throws -> String? {
#if canImport(Security)
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(appBundle as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else { return nil }

        var signingInfoRef: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfoRef)
        guard infoStatus == errSecSuccess,
              let signingInfo = signingInfoRef as? [String: Any] else {
            return nil
        }
        return signingInfo[kSecCodeInfoTeamIdentifier as String] as? String
#else
        return nil
#endif
    }

    nonisolated private static func verifyCodeSignature(
        of appBundle: URL,
        expectedTeamID: String,
        expectedBundleID: String?
    ) throws -> Bool {
#if canImport(Security)
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(appBundle as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else { return false }
        let checkStatus = SecStaticCodeCheckValidity(staticCode, SecCSFlags(), nil)
        guard checkStatus == errSecSuccess else { return false }

        var signingInfoRef: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfoRef)
        guard infoStatus == errSecSuccess,
              let signingInfo = signingInfoRef as? [String: Any] else {
            return false
        }

        guard let teamID = signingInfo[kSecCodeInfoTeamIdentifier as String] as? String,
              teamID == expectedTeamID else {
            return false
        }

        if let expectedBundleID, !expectedBundleID.isEmpty {
            guard let actualBundleID = signingInfo[kSecCodeInfoIdentifier as String] as? String,
                  actualBundleID == expectedBundleID else {
                return false
            }
        }
        return true
#else
        return false
#endif
    }
#endif
}

private struct GitHubReleasePayload: Decodable {
    let apiURL: URL?
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String
    let publishedAt: Date?
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubAssetPayload]

    enum CodingKeys: String, CodingKey {
        case apiURL = "url"
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case draft
        case prerelease
        case assets
    }
}

private struct GitHubAssetPayload: Decodable {
    let name: String
    let browserDownloadURL: String
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
    }
}

#if os(macOS)
private final class ReleaseAssetDownloadService {
    private struct DownloadAttemptFailure: Error {
        let underlying: Error
        let resumeData: Data?
    }

    private struct DownloadState {
        var continuation: CheckedContinuation<(URL, URLResponse), Error>?
        var progressHandler: (@Sendable (Double) -> Void)?
    }

    private final class DownloadStateController {
        private let lock = OSAllocatedUnfairLock(initialState: DownloadState())

        nonisolated func reserve(
            continuation: CheckedContinuation<(URL, URLResponse), Error>,
            progressHandler: @escaping @Sendable (Double) -> Void
        ) -> Bool {
            lock.withLock { state in
                guard state.continuation == nil else { return false }
                state.continuation = continuation
                state.progressHandler = progressHandler
                return true
            }
        }

        nonisolated func progressHandler() -> (@Sendable (Double) -> Void)? {
            lock.withLock { state in
                state.progressHandler
            }
        }

        nonisolated func takeContinuationAndReset() -> CheckedContinuation<(URL, URLResponse), Error>? {
            lock.withLock { state in
                let continuation = state.continuation
                state.continuation = nil
                state.progressHandler = nil
                return continuation
            }
        }
    }

    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        private let state: DownloadStateController

        init(state: DownloadStateController) {
            self.state = state
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            guard totalBytesExpectedToWrite > 0 else { return }
            let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let progressHandler = state.progressHandler()
            progressHandler?(fraction)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            guard let continuation = state.takeContinuationAndReset() else { return }
            guard let response = downloadTask.response else {
                continuation.resume(throwing: URLError(.badServerResponse))
                return
            }
            let fileManager = FileManager.default
            let stableTempURL = fileManager.temporaryDirectory
                .appendingPathComponent("nve-release-asset-\(UUID().uuidString).tmp", isDirectory: false)
            do {
                // Persist the downloaded file before this delegate callback returns.
                // URLSession may clean up `location` immediately after this method exits.
                if fileManager.fileExists(atPath: stableTempURL.path) {
                    try fileManager.removeItem(at: stableTempURL)
                }
                try fileManager.moveItem(at: location, to: stableTempURL)
                continuation.resume(returning: (stableTempURL, response))
            } catch {
                continuation.resume(throwing: error)
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let error else { return }
            guard let continuation = state.takeContinuationAndReset() else { return }
            let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            continuation.resume(throwing: DownloadAttemptFailure(underlying: error, resumeData: resumeData))
        }
    }

    private let state: DownloadStateController
    private let delegate: DownloadDelegate
    private let session: URLSession

    init() {
        let state = DownloadStateController()
        self.state = state
        self.delegate = DownloadDelegate(state: state)
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config, delegate: self.delegate, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    func download(
        from url: URL,
        maxAttempts: Int = 4,
        baseBackoffSeconds: TimeInterval = 1.0,
        retryNotice: ((Int, TimeInterval, Bool) -> Void)? = nil,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (URL, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        var resumeData: Data?

        for attempt in 1...maxAttempts {
            do {
                return try await performSingleDownload(request: request, resumeData: resumeData, progress: progress)
            } catch let failure as DownloadAttemptFailure {
                let shouldRetryNow = attempt < maxAttempts && shouldRetry(after: failure.underlying)
                guard shouldRetryNow else {
                    throw failure.underlying
                }
                let delay = min(8.0, baseBackoffSeconds * pow(2.0, Double(attempt - 1)))
                retryNotice?(attempt + 1, delay, failure.resumeData != nil)
                resumeData = failure.resumeData
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                let shouldRetryNow = attempt < maxAttempts && shouldRetry(after: error)
                guard shouldRetryNow else {
                    throw error
                }
                let delay = min(8.0, baseBackoffSeconds * pow(2.0, Double(attempt - 1)))
                retryNotice?(attempt + 1, delay, false)
                resumeData = nil
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw URLError(.cannotLoadFromNetwork)
    }

    private func performSingleDownload(
        request: URLRequest,
        resumeData: Data?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (URL, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            guard state.reserve(continuation: continuation, progressHandler: progress) else {
                continuation.resume(throwing: URLError(.cannotLoadFromNetwork))
                return
            }
            let task: URLSessionDownloadTask
            if let resumeData {
                task = session.downloadTask(withResumeData: resumeData)
            } else {
                task = session.downloadTask(with: request)
            }
            task.resume()
        }
    }

    private func shouldRetry(after error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        switch nsError.code {
        case NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorCallIsActive,
            NSURLErrorDataNotAllowed,
            NSURLErrorCannotLoadFromNetwork:
            return true
        default:
            return false
        }
    }

}
#else
private final class ReleaseAssetDownloadService {
    func download(
        from url: URL,
        maxAttempts: Int = 4,
        baseBackoffSeconds: TimeInterval = 1.0,
        retryNotice: ((Int, TimeInterval, Bool) -> Void)? = nil,
        progress: @escaping (Double) -> Void
    ) async throws -> (URL, URLResponse) {
        progress(0)
        return try await URLSession.shared.download(from: url)
    }
}
#endif
