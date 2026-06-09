import Testing
@testable import Swooshy

struct AboutPageModelTests {
    @Test
    func versionTextUsesShortVersionWhenBuildMatches() {
        #expect(
            AboutPageModel.versionText(
                shortVersion: "2.6.11",
                buildVersion: "2.6.11"
            ) == "2.6.11"
        )
    }

    @Test
    func versionTextIncludesDifferentBuildVersion() {
        #expect(
            AboutPageModel.versionText(
                shortVersion: "2.6.11",
                buildVersion: "42"
            ) == "2.6.11 (42)"
        )
    }

    @Test
    func versionTextFallsBackForDevelopmentBuilds() {
        #expect(
            AboutPageModel.versionText(
                shortVersion: nil,
                buildVersion: nil
            ) == "Development Build"
        )
        #expect(
            AboutPageModel.versionText(
                shortVersion: " ",
                buildVersion: "42"
            ) == "Development Build"
        )
    }

    @Test
    func linksPointToProjectPages() {
        let model = AboutPageModel(shortVersion: "2.6.11", buildVersion: "2.6.11")

        #expect(model.repositoryURL.absoluteString == "https://github.com/xiamiyu123/Swooshy")
        #expect(model.currentVersion == "2.6.11")
        #expect(AboutPageModel.latestReleaseAPIURL.absoluteString == "https://api.github.com/repos/xiamiyu123/Swooshy/releases/latest")
        #expect(model.latestReleaseURL.absoluteString == "https://github.com/xiamiyu123/Swooshy/releases/latest")
        #expect(model.licenseURL.absoluteString == "https://github.com/xiamiyu123/Swooshy/blob/main/LICENSE")
        #expect(model.attributionURL.absoluteString == "https://github.com/xiamiyu123/Swooshy/blob/main/ATTRIBUTION.md")
    }

    @Test
    func previewUpdateAvailableUsesUpdateAvailableState() {
        #expect(AboutPageModel(previewUpdateAvailable: false).updateState == .manualCheck)
        #expect(AboutPageModel(previewUpdateAvailable: true).updateState == .updateAvailable)
    }

    @Test
    func updateStateComparesVersionTags() {
        #expect(
            AboutPageModel.updateState(
                currentVersion: "2.6.11",
                latestReleaseTag: "v2.6.12"
            ) == .updateAvailable
        )
        #expect(
            AboutPageModel.updateState(
                currentVersion: "2.6.11",
                latestReleaseTag: "v2.6.11"
            ) == .upToDate
        )
        #expect(
            AboutPageModel.updateState(
                currentVersion: "2.7.0",
                latestReleaseTag: "v2.6.12"
            ) == .upToDate
        )
        #expect(
            AboutPageModel.updateState(
                currentVersion: nil,
                latestReleaseTag: "v2.6.12"
            ) == .updateAvailable
        )
        #expect(
            AboutPageModel.updateState(
                currentVersion: "2.6.x",
                latestReleaseTag: "v2.6.12"
            ) == .updateAvailable
        )
        #expect(
            AboutPageModel.updateState(
                currentVersion: "2.6.11",
                latestReleaseTag: "latest"
            ) == .checkFailed
        )
    }
}
