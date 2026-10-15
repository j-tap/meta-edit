import Foundation

/// Translation tables. Keys are the English strings used in code; English needs entries only for plurals.
/// Every language must translate every key: ProviderTests.translationsAreComplete checks it.
/// See docs/localization.md for the shared glossary.
enum Translations {
    static let strings: [AppLanguage: [String: String]] = [.ru: ru, .es: es, .zhHans: zhHans]

    /// Plural forms in the order of Localizer.pluralIndex: English and Spanish one / other,
    /// Russian one / few / many, Chinese a single form.
    static let plurals: [AppLanguage: [String: [String]]] = [.en: enPlurals, .ru: ruPlurals, .es: esPlurals, .zhHans: zhHansPlurals]

    static let enPlurals: [String: [String]] = [
        "%d files": ["%d file", "%d files"],
        "Added %d files": ["Added %d file", "Added %d files"],
        "Saved %d files": ["Saved %d file", "Saved %d files"],
        "Save changes to %d files?": ["Save changes to %d file?", "Save changes to %d files?"],
        "Change %d files?": ["Change %d file?", "Change %d files?"],
        "Change %d files": ["Change %d file", "Change %d files"],
    ]
}
