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

    /// List-sourced facts are **list entries**, not the tangential blurb link.
    /// Title/body come from the list item; Read more + image stay on the list page.
    /// `articleSummary` is optional enrichment only when the linked page is a real subject
    /// (not a hometown city) — pass `nil` otherwise.
    static func makeFact(
        from entry: ListEntry,
        listPageSummary: WikipediaSummaryDTO?,
        articleSummary: WikipediaSummaryDTO?,
        matchedNicheIDs: [String]
    ) -> Fact {
        let title = displayTitleForListEntry(entry)
        let cleanedBlurb = formatSummary(entry.blurb)
        let articleExtract = formatSummary(articleSummary?.extract ?? "")

        // List blurb is the fact. Article extract only fills in if the blurb is too thin
        // and we were given a verified subject article.
        let summaryText: String
        if cleanedBlurb.count >= 40 {
            summaryText = cleanedBlurb
        } else if articleExtract.count >= 80 {
            summaryText = articleExtract
        } else {
            summaryText = cleanedBlurb.isEmpty ? articleExtract : cleanedBlurb
        }

        let imageString = listPageSummary?.thumbnail?.source ?? listPageSummary?.originalimage?.source
        let listWikiPath = entry.listTitle.replacingOccurrences(of: " ", with: "_")
        let pageString = listPageSummary?.content_urls?.desktop?.page
            ?? listPageSummary?.content_urls?.mobile?.page
            ?? "https://en.wikipedia.org/wiki/\(listWikiPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? listWikiPath)"

        // Closer-look: subject article when we have one; otherwise the list page itself.
        let lookupTitle = articleSummary != nil ? entry.articleTitle : entry.listTitle

        return Fact(
            id: entry.id,
            title: title,
            lookupTitle: lookupTitle,
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
        TextUtils.cleanFactPlainText(extract)
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
        return makeAdditionInterest(label: label)
    }

    /// Broader heart suggestions: catalog matches + generalized Wikipedia categories.
    static func heartSuggestions(categories: [String], fact: Fact, limit: Int = 8) -> [Interest] {
        var results: [Interest] = []
        var seen = Set<String>()

        func append(_ interest: Interest) {
            let key = interest.id
            guard seen.insert(key).inserted else { return }
            results.append(interest)
        }

        // 1) Existing catalog niches that clearly relate to this fact.
        let haystack = "\(fact.title) \(fact.summary) \(fact.highlight) \(categories.joined(separator: " "))"
            .lowercased()
        let catalogHits = InterestCatalog.leaves.compactMap { leaf -> (Interest, Int)? in
            var score = 0
            for keyword in InterestMatching.interestKeywords(leaf) {
                let strength = InterestMatching.keywordStrength(keyword, allowShortBrands: false)
                if strength > 0, InterestMatching.keywordHits(haystack: haystack, keyword: keyword) {
                    score = max(score, strength)
                }
            }
            return score > 0 ? (leaf, score) : nil
        }
        .sorted { $0.1 > $1.1 }
        for (leaf, _) in catalogHits.prefix(4) {
            append(leaf)
        }

        // 2) Broadened Wikipedia categories (not hyper-specific leaves).
        for raw in categories {
            guard let broad = broadenCategoryLabel(raw) else { continue }
            // Prefer an existing catalog leaf with the same label when possible.
            if let existing = InterestCatalog.leaves.first(where: {
                $0.label.compare(broad, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                append(existing)
            } else {
                append(makeAdditionInterest(label: broad))
            }
            if results.count >= limit { break }
        }

        return Array(results.prefix(limit))
    }

    /// Collapse overly specific Wiki categories into something matchable.
    static func broadenCategoryLabel(_ raw: String) -> String? {
        var label = raw.replacingOccurrences(of: #"^Category:"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isUsableCategory(label) else { return nil }

        // Drop trailing geography / date-heavy tails: "X in France", "X of the 19th century"
        label = label.replacingOccurrences(
            of: #"\s+(in|of|from|by|for)\s+.+$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        label = label.trimmingCharacters(in: .whitespacesAndNewlines)

        var words = label.split(separator: " ").map(String.init)
        // Keep at most 3 content words so niches stay broad enough to match DYK.
        if words.count > 3 {
            words = Array(words.suffix(3))
            label = words.joined(separator: " ")
        }
        guard isBroadEnoughCategory(label) else { return nil }
        return label
    }

    private static func makeAdditionInterest(label: String) -> Interest {
        let lower = label.lowercased()
        let parts = lower.split(separator: " ").map(String.init).filter { $0.count > 2 }
        let slug = TextUtils.slugify(label)
        return Interest(
            id: "add-\(slug)",
            label: label,
            keywords: Array(Set([lower] + parts)),
            categoryHints: [lower] + parts.filter { $0.count >= 4 },
            parentID: nil,
            parentLabel: "More like this",
            overview: "A broader topic suggested from an article you liked.",
            purpose: "Steer Learn toward related Did You Know facts.",
            symbolName: "sparkles",
            source: .addition
        )
    }

    /// Public so loaders can de-dupe / safety-check before building the Fact.
    static func listEntryDisplayTitle(_ entry: ListEntry) -> String {
        displayTitleForListEntry(entry)
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
        guard cleaned.count >= 3, cleaned.count <= 56 else { return false }
        if cleaned.range(of: #"^\d{4}"#, options: .regularExpression) != nil { return false }
        if cleaned.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil { return false }
        let blocked = [
            "Articles ", "Pages ", "All ", "Wikipedia ", "CS1 ", "Use ", "Webarchive",
            "Redirects ", "Disambiguation", "Living people", "Births ", "Deaths ",
            "People from ", "Alumni of ", "Members of "
        ]
        if blocked.contains(where: { cleaned.hasPrefix($0) }) { return false }
        if cleaned.range(of: #"\b(stubs?|templates?|categories|maintenance|wikidata|infobox)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return false
        }
        return true
    }

    private static func isBroadEnoughCategory(_ cleaned: String) -> Bool {
        guard isUsableCategory(cleaned) else { return false }
        let words = cleaned.split(separator: " ")
        guard words.count >= 1, words.count <= 3 else { return false }
        // Single very short tokens are too vague / noisy for matching.
        if words.count == 1, cleaned.count < 4 { return false }
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
