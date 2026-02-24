import XCTest
@testable import Neon_Vision_Editor

final class AppUpdateManagerTests: XCTestCase {
    func testHostAllowlistBehavior() {
        XCTAssertTrue(AppUpdateManager.isTrustedGitHubHost("github.com"))
        XCTAssertTrue(AppUpdateManager.isTrustedGitHubHost("objects.githubusercontent.com"))
        XCTAssertTrue(AppUpdateManager.isTrustedGitHubHost("github-releases.githubusercontent.com"))
        XCTAssertFalse(AppUpdateManager.isTrustedGitHubHost("api.github.com"))
        XCTAssertFalse(AppUpdateManager.isTrustedGitHubHost("github.com.evil.example"))
        XCTAssertFalse(AppUpdateManager.isTrustedGitHubHost(nil))
    }

    func testAssetChooserPrecedence() {
        let names = [
            "Neon-Vision-Editor-macOS.zip",
            "Neon.Vision.Editor.app.zip",
            "Neon-App-Preview.zip"
        ]
        XCTAssertEqual(AppUpdateManager.selectPreferredAssetName(from: names), "Neon.Vision.Editor.app.zip")

        let appZipFallback = [
            "NeonVisionEditor.app.zip",
            "Neon-Vision-Editor-macOS.zip"
        ]
        XCTAssertEqual(AppUpdateManager.selectPreferredAssetName(from: appZipFallback), "NeonVisionEditor.app.zip")

        let neonZipFallback = [
            "Neon-Vision-Editor-macOS.zip",
            "SomethingElse.zip"
        ]
        XCTAssertEqual(AppUpdateManager.selectPreferredAssetName(from: neonZipFallback), "Neon-Vision-Editor-macOS.zip")
    }

    func testSkipVersionBehavior() {
        XCTAssertTrue(AppUpdateManager.isVersionSkipped("1.2.3", skippedValue: "1.2.3"))
        XCTAssertFalse(AppUpdateManager.isVersionSkipped("1.2.3", skippedValue: nil))
        XCTAssertFalse(AppUpdateManager.isVersionSkipped("1.2.3", skippedValue: "1.2.4"))
        XCTAssertFalse(AppUpdateManager.isVersionSkipped("1.2.3", skippedValue: "v1.2.3"))
    }

    func testNormalizeVersionStripsPrefixAndPrerelease() {
        XCTAssertEqual(AppUpdateManager.normalizedVersion(from: "v1.2.3"), "1.2.3")
        XCTAssertEqual(AppUpdateManager.normalizedVersion(from: "V2.0.0-beta.1"), "2.0.0")
        XCTAssertEqual(AppUpdateManager.normalizedVersion(from: "v2.1.0+456"), "2.1.0")
        XCTAssertEqual(AppUpdateManager.normalizedVersion(from: "v2.1.0 (build 456)"), "2.1.0")
        XCTAssertEqual(AppUpdateManager.normalizedVersion(from: "release 2.1.0+456-hotfix"), "2.1.0")
    }

    func testVersionComparison() {
        XCTAssertEqual(AppUpdateManager.compareVersions("1.2.0", "1.1.9"), .orderedDescending)
        XCTAssertEqual(AppUpdateManager.compareVersions("1.2", "1.2.0"), .orderedSame)
        XCTAssertEqual(AppUpdateManager.compareVersions("1.2.0", "1.2.1"), .orderedAscending)
    }

    func testStableIsNewerThanPrereleaseWithSameCoreVersion() {
        XCTAssertEqual(AppUpdateManager.compareVersions("1.2.0-beta.1", "1.2.0"), .orderedAscending)
        XCTAssertEqual(AppUpdateManager.compareVersions("1.2.0", "1.2.0-beta.1"), .orderedDescending)
    }

    func testPrereleaseVsStableEdgeCases() {
        XCTAssertEqual(AppUpdateManager.compareVersions("1.10.0-beta.1", "1.9.9"), .orderedDescending)
        XCTAssertEqual(AppUpdateManager.compareVersions("v1.2.0", "1.2.0-rc.1"), .orderedDescending)
        XCTAssertEqual(AppUpdateManager.compareVersions("1.2.0-rc.1", "1.2.0-beta.4"), .orderedSame)
    }

    func testReleaseComparisonFallsBackToBuildWhenVersionMatches() {
        XCTAssertEqual(
            AppUpdateManager.compareReleaseToCurrent(
                releaseVersion: "1.2.3",
                releaseBuild: "200",
                currentVersion: "1.2.3",
                currentBuild: "199"
            ),
            .orderedDescending
        )
        XCTAssertEqual(
            AppUpdateManager.compareReleaseToCurrent(
                releaseVersion: "1.2.3",
                releaseBuild: "199",
                currentVersion: "1.2.3",
                currentBuild: "200"
            ),
            .orderedAscending
        )
        XCTAssertEqual(
            AppUpdateManager.compareReleaseToCurrent(
                releaseVersion: "1.2.3",
                releaseBuild: nil,
                currentVersion: "1.2.3",
                currentBuild: "200"
            ),
            .orderedSame
        )
        XCTAssertEqual(
            AppUpdateManager.compareReleaseToCurrent(
                releaseVersion: "1.2.3+201",
                releaseBuild: "201",
                currentVersion: "1.2.3",
                currentBuild: "200"
            ),
            .orderedDescending
        )
        XCTAssertEqual(
            AppUpdateManager.compareReleaseToCurrent(
                releaseVersion: "v1.2.3 (build 201)",
                releaseBuild: "201",
                currentVersion: "1.2.3",
                currentBuild: "200"
            ),
            .orderedDescending
        )
        XCTAssertEqual(
            AppUpdateManager.compareReleaseToCurrent(
                releaseVersion: "release 1.2.3+199-hotfix",
                releaseBuild: "199",
                currentVersion: "1.2.3",
                currentBuild: "200"
            ),
            .orderedAscending
        )
    }

    func testReleaseComparisonHandlesMissingAndInvalidBuildsAsEqual() {
        XCTAssertEqual(
            AppUpdateManager.compareReleaseToCurrent(
                releaseVersion: "1.2.3",
                releaseBuild: nil,
                currentVersion: "1.2.3",
                currentBuild: "200"
            ),
            .orderedSame
        )
        XCTAssertEqual(
            AppUpdateManager.compareReleaseToCurrent(
                releaseVersion: "1.2.3",
                releaseBuild: "build-abc",
                currentVersion: "1.2.3",
                currentBuild: "200"
            ),
            .orderedSame
        )
    }

    func testReleaseTrackingIdentifierIncludesBuildWhenPresent() {
        XCTAssertEqual(AppUpdateManager.releaseTrackingIdentifier(version: "v1.2.3", build: "45"), "1.2.3+45")
        XCTAssertEqual(AppUpdateManager.releaseTrackingIdentifier(version: "1.2.3", build: nil), "1.2.3")
    }
}
