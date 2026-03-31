import Foundation

enum L10n {
    private static let resourceBundleName = "Swooshy_Swooshy.bundle"

    nonisolated(unsafe) private static var preferredLanguagesOverride: [String]?

    static func setPreferredLanguagesOverride(_ languages: [String]?) {
        preferredLanguagesOverride = languages
    }

    static func string(
        _ key: String,
        localeIdentifier: String? = nil,
        preferredLanguages: [String]? = nil
    ) -> String {
        let bundle = bundle(
            for: localeIdentifier,
            preferredLanguages: preferredLanguages
        )

        return bundle.localizedString(
            forKey: key,
            value: key,
            table: nil
        )
    }

    static func bundle(
        for localeIdentifier: String?,
        preferredLanguages: [String]? = nil
    ) -> Bundle {
        let preferences = localePreferences(
            explicitLocaleIdentifier: localeIdentifier,
            preferredLanguages: preferredLanguages
        )

        let candidates = preferences + ["en", resourcesBundle.localizations.first].compactMap { $0 }
        
        for candidate in candidates {
            if let match = resourcesBundle.localizations.first(where: {
                $0.compare(candidate, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }),
            let path = resourcesBundle.path(forResource: match, ofType: "lproj"),
            let bundle = Bundle(path: path) {
                return bundle
            }
        }

        return resourcesBundle
    }

    static func localization(
        for localeIdentifier: String?,
        preferredLanguages: [String]? = nil
    ) -> String? {
        let preferences = localePreferences(
            explicitLocaleIdentifier: localeIdentifier,
            preferredLanguages: preferredLanguages
        )

        if let preferredLocalization = Bundle.preferredLocalizations(
            from: resourcesBundle.localizations,
            forPreferences: preferences
        ).first {
            return preferredLocalization
        }

        for candidate in preferences {
            if let match = resourcesBundle.localizations.first(where: {
                $0.compare(candidate, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                return match
            }
        }

        return nil
    }

    private static func localePreferences(
        explicitLocaleIdentifier: String?,
        preferredLanguages: [String]?
    ) -> [String] {
        let basePreferences = explicitLocaleIdentifier.map { [$0] } ?? preferredLanguages ?? preferredLanguagesOverride ?? Locale.preferredLanguages

        return basePreferences.flatMap { identifier in
            let normalizedIdentifier = identifier.replacingOccurrences(of: "_", with: "-")
            let locale = Locale(identifier: normalizedIdentifier)
            let languageCode = locale.language.languageCode?.identifier
            let scriptCode = locale.language.script?.identifier

            let candidates: [String?] = [
                normalizedIdentifier,
                normalizedIdentifier.lowercased(),
                [languageCode, scriptCode].compactMap { $0 }.joined(separator: "-"),
                languageCode,
            ]

            return candidates.compactMap { (candidate: String?) -> String? in
                guard let candidate, !candidate.isEmpty else { return nil }
                return candidate
            }
        }
    }

    private static let resourcesBundle: Bundle = .appResources
}
