import Foundation

enum AboutUpdateState: Equatable, Sendable {
    case manualCheck
    case checking
    case upToDate
    case updateAvailable
    case checkFailed
}

struct AboutPageModel: Equatable, Sendable {
    static let appName = "Swooshy"
    static let repositoryURL = githubURL()
    static let latestReleaseAPIURL = apiURL(path: "/releases/latest")
    static let latestReleaseURL = githubURL(path: "/releases/latest")
    static let licenseURL = githubURL(path: "/blob/main/LICENSE")
    static let attributionURL = githubURL(path: "/blob/main/ATTRIBUTION.md")

    let appName: String
    let currentVersion: String?
    let versionText: String
    let updateState: AboutUpdateState
    let repositoryURL: URL
    let latestReleaseURL: URL
    let licenseURL: URL
    let attributionURL: URL

    init(
        shortVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        buildVersion: String? = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
        previewUpdateAvailable: Bool = false
    ) {
        self.appName = Self.appName
        self.currentVersion = Self.normalizedVersion(shortVersion)
        self.versionText = Self.versionText(shortVersion: shortVersion, buildVersion: buildVersion)
        self.updateState = previewUpdateAvailable ? .updateAvailable : .manualCheck
        self.repositoryURL = Self.repositoryURL
        self.latestReleaseURL = Self.latestReleaseURL
        self.licenseURL = Self.licenseURL
        self.attributionURL = Self.attributionURL
    }

    static func versionText(shortVersion: String?, buildVersion: String?) -> String {
        let shortVersion = shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let buildVersion = buildVersion?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let shortVersion, shortVersion.isEmpty == false else {
            return "Development Build"
        }

        guard
            let buildVersion,
            buildVersion.isEmpty == false,
            buildVersion != shortVersion
        else {
            return shortVersion
        }

        return "\(shortVersion) (\(buildVersion))"
    }

    static func updateState(currentVersion: String?, latestReleaseTag: String) -> AboutUpdateState {
        guard let latestVersion = ComparableVersion(latestReleaseTag) else {
            return .checkFailed
        }

        guard
            let currentVersion,
            let currentVersion = ComparableVersion(currentVersion)
        else {
            return .updateAvailable
        }

        return latestVersion > currentVersion ? .updateAvailable : .upToDate
    }

    private static func normalizedVersion(_ version: String?) -> String? {
        let version = version?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let version, version.isEmpty == false else {
            return nil
        }

        return version
    }

    private static func githubURL(path: String = "") -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/xiamiyu123/Swooshy\(path)"
        guard let url = components.url else {
            preconditionFailure("Invalid Swooshy GitHub URL")
        }
        return url
    }

    private static func apiURL(path: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/xiamiyu123/Swooshy\(path)"
        guard let url = components.url else {
            preconditionFailure("Invalid Swooshy GitHub API URL")
        }
        return url
    }
}

enum AboutUpdateChecker {
    static func checkLatestRelease(currentVersion: String?) async -> AboutUpdateState {
        do {
            var request = URLRequest(url: AboutPageModel.latestReleaseAPIURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Swooshy", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return .checkFailed
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            return AboutPageModel.updateState(
                currentVersion: currentVersion,
                latestReleaseTag: release.tagName
            )
        } catch {
            return .checkFailed
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}

private struct ComparableVersion: Comparable {
    private let components: [Int]

    init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.dropFirst(trimmed.first?.lowercased() == "v" ? 1 : 0)
        let core = withoutPrefix.split(separator: "-", maxSplits: 1).first ?? ""
        let segments = core.split(separator: ".")
        let components = segments.compactMap { Int($0) }

        guard components.isEmpty == false, components.count == segments.count else {
            return nil
        }

        self.components = components
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0 ..< max(lhs.components.count, rhs.components.count) {
            let left = lhs.components.indices.contains(index) ? lhs.components[index] : 0
            let right = rhs.components.indices.contains(index) ? rhs.components[index] : 0

            if left != right {
                return left < right
            }
        }

        return false
    }
}
