import Foundation

enum L10n {
    static func string(
        _ key: String,
        localeIdentifier: String? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
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
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Bundle {
        guard
            let localization = localization(
                for: localeIdentifier,
                preferredLanguages: preferredLanguages
            ),
            let path = Bundle.module.path(forResource: localization, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return .module
        }

        return bundle
    }

    static func localization(
        for localeIdentifier: String?,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String? {
        let preferences = localePreferences(
            explicitLocaleIdentifier: localeIdentifier,
            preferredLanguages: preferredLanguages
        )

        if let preferredLocalization = Bundle.preferredLocalizations(
            from: Bundle.module.localizations,
            forPreferences: preferences
        ).first {
            return preferredLocalization
        }

        for candidate in preferences {
            if let match = Bundle.module.localizations.first(where: {
                $0.compare(candidate, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                return match
            }
        }

        return nil
    }

    private static func localePreferences(
        explicitLocaleIdentifier: String?,
        preferredLanguages: [String]
    ) -> [String] {
        let basePreferences = explicitLocaleIdentifier.map { [$0] } ?? preferredLanguages

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
}
