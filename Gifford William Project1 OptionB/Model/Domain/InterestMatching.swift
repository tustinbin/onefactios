import Foundation

/// Exact port of web `domain/matching.js` + category helpers from `domain/interests.js`.
enum InterestMatching {
    // MARK: - Keywords (leaf-only — parents intentionally not inherited)

    static func interestKeywords(_ interest: Interest) -> [String] {
        if !interest.keywords.isEmpty {
            return Array(Set(interest.keywords.map { $0.lowercased() }))
        }
        let label = interest.label.lowercased()
        let parts = label.split(separator: " ").map(String.init).filter { $0.count > 2 }
        return Array(Set([label] + parts))
    }

    /// Words that shouldn't drive matching on their own ("Star Wars" → star + wars).
    private static let matchStopWords: Set<String> = [
        "a", "an", "the", "of", "and", "or", "in", "on", "at", "to", "for",
        "from", "by", "with", "as", "vs", "versus", "&"
    ]

    /// Stronger = better. Phrases beat long tokens; tiny tokens are ignored.
    /// Custom niches allow slightly shorter brand-like tokens (e.g. "lego").
    static func keywordStrength(_ keyword: String, allowShortBrands: Bool = false) -> Int {
        let k = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return 0 }
        let words = k.split(separator: " ").filter { !$0.isEmpty }
        if words.count >= 2 { return 3 }
        if k.count >= 8 { return 2 }
        if k.count >= 5 { return 1 }
        if allowShortBrands, k.count >= 3 { return 1 }
        return 0
    }

    static func keywordHits(haystack: String, keyword: String) -> Bool {
        let k = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return false }
        if k.contains(" ") { return haystack.contains(k) }
        let escaped = NSRegularExpression.escapedPattern(for: k)
        let pattern = "(?:^|[^a-z0-9])\(escaped)(?:[^a-z0-9]|$)"
        return haystack.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Meaningful tokens from a label (drops a/the/of, keeps "star" + "wars").
    static func significantMatchWords(from label: String) -> [String] {
        label
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 && !matchStopWords.contains($0) }
    }

    private static var usesStrictPhraseMatching: (Interest) -> Bool = { interest in
        interest.source == .custom || interest.source == .addition
    }

    /// Custom / sparkle niches: every significant word must appear (or the full phrase).
    private static func scoreStrictMultiWord(_ interest: Interest, haystack: String) -> Int? {
        guard usesStrictPhraseMatching(interest) else { return nil }
        let words = significantMatchWords(from: interest.label)
        guard words.count >= 2 else { return nil }

        let phrase = interest.label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !phrase.isEmpty, haystack.contains(phrase) {
            return 3
        }
        if words.allSatisfy({ keywordHits(haystack: haystack, keyword: $0) }) {
            return 3
        }
        return 0
    }

    static func scoreInterestAgainstHook(_ interest: Interest, hook: DYKHook) -> Int {
        let haystack = "\(hook.articleTitle) \(hook.hookText)".lowercased()
        if let strict = scoreStrictMultiWord(interest, haystack: haystack) {
            return strict
        }
        let allowShort = interest.source == .custom || interest.source == .addition
        var best = 0
        for keyword in interestKeywords(interest) {
            let strength = keywordStrength(keyword, allowShortBrands: allowShort)
            if strength > 0, keywordHits(haystack: haystack, keyword: keyword) {
                best = max(best, strength)
            }
        }
        return best
    }

    static func matchedInterestsForHook(_ hook: DYKHook, selectedInterests: [Interest]) -> [Interest] {
        selectedInterests
            .map { (interest: $0, score: scoreInterestAgainstHook($0, hook: hook)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .map(\.interest)
    }

    struct ScoredHook {
        let hook: DYKHook
        let matched: [(interest: Interest, score: Int)]
        let bestScore: Int
    }

    /// Rank DYK hooks that pass leaf-keyword matching for Interests mode.
    static func shortlistInterestHooks(
        _ hooks: [DYKHook],
        seenIDs: [String],
        selectedInterests: [Interest],
        limit: Int = 12
    ) -> [ScoredHook] {
        let unused = hooks.filter { !seenIDs.contains($0.id) }
        let pool = unused.isEmpty ? hooks : unused
        guard !pool.isEmpty, !selectedInterests.isEmpty else { return [] }

        var scored: [ScoredHook] = []
        for hook in pool {
            let matched = selectedInterests
                .map { (interest: $0, score: scoreInterestAgainstHook($0, hook: hook)) }
                .filter { $0.score > 0 }
                .sorted { $0.score > $1.score }
            if let best = matched.first {
                scored.append(ScoredHook(hook: hook, matched: matched, bestScore: best.score))
            }
        }

        scored.sort { a, b in
            if a.bestScore != b.bestScore { return a.bestScore > b.bestScore }
            return Bool.random()
        }
        return Array(scored.prefix(limit))
    }

    static func chooseHook(
        _ hooks: [DYKHook],
        interestsMode: Bool,
        seenIDs: [String],
        selectedInterests: [Interest]
    ) -> (hook: DYKHook?, matchedLabel: String?) {
        let unused = hooks.filter { !seenIDs.contains($0.id) }
        let pool = unused.isEmpty ? hooks : unused
        guard !pool.isEmpty else { return (nil, nil) }

        if !interestsMode || selectedInterests.isEmpty {
            return (TextUtils.pickRandom(pool), nil)
        }

        let shortlist = shortlistInterestHooks(
            hooks,
            seenIDs: seenIDs,
            selectedInterests: selectedInterests,
            limit: 1
        )
        guard let pick = shortlist.first else { return (nil, nil) }
        return (pick.hook, pick.matched.first?.interest.label)
    }

    // MARK: - Category verification (web `categoriesMatchInterest`)

    static func categoryMatchTerms(_ interest: Interest) -> [String] {
        let terms = interest.categoryHints + interestKeywords(interest) + [interest.label]
        return Array(Set(
            terms
                .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 4 }
        ))
    }

    static func categoriesMatchInterest(_ categoryTitles: [String], interest: Interest) -> Bool {
        let cats = categoryTitles.map {
            $0.replacingOccurrences(of: #"^Category:"#, with: "", options: [.regularExpression, .caseInsensitive])
                .lowercased()
        }
        let blob = cats.joined(separator: " ")

        // Custom multi-word: require full phrase or every significant word across categories.
        if let strict = scoreStrictMultiWord(interest, haystack: blob) {
            return strict > 0
        }

        let terms = categoryMatchTerms(interest)
        guard !terms.isEmpty else { return false }

        return terms.contains { term in
            // Avoid ultra-short tokens ("trial") matching unrelated categories.
            guard term.count >= 5 || term.contains(" ") else { return false }
            return cats.contains { cat in
                if cat.contains(term) { return true }
                if term.contains(cat), cat.count >= 6 { return true }
                return false
            }
        }
    }

    /// Keyword score against arbitrary text (list blurbs, article extracts, titles).
    static func scoreInterestAgainstText(_ interest: Interest, text: String) -> Int {
        let haystack = text.lowercased()
        if let strict = scoreStrictMultiWord(interest, haystack: haystack) {
            return strict
        }
        let allowShort = interest.source == .custom || interest.source == .addition
        var best = 0
        for keyword in interestKeywords(interest) {
            let strength = keywordStrength(keyword, allowShortBrands: allowShort)
            if strength > 0, keywordHits(haystack: haystack, keyword: keyword) {
                best = max(best, strength)
            }
        }
        return best
    }

    static func bestInterestMatch(
        in text: String,
        selectedInterests: [Interest]
    ) -> (interest: Interest, score: Int)? {
        selectedInterests
            .map { ($0, scoreInterestAgainstText($0, text: text)) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }
            .map { (interest: $0.0, score: $0.1) }
    }

    // MARK: - Off-topic guards (e.g. soundtrack pages under Crime & intrigue)

    private static let musicNicheIDPrefixes = ["music-"]
    private static let gamesNicheIDPrefixes = ["games-", "play-"]
    private static let musicSignals = [
        "soundtrack", " discograph", "album", "single (song)", "songs written",
        "film score", "musical composition", "cast recording"
    ]
    private static let gamesSignals = [
        "video game", "video games", "nintendo", "playstation", "xbox"
    ]

    /// True when the page is clearly music/games media and none of the selected niches want that.
    static func isOffTopicForSelectedInterests(
        title: String,
        categories: [String],
        selectedInterests: [Interest]
    ) -> Bool {
        guard !selectedInterests.isEmpty else { return false }
        let blob = ([title] + categories).joined(separator: " ").lowercased()
        let wantsMusic = selectedInterests.contains { interest in
            musicNicheIDPrefixes.contains { interest.id.hasPrefix($0) }
                || interest.parentID == "music"
                || interest.label.lowercased().contains("music")
        }
        let wantsGames = selectedInterests.contains { interest in
            gamesNicheIDPrefixes.contains { interest.id.hasPrefix($0) }
                || interest.parentID == "games"
                || interest.label.lowercased().contains("game")
        }

        let looksMusic = musicSignals.contains { blob.contains($0) }
            || title.lowercased().contains("soundtrack")
        let looksGames = gamesSignals.contains { blob.contains($0) }

        if looksMusic, !wantsMusic { return true }
        if looksGames, !wantsGames { return true }
        return false
    }

    /// Collapse “The Last of Us Part I/II soundtrack” style titles for de-duplication.
    static func seriesStem(for title: String) -> String {
        var t = title.lowercased()
        t = t.replacingOccurrences(of: #"\bsoundtrack\b"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\balbum\b"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\bpart\s*(?:[ivx]+|\d+)\b"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
        t = TextUtils.normalizeWhitespace(t)
        let stop: Set<String> = ["the", "a", "an", "of", "and"]
        let words = t.split(separator: " ").map(String.init).filter { !stop.contains($0) }
        return words.prefix(4).joined(separator: " ")
    }

    static func isTooSimilarTitle(_ title: String, toRecent recentTitles: [String]) -> Bool {
        let stem = seriesStem(for: title)
        guard stem.count >= 4 else { return false }
        return recentTitles.suffix(8).contains { seriesStem(for: $0) == stem }
    }
}
