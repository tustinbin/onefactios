import Foundation

/// Soft family-friendly filter. Wikipedia’s API does **not** exclude adult topics;
/// this is our app-side precaution and will miss some edge cases.
enum ContentSafety {
    private static let blockedTitleFragments: [String] = [
        "porn", "pornograph", "xxx", "hentai", "erotic", "sex worker",
        "prostitut", "brothel", "onlyfans", "sexual act", "child sexual",
        "rape", "incest", "bdsm", "fetish", "nudity", "nude "
    ]

    private static let blockedCategoryFragments: [String] = [
        "pornograph", "erotica", "sexual act", "prostitution",
        "sex worker", "bdsm", "fetish", "nude photography",
        "lgbt pornography", "adult film", "xxx", "sexual content"
    ]

    static func isRestrictedTitle(_ title: String) -> Bool {
        containsBlocked(title, list: blockedTitleFragments)
    }

    static func isRestrictedCategories(_ categoryTitles: [String]) -> Bool {
        categoryTitles.contains { containsBlocked($0, list: blockedCategoryFragments) }
    }

    static func isRestrictedSummary(_ summary: WikipediaSummaryDTO?) -> Bool {
        guard let summary else { return false }
        let blob = [summary.title, summary.description, summary.extract]
            .compactMap { $0 }
            .joined(separator: " ")
        return containsBlocked(blob, list: blockedTitleFragments)
    }

    static func isRestrictedFactText(title: String, summary: String, highlight: String) -> Bool {
        containsBlocked(
            [title, summary, highlight].joined(separator: " "),
            list: blockedTitleFragments
        )
    }

    private static func containsBlocked(_ text: String, list: [String]) -> Bool {
        let lower = text.lowercased()
        return list.contains { lower.contains($0) }
    }
}
