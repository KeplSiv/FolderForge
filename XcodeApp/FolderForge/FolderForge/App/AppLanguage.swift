import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case portugueseBrazil = "pt-BR"
    case italian = "it"
    case dutch = "nl"
    case polish = "pl"
    case russian = "ru"
    case ukrainian = "uk"
    case turkish = "tr"
    case simplifiedChinese = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"
    case vietnamese = "vi"
    case indonesian = "id"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: "English"
        case .spanish: "Español"
        case .french: "Français"
        case .german: "Deutsch"
        case .portugueseBrazil: "Português (Brasil)"
        case .italian: "Italiano"
        case .dutch: "Nederlands"
        case .polish: "Polski"
        case .russian: "Русский"
        case .ukrainian: "Українська"
        case .turkish: "Türkçe"
        case .simplifiedChinese: "简体中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .vietnamese: "Tiếng Việt"
        case .indonesian: "Bahasa Indonesia"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }
}

enum LanguagePreference {
    static let languageKey = "appearance.language"
    static let completedFirstRunKey = "appearance.languageChosen"
}
