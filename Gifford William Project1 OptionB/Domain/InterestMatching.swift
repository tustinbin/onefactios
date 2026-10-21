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

    static func scoreInterestAgainstHook(_ interest: Interest, hook: DYKHook) -> Int {
        let haystack = "\(hook.articleTitle) \(hook.hookText)".lowercased()
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
        let terms = categoryMatchTerms(interest)
        guard !terms.isEmpty else { return false }

        let cats = categoryTitles.map {
            $0.replacingOccurrences(of: #"^Category:"#, with: "", options: [.regularExpression, .caseInsensitive])
                .lowercased()
        }

        return terms.contains { term in
            cats.contains { cat in
                if cat.contains(term) { return true }
                if term.contains(cat), cat.count >= 6 { return true }
                return false
            }
        }
    }
}
