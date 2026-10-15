import Foundation
import Observation

/// Interface languages. See docs/localization.md.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en, ru, es
    case zhHans = "zh-Hans"

    var id: String { rawValue }

    static let supported: [AppLanguage] = [.en, .ru, .es, .zhHans]

    /// Name of the language in that language, so it is recognisable whatever the current one is.
    var nativeName: String {
        switch self {
        case .system: return tr("System")
        case .en: return "English"
        case .ru: return "Русский"
        case .es: return "Español"
        case .zhHans: return "简体中文"
        }
    }

    /// The language macOS would pick for this app from the user's preferred languages.
    static var preferredBySystem: AppLanguage {
        let codes = supported.map(\.rawValue)
        let match = Bundle.preferredLocalizations(from: codes, forPreferences: systemLanguages).first
        return match.flatMap(AppLanguage.init(rawValue:)) ?? .en
    }

    /// Preferred languages of the user, ignoring the per-app override this app writes for system menus.
    private static var systemLanguages: [String] {
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        return global ?? Locale.preferredLanguages
    }
}

/// Translates interface strings. English strings are the keys; a missing translation falls back to the key.
/// Views read `current`, so changing the language re-renders them without a restart.
@Observable
final class Localizer: @unchecked Sendable {
    static let shared = Localizer()

    private static let settingKey = "language"

    var choice: AppLanguage {
        didSet { apply() }
    }

    /// The language in effect, never `.system`.
    private(set) var current: AppLanguage = .en

    var locale: Locale { Locale(identifier: current.rawValue) }

    init() {
        choice = UserDefaults.standard.string(forKey: Self.settingKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
        apply()
    }

    private func apply() {
        current = choice == .system ? AppLanguage.preferredBySystem : choice
        let defaults = UserDefaults.standard
        if choice == .system {
            defaults.removeObject(forKey: Self.settingKey)
            // Menus that macOS itself provides follow AppleLanguages at launch.
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set(choice.rawValue, forKey: Self.settingKey)
            defaults.set([choice.rawValue], forKey: "AppleLanguages")
        }
    }

    func string(_ key: String) -> String {
        Translations.strings[current]?[key] ?? key
    }

    func plural(_ key: String, _ count: Int) -> String {
        let forms = Translations.plurals[current]?[key] ?? Translations.plurals[.en]?[key] ?? [key]
        let index = min(Self.pluralIndex(count, current), forms.count - 1)
        return String(format: forms[index], locale: locale, count)
    }

    /// CLDR plural categories, reduced to what the supported languages need: one / few / many.
    static func pluralIndex(_ n: Int, _ language: AppLanguage) -> Int {
        switch language {
        case .ru:
            let mod10 = n % 10, mod100 = n % 100
            if mod10 == 1, mod100 != 11 { return 0 }
            if (2...4).contains(mod10), !(12...14).contains(mod100) { return 1 }
            return 2
        case .zhHans:
            return 0
        default:
            return n == 1 ? 0 : 1
        }
    }
}

/// Translated interface string.
func tr(_ key: String) -> String {
    Localizer.shared.string(key)
}

/// Translated format string, filled with `arguments`.
func tr(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: Localizer.shared.string(key), locale: Localizer.shared.locale, arguments: arguments)
}

/// Translated count phrase such as "3 files". Plural forms live in `Translations.plurals`.
func trPlural(_ key: String, _ count: Int) -> String {
    Localizer.shared.plural(key, count)
}
