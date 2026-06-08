import Foundation

extension Bundle {
    private static let appResourcesBundleName = "Swooshy_Swooshy.bundle"

    static var appResources: Bundle {
        let bundleCandidates = [
            Bundle.main.resourceURL?.appendingPathComponent(appResourcesBundleName),
            Bundle.main.bundleURL.appendingPathComponent(appResourcesBundleName).absoluteURL,
        ].compactMap { $0 }

        for candidate in bundleCandidates {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }

        return .module
    }
}
