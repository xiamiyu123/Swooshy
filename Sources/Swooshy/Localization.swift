import Foundation

enum L10n {
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

        let candidates = preferences + fallbackLocalizationCandidates
        return localizedBundle(for: candidates) ?? resourcesBundle
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

        for preference in preferences {
            if let localization = matchingLocalization(for: preference) {
                return localization
            }
        }

        return nil
    }

    private static func localePreferences(
        explicitLocaleIdentifier: String?,
        preferredLanguages: [String]?
    ) -> [String] {
        let basePreferences =
            explicitLocaleIdentifier.map { [$0] }
            ?? preferredLanguages
            ?? preferredLanguagesOverride
            ?? Locale.preferredLanguages

        return basePreferences.flatMap(localePreferenceCandidates)
    }

    private static var fallbackLocalizationCandidates: [String] {
        ["en", resourcesBundle.localizations.first].compactMap { $0 }
    }

    private static func localePreferenceCandidates(for identifier: String) -> [String] {
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

        return candidates
            .compactMap { $0 }
            .filter { !$0.isEmpty }
    }

    private static func matchingLocalization(for candidate: String) -> String? {
        resourcesBundle.localizations.first {
            $0.compare(candidate, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private static func localizedBundle(for candidates: [String]) -> Bundle? {
        for candidate in candidates {
            guard
                let localization = matchingLocalization(for: candidate),
                let url = resourcesBundle.url(forResource: localization, withExtension: "lproj")
            else {
                continue
            }

            if let bundle = Bundle(url: url) {
                return bundle
            }
        }

        return nil
    }

    private static let resourcesBundle: Bundle = .appResources
}
