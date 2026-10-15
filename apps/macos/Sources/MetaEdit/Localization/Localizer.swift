import Foundation
import Observation
import os

/// Interface languages. See docs/localization.md.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en, ru, es
    case zhHans = "zh-Hans"

    var id: String { rawValue }

    /// The languages the interface is translated into. Resources/Info.plist lists the same ones in
    /// CFBundleLocalizations; ProviderTests.languagesMatchInfoPlist keeps the two in step.
    static let supported = allCases.filter { $0 != .system }

    /// Preferred languages of an app or of the user, read by macOS for the menus it provides itself.
    static let appleLanguagesKey = "AppleLanguages"

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
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[appleLanguagesKey] as? [String]
        return global ?? Locale.preferredLanguages
    }
}

/// Translates interface strings. English strings are the keys; a missing translation falls back to the key.
/// Safe to use from any thread, since providers translate their error messages in the background.
/// Views that call tr() observe the language, so changing it re-renders them without a restart.
final class Localizer: Observable, Sendable {
    static let shared = Localizer()

    private static let settingKey = "language"

    private struct State: Sendable {
        var choice: AppLanguage
        var current: AppLanguage
    }

    private let state: OSAllocatedUnfairLock<State>
    private let registrar = ObservationRegistrar()

    init() {
        let choice = UserDefaults.standard.string(forKey: Self.settingKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
        state = OSAllocatedUnfairLock(initialState: State(choice: choice, current: Self.resolve(choice)))
        Self.persist(choice)
    }

    /// The language picked in Settings, possibly `.system`.
    var choice: AppLanguage {
        get {
            registrar.access(self, keyPath: \.choice)
            return state.withLock { $0.choice }
        }
        set {
            registrar.withMutation(of: self, keyPath: \.choice) {
                registrar.withMutation(of: self, keyPath: \.current) {
                    state.withLock { $0 = State(choice: newValue, current: Self.resolve(newValue)) }
                }
            }
            Self.persist(newValue)
        }
    }

    /// The language in effect, never `.system`.
    var current: AppLanguage {
        registrar.access(self, keyPath: \.current)
        return state.withLock { $0.current }
    }

    var locale: Locale { Locale(identifier: current.rawValue) }

    private static func resolve(_ choice: AppLanguage) -> AppLanguage {
        choice == .system ? AppLanguage.preferredBySystem : choice
    }

    private static func persist(_ choice: AppLanguage) {
        let defaults = UserDefaults.standard
        if choice == .system {
            defaults.removeObject(forKey: settingKey)
            defaults.removeObject(forKey: AppLanguage.appleLanguagesKey)
        } else {
            defaults.set(choice.rawValue, forKey: settingKey)
            defaults.set([choice.rawValue], forKey: AppLanguage.appleLanguagesKey)
        }
    }

    func string(_ key: String) -> String {
        Translations.strings[current]?[key] ?? key
    }

    func plural(_ key: String, _ count: Int) -> String {
        let language = current
        let forms = Translations.plurals[language]?[key] ?? Translations.plurals[.en]?[key] ?? [key]
        let index = min(Self.pluralIndex(count, language), forms.count - 1)
        return String(format: forms[index], locale: Locale(identifier: language.rawValue), count)
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
