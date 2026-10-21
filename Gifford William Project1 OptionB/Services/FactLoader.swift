import Foundation

struct LoadedFact {
    let fact: Fact
    let matchedLabel: String?
}

enum FactLoadError: LocalizedError {
    case noMatch
    case network

    var errorDescription: String? {
        switch self {
        case .noMatch:
            return "No facts matched your interests. Add more niches or try Random."
        case .network:
            return "Wikipedia didn’t return a fact."
        }
    }
}

/// Orchestrates fact loading like web `services/load-fact.js`:
/// curated lists (sometimes) → DYK archive months → keyword shortlist → category verify → list fallback.
actor FactLoader {
    private let wikipedia: WikipediaService
    private var listEntryCache: [String: [ListEntry]] = [:]

    private let categoryCheckPerMonth = 6
    private let interestsWithListsAttempts = 8
    private let randomAttempts = 6
    private let interestsAttempts = 32

    init(wikipedia: WikipediaService = WikipediaService()) {
        self.wikipedia = wikipedia
    }

    func loadFact(
        interestsMode: Bool,
        selectedInterests: [Interest],
        seenIDs: [String],
        recentTitles: [String] = []
    ) async throws -> LoadedFact {
        let nicheIDs = selectedInterests.map(\.id)
        let listSources = ListSources.forNicheIDs(nicheIDs)
        let allowLists = interestsMode && !listSources.isEmpty

        // Interests niches with curated lists: often try lists first (DYK is sparse there).
        // List entries are presented as list facts (blurb + list subject), not as the
        // tangential wikilink (e.g. a hometown city).
        if allowLists, Double.random(in: 0..<1) < 0.55 {
            if let listPick = await pickListEntry(
                nicheIDs: nicheIDs,
                seenIDs: seenIDs,
                selectedInterests: selectedInterests,
                recentTitles: recentTitles
            ) {
                return try await presentListFact(
                    listPick,
                    selectedInterests: selectedInterests,
                    interestsMode: interestsMode,
                    recentTitles: recentTitles
                )
            }
        }

        var chosen: DYKHook?
        var matchedLabel: String?
        var lastError: Error?
        var avoidKey: String?

        let maxAttempts: Int
        if interestsMode, !selectedInterests.isEmpty {
            maxAttempts = listSources.isEmpty ? interestsAttempts : interestsWithListsAttempts
        } else {
            maxAttempts = randomAttempts
        }

        for attempt in 0..<maxAttempts where chosen == nil {
            let target = await wikipedia.pickArchiveTarget(avoidKey: avoidKey)
            avoidKey = target.key
            do {
                let html = try await wikipedia.fetchDykArchive(year: target.year, monthName: target.monthName)
                let hooks = TextUtils.shuffle(DYKParser.parseHooks(from: html))
                guard !hooks.isEmpty else { continue }

                let result: (hook: DYKHook?, matchedLabel: String?)
                if interestsMode, !selectedInterests.isEmpty {
                    result = await pickInterestHook(
                        hooks,
                        selectedInterests: selectedInterests,
                        seenIDs: seenIDs
                    )
                } else {
                    result = InterestMatching.chooseHook(
                        hooks,
                        interestsMode: false,
                        seenIDs: seenIDs,
                        selectedInterests: []
                    )
                }

                if let hook = result.hook,
                   !ContentSafety.isRestrictedTitle(hook.articleTitle),
                   !InterestMatching.isTooSimilarTitle(hook.articleTitle, toRecent: recentTitles) {
                    chosen = hook
                    matchedLabel = result.matchedLabel
                }
            } catch {
                lastError = error
                // Back off when Wikimedia rate-limits so the next month attempt can succeed.
                if let wikiError = error as? WikipediaServiceError, wikiError == .rateLimited {
                    try? await Task.sleep(nanoseconds: UInt64((1.0 + Double(attempt) * 0.5) * 1_000_000_000))
                }
            }
        }

        if let chosen {
            do {
                return try await presentDYKFact(
                    chosen,
                    matchedLabel: interestsMode ? matchedLabel : nil,
                    selectedInterests: interestsMode ? selectedInterests : [],
                    recentTitles: recentTitles
                )
            } catch {
                // Restricted / bad page — keep going to list fallback or another attempt path.
                lastError = error
            }
        }

        // List pages are Interests-only — Random stays pure DYK.
        if allowLists {
            if let listPick = await pickListEntry(
                nicheIDs: nicheIDs,
                seenIDs: seenIDs,
                selectedInterests: selectedInterests,
                recentTitles: recentTitles
            ) {
                return try await presentListFact(
                    listPick,
                    selectedInterests: selectedInterests,
                    interestsMode: true,
                    recentTitles: recentTitles
                )
            }
        }

        if interestsMode, !selectedInterests.isEmpty {
            throw FactLoadError.noMatch
        }

        if let wikiError = lastError as? WikipediaServiceError {
            throw wikiError
        }
        throw lastError.map { _ in FactLoadError.network } ?? FactLoadError.network
    }

    // MARK: - Interest DYK pick (keyword shortlist + category verify)

    private func pickInterestHook(
        _ hooks: [DYKHook],
        selectedInterests: [Interest],
        seenIDs: [String]
    ) async -> (hook: DYKHook?, matchedLabel: String?) {
        let shortlist = InterestMatching.shortlistInterestHooks(
            hooks,
            seenIDs: seenIDs,
            selectedInterests: selectedInterests,
            limit: categoryCheckPerMonth
        )
        guard !shortlist.isEmpty else { return (nil, nil) }

        for candidate in shortlist {
            if ContentSafety.isRestrictedTitle(candidate.hook.articleTitle) { continue }
            do {
                let categories = try await wikipedia.fetchCategoryTitles(forArticleTitle: candidate.hook.articleTitle)
                if ContentSafety.isRestrictedCategories(categories) { continue }
                if InterestMatching.isOffTopicForSelectedInterests(
                    title: candidate.hook.articleTitle,
                    categories: categories,
                    selectedInterests: selectedInterests
                ) {
                    continue
                }
                let verified = candidate.matched.filter { item in
                    InterestMatching.categoriesMatchInterest(categories, interest: item.interest)
                }
                if let first = verified.first {
                    return (candidate.hook, first.interest.label)
                }
            } catch {
                // Only accept without categories when the keyword phrase match is very strong.
                if candidate.bestScore >= 3 {
                    return (candidate.hook, candidate.matched.first?.interest.label)
                }
                continue
            }
        }
        return (nil, nil)
    }

    // MARK: - Present

    private func presentDYKFact(
        _ hook: DYKHook,
        matchedLabel: String?,
        selectedInterests: [Interest],
        recentTitles: [String]
    ) async throws -> LoadedFact {
        if ContentSafety.isRestrictedTitle(hook.articleTitle) {
            throw FactLoadError.noMatch
        }
        if InterestMatching.isTooSimilarTitle(hook.articleTitle, toRecent: recentTitles) {
            throw FactLoadError.noMatch
        }
        let summary = try? await wikipedia.fetchSummary(title: hook.articleTitle)
        if ContentSafety.isRestrictedSummary(summary) {
            throw FactLoadError.noMatch
        }
        if !selectedInterests.isEmpty {
            let categories = (try? await wikipedia.fetchCategoryTitles(forArticleTitle: hook.articleTitle)) ?? []
            if InterestMatching.isOffTopicForSelectedInterests(
                title: hook.articleTitle,
                categories: categories,
                selectedInterests: selectedInterests
            ) {
                throw FactLoadError.noMatch
            }
        }
        let matchedNicheIDs = InterestMatching.matchedInterestsForHook(hook, selectedInterests: selectedInterests).map(\.id)
        let fact = FactFactory.makeFact(from: hook, summary: summary, matchedNicheIDs: matchedNicheIDs)
        if ContentSafety.isRestrictedFactText(
            title: fact.title,
            summary: fact.summary,
            highlight: fact.highlight
        ) {
            throw FactLoadError.noMatch
        }
        return LoadedFact(fact: fact, matchedLabel: matchedLabel)
    }

    private func presentListFact(
        _ pick: (entry: ListEntry, source: ListSource),
        selectedInterests: [Interest],
        interestsMode: Bool,
        recentTitles: [String]
    ) async throws -> LoadedFact {
        // Card identity comes from the list entry (blurb + display title), not the
        // blurb's first wikilink — so a hometown city never becomes the fact.
        let displayTitle = FactFactory.listEntryDisplayTitle(pick.entry)
        if InterestMatching.isTooSimilarTitle(displayTitle, toRecent: recentTitles) {
            throw FactLoadError.noMatch
        }
        if ContentSafety.isRestrictedFactText(
            title: displayTitle,
            summary: pick.entry.blurb,
            highlight: ""
        ) {
            throw FactLoadError.noMatch
        }

        async let listPageSummaryTask = wikipedia.fetchSummary(title: pick.entry.listTitle)

        // Only fetch / use a linked article when it looks like a real subject (ride, cat, …).
        let linkedTitle = pick.entry.articleTitle
        let linkedLooksPlace = ListPageParser.isPlaceLikeWikiTitle(linkedTitle)
        var subjectSummary: WikipediaSummaryDTO?
        var subjectCategories: [String] = []

        if !linkedLooksPlace, !ContentSafety.isRestrictedTitle(linkedTitle) {
            async let articleSummaryTask = wikipedia.fetchSummary(title: linkedTitle)
            async let categoriesTask = wikipedia.fetchCategoryTitles(forArticleTitle: linkedTitle)
            let articleSummary = try? await articleSummaryTask
            let categories = (try? await categoriesTask) ?? []
            let articleTitle = (articleSummary?.title ?? linkedTitle)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let isSettlement = ListPageParser.looksLikeSettlement(
                title: articleTitle.isEmpty ? linkedTitle : articleTitle,
                categories: categories
            )
            if !isSettlement,
               !ContentSafety.isRestrictedSummary(articleSummary),
               !InterestMatching.isOffTopicForSelectedInterests(
                   title: linkedTitle,
                   categories: categories,
                   selectedInterests: selectedInterests
               ) {
                subjectSummary = articleSummary
                subjectCategories = categories
            }
        }

        let listPageSummary = try? await listPageSummaryTask

        let listNicheInterests = selectedInterests.filter { pick.source.nicheIDs.contains($0.id) }
        // Match niche from the list blurb (and subject article when we have one) —
        // never from a rejected place page alone.
        let haystack = [
            pick.entry.blurb,
            pick.entry.listTitle,
            displayTitle,
            subjectSummary?.title ?? "",
            subjectSummary?.extract ?? ""
        ].joined(separator: " ")

        let matchedInterest: Interest? = {
            if !subjectCategories.isEmpty,
               let catHit = listNicheInterests.first(where: {
                   InterestMatching.categoriesMatchInterest(subjectCategories, interest: $0)
               }) {
                return catHit
            }
            if let textHit = InterestMatching.bestInterestMatch(
                in: haystack,
                selectedInterests: listNicheInterests
            )?.interest {
                return textHit
            }
            // Curated list membership + non-empty niche filter: allow the niche tied to this source.
            return listNicheInterests.first
        }()

        guard let matched = matchedInterest else {
            throw FactLoadError.noMatch
        }

        let fact = FactFactory.makeFact(
            from: pick.entry,
            listPageSummary: listPageSummary,
            articleSummary: subjectSummary,
            matchedNicheIDs: [matched.id]
        )
        if ContentSafety.isRestrictedFactText(
            title: fact.title,
            summary: fact.summary,
            highlight: fact.highlight
        ) {
            throw FactLoadError.noMatch
        }
        if TextUtils.cleanFactPlainText(fact.summary).count < 40 {
            throw FactLoadError.noMatch
        }
        if InterestMatching.isTooSimilarTitle(fact.title, toRecent: recentTitles) {
            throw FactLoadError.noMatch
        }
        let matchedLabel = interestsMode ? matched.label : "From a Wikipedia list"
        return LoadedFact(fact: fact, matchedLabel: matchedLabel)
    }

    // MARK: - List cache / pick (web `list-facts.js`)

    private func loadListEntries(listTitle: String) async -> [ListEntry] {
        if let cached = listEntryCache[listTitle] { return cached }
        do {
            let page = try await wikipedia.fetchParsedPageHTML(title: listTitle)
            let entries = ListPageParser.parseListEntries(html: page.html, listTitle: page.title)
            let pageScore = ListPageParser.scoreListPage(listTitle: page.title, entryCount: entries.count)
            let usable = pageScore >= 12 && entries.count >= 5 ? entries : []
            listEntryCache[listTitle] = usable
            return usable
        } catch {
            listEntryCache[listTitle] = []
            return []
        }
    }

    private func pickListEntry(
        nicheIDs: [String],
        seenIDs: [String],
        selectedInterests: [Interest],
        recentTitles: [String]
    ) async -> (entry: ListEntry, source: ListSource)? {
        let sources = TextUtils.shuffle(ListSources.forNicheIDs(nicheIDs))
        let relevantInterests = selectedInterests.filter { nicheIDs.contains($0.id) }
        for source in sources {
            let entries = await loadListEntries(listTitle: source.title)
            guard !entries.isEmpty else { continue }
            let unused = entries.filter { !seenIDs.contains($0.id) }
            var pool = unused.isEmpty ? entries : unused
            pool = pool.filter { entry in
                let display = FactFactory.listEntryDisplayTitle(entry)
                if ContentSafety.isRestrictedFactText(
                    title: display,
                    summary: entry.blurb,
                    highlight: ""
                ) { return false }
                if InterestMatching.isTooSimilarTitle(display, toRecent: recentTitles) {
                    return false
                }
                // Prefer entries whose blurb actually smells like the niche.
                let sourceInterests = relevantInterests.filter { source.nicheIDs.contains($0.id) }
                guard !sourceInterests.isEmpty else { return true }
                let text = "\(display) \(entry.blurb) \(entry.listTitle)"
                return sourceInterests.contains {
                    InterestMatching.scoreInterestAgainstText($0, text: text) > 0
                }
            }
            guard !pool.isEmpty else { continue }
            pool.sort { a, b in
                // Prefer entries whose linked subject isn't a hometown/city.
                let aPlace = ListPageParser.isPlaceLikeWikiTitle(a.articleTitle)
                let bPlace = ListPageParser.isPlaceLikeWikiTitle(b.articleTitle)
                if aPlace != bPlace { return !aPlace }
                if a.score != b.score { return a.score > b.score }
                return Bool.random()
            }
            let topCount = max(5, Int(ceil(Double(pool.count) / 3.0)))
            let top = Array(pool.prefix(topCount))
            if let entry = TextUtils.pickRandom(top) {
                return (entry, source)
            }
        }
        return nil
    }
}
