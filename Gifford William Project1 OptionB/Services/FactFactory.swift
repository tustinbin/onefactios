import Foundation

enum FactFactory {
    private static let stopWords: Set<String> = [
        "the", "and", "that", "with", "from", "this", "were", "was", "are", "for",
        "his", "her", "she", "who", "has", "had", "been", "into", "over", "after",
        "before", "their", "they", "than", "also", "which", "when", "where", "while",
        "about", "have", "one"
    ]

    // MARK: - DYK hook (web `buildFact`)

    static func makeFact(
        from hook: DYKHook,
        summary: WikipediaSummaryDTO?,
        matchedNicheIDs: [String]
    ) -> Fact {
        let title = summary?.title ?? hook.articleTitle
        let statement = rephraseHookToStatement(hook.hookText)
        // Full extract for readable iOS layout (web clips to ~360; we keep full REST extract).
        let summaryText = formatSummary(summary?.extract ?? "")
        let showHighlight = !statement.isEmpty && !isHighlightRedundant(summary: summaryText, highlight: statement)
        let imageString = summary?.thumbnail?.source ?? summary?.originalimage?.source
        let pageString = summary?.content_urls?.desktop?.page
            ?? summary?.content_urls?.mobile?.page
            ?? "https://en.wikipedia.org/wiki/\(hook.articleTitle.replacingOccurrences(of: " ", with: "_"))"

        return Fact(
            id: hook.id,
            title: title,
            lookupTitle: hook.articleTitle,
            summary: summaryText,
            highlight: showHighlight ? statement : "",
            imageURL: imageString.flatMap(URL.init(string:)),
            pageURL: URL(string: pageString),
            matchedNicheIDs: matchedNicheIDs,
            source: .dyk,
            isComplete: false,
            savedAt: nil
        )
    }

    // MARK: - List entry

    /// List-sourced facts always "Read more" to the **list page**, not a tangential
    /// blurb link (e.g. Autopsy). Image comes from the list page summary only —
    /// never from a linked side article — so we don't show misleading thumbnails.
    static func makeFact(
        from entry: ListEntry,
        listPageSummary: WikipediaSummaryDTO?,
        matchedNicheIDs: [String]
    ) -> Fact {
        let title = displayTitleForListEntry(entry)
        let summaryText = formatSummary(entry.blurb).isEmpty ? entry.blurb : formatSummary(entry.blurb)
        let imageString = listPageSummary?.thumbnail?.source ?? listPageSummary?.originalimage?.source
        let listWikiPath = entry.listTitle.replacingOccurrences(of: " ", with: "_")
        let pageString = listPageSummary?.content_urls?.desktop?.page
            ?? listPageSummary?.content_urls?.mobile?.page
            ?? "https://en.wikipedia.org/wiki/\(listWikiPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listWikiPath)"

        return Fact(
            id: entry.id,
            title: title,
            lookupTitle: entry.articleTitle,
            summary: summaryText,
            highlight: "",
            imageURL: imageString.flatMap(URL.init(string:)),
            pageURL: URL(string: pageString),
            matchedNicheIDs: matchedNicheIDs,
            source: .list,
            isComplete: false,
            savedAt: nil
        )
    }

    /// Category labels safe to show on the card back.
    static func displayCategories(from rawTitles: [String], limit: Int = 8) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in rawTitles {
            let label = raw.replacingOccurrences(of: #"^Category:"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUsableCategory(label) else { continue }
            let key = label.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(label)
            if result.count >= limit { break }
        }
        return result
    }

    static func rephraseHookToStatement(_ hookText: String) -> String {
        var text = TextUtils.normalizeWhitespace(hookText)
        text = text.replacingOccurrences(of: #"^(?:\.\.\.|…)\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"^that\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"\?\s*$"#, with: "", options: .regularExpression)
        text = TextUtils.normalizeWhitespace(text)
            .replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        guard !text.isEmpty else { return hookText }
        text = text.prefix(1).uppercased() + text.dropFirst()
        if text.range(of: #"[.!?]$"#, options: .regularExpression) == nil {
            text += "."
        }
        return text
    }

    static func formatSummary(_ extract: String) -> String {
        TextUtils.normalizeWhitespace(extract)
    }

    static func isHighlightRedundant(summary: String, highlight: String) -> Bool {
        let summaryNorm = normalizeForCompare(summary)
        let highlightNorm = normalizeForCompare(highlight)
        guard !highlightNorm.isEmpty else { return true }
        if summaryNorm.contains(highlightNorm) || highlightNorm.contains(summaryNorm) { return true }
        let summaryTokens = Set(significantTokens(summary))
        let highlightTokens = significantTokens(highlight)
        guard !highlightTokens.isEmpty else { return true }
        let overlap = highlightTokens.filter { summaryTokens.contains($0) }.count
        return Double(overlap) / Double(highlightTokens.count) >= 0.72
    }

    static func interestFromCategoryTitle(_ name: String) -> Interest? {
        let label = name.replacingOccurrences(of: #"^Category:"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isUsableCategory(label) else { return nil }
        let lower = label.lowercased()
        let parts = lower.split(separator: " ").map(String.init).filter { $0.count > 2 }
        let slug = TextUtils.slugify(label)
        return Interest(
            id: "add-\(slug)",
            label: label,
            keywords: [lower] + parts,
            categoryHints: [lower],
            parentID: nil,
            parentLabel: nil,
            overview: "A topic you added by hearting a related Wikipedia article.",
            purpose: "Steer future facts toward subjects you already liked.",
            symbolName: "plus.circle",
            source: .addition
        )
    }

    private static func displayTitleForListEntry(_ entry: ListEntry) -> String {
        if entry.listTitle.range(of: #"\bincidents?\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            var place = entry.listTitle
            place = place.replacingOccurrences(
                of: #"^List of incidents at\s+"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            place = place.replacingOccurrences(
                of: #"^Incidents at\s+"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            place = place.trimmingCharacters(in: .whitespacesAndNewlines)
            if let yearMatch = entry.blurb.range(of: #"\b((?:19|20)\d{2})\b"#, options: .regularExpression) {
                let year = String(entry.blurb[yearMatch])
                if !place.isEmpty { return "\(place) (\(year))" }
            }
            if !place.isEmpty { return "\(place) incident" }
        }
        // Prefer the parsed list-item subject, not a side-link article title.
        return entry.articleTitle
    }

    private static func isUsableCategory(_ cleaned: String) -> Bool {
        guard cleaned.count >= 3, cleaned.count <= 48 else { return false }
        if cleaned.range(of: #"^\d{4}"#, options: .regularExpression) != nil { return false }
        let blocked = [
            "Articles ", "Pages ", "All ", "Wikipedia ", "CS1 ", "Use ", "Webarchive",
            "Redirects ", "Disambiguation", "Living people", "Births ", "Deaths "
        ]
        if blocked.contains(where: { cleaned.hasPrefix($0) }) { return false }
        if cleaned.range(of: #"\b(stubs?|templates?|categories|maintenance|wikidata|infobox)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return false
        }
        return true
    }

    private static func normalizeForCompare(_ text: String) -> String {
        TextUtils.normalizeWhitespace(text)
            .lowercased()
            .replacingOccurrences(of: #"[^\w\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func significantTokens(_ text: String) -> [String] {
        normalizeForCompare(text)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }
}
