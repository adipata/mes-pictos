import Foundation

/// UserDefaults keys. Settings are per device (not synced), so the iPad and the parent's
/// iPhone can use different voices or show-mode options.
enum SettingsKey {
    static let onboardingDone = "onboardingDone"
    static let lastPageID = "lastPageID"

    static let voiceIdentifier = "voiceIdentifier"
    static let speechRate = "speechRate"
    static let speechPitch = "speechPitch"

    static let showModeEnabled = "showModeEnabled"
    static let showDismissMode = "showDismissMode"
    static let showAutoCloseSeconds = "showAutoCloseSeconds"
    static let showCelebration = "showCelebration"

    static let sentenceBarEnabled = "sentenceBarEnabled"
    static let sentenceMaxWords = "sentenceMaxWords"
    static let sentenceClearAfterReading = "sentenceClearAfterReading"
    /// One-time migration: existing "Je veux"-like cards became sentence starters.
    static let startersUpgradedV1 = "startersUpgradedV1"

    static let labelStyle = "labelStyle"
    static let showPageTabs = "showPageTabs"
    static let tapInterval = "tapInterval"

    static let parentProtection = "parentProtection"
    static let parentCode = "parentCode"

    /// Every key, for "reset settings".
    static let all = [
        onboardingDone, lastPageID, voiceIdentifier, speechRate, speechPitch,
        showModeEnabled, showDismissMode, showAutoCloseSeconds, showCelebration,
        sentenceBarEnabled, sentenceMaxWords, sentenceClearAfterReading, startersUpgradedV1,
        labelStyle, showPageTabs, tapInterval, parentProtection, parentCode,
    ]

    /// Back to the defaults. The onboarding flag is kept unless `includingOnboarding`.
    static func resetAll(in defaults: UserDefaults = .standard, includingOnboarding: Bool = false) {
        for key in all where includingOnboarding || key != onboardingDone {
            defaults.removeObject(forKey: key)
        }
    }
}

enum SettingsDefault {
    static let speechRate = 0.45
    static let speechPitch = 1.0
    static let showModeEnabled = true
    static let showAutoCloseSeconds = 0
    static let showCelebration = true
    static let sentenceBarEnabled = true
    /// Words after the starter: "Je veux" + 2 words by default.
    static let sentenceMaxWords = 2
    static let sentenceMaxWordsRange = 1...4
    static let sentenceClearAfterReading = true
    static let showPageTabs = true
    static let tapInterval = 0.6
}

/// How the card shown in the centre is closed.
enum DismissMode: String, CaseIterable, Identifiable {
    /// Tap outside the card, swipe the card away, or swipe down outside it.
    case tapOutside
    /// Long press (1 s) outside the card, so the child does not close it before showing it.
    case adultLongPress

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tapOutside: return "Toucher à côté ou glisser la carte"
        case .adultLongPress: return "Appui long (adulte)"
        }
    }
}

/// What protects the parent mode, in addition to the 3-second press on the lock.
enum ParentProtection: String, CaseIterable, Identifiable {
    case gestureOnly
    case code
    case deviceAuth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gestureOnly: return "Appui long seulement"
        case .code: return "Code parent"
        case .deviceAuth: return "Face ID / Touch ID"
        }
    }
}

extension UserDefaults {
    func double(forKey key: String, default value: Double) -> Double {
        object(forKey: key) as? Double ?? value
    }

    func bool(forKey key: String, default value: Bool) -> Bool {
        object(forKey: key) as? Bool ?? value
    }

    func integer(forKey key: String, default value: Int) -> Int {
        object(forKey: key) as? Int ?? value
    }
}
