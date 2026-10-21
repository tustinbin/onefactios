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
        seenIDs: [String]
    ) async throws -> LoadedFact {
        let nicheIDs = selectedInterests.map(\.id)
        let listSources = ListSources.forNicheIDs(nicheIDs)

        // Interests niches with curated lists: often try lists first (DYK is sparse there)
        if interestsMode, !listSources.isEmpty, Double.random(in: 0..<1) < 0.55 {
            if let listPick = await pickListEntry(nicheIDs: nicheIDs, seenIDs: seenIDs) {
                return try await presentListFact(listPick, selectedInterests: selectedInterests, interestsMode: interestsMode)
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
                    result = await pickInterestHook(hooks, selectedInterests: selectedInterests, seenIDs: seenIDs)
                } else {
                    result = InterestMatching.chooseHook(
                        hooks,
                        interestsMode: false,
                        seenIDs: seenIDs,
                        selectedInterests: []
                    )
                }

                if let hook = result.hook, !ContentSafety.isRestrictedTitle(hook.articleTitle) {
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
                    selectedInterests: interestsMode ? selectedInterests : []
                )
            } catch {
                // Restricted / bad page — keep going to list fallback or another attempt path.
                lastError = error
            }
        }

        // List pages are Interests-only — Random stays pure DYK
        if interestsMode {
            if let listPick = await pickListEntry(nicheIDs: nicheIDs, seenIDs: seenIDs) {
                return try await presentListFact(listPick, selectedInterests: selectedInterests, interestsMode: true)
            }
            if !selectedInterests.isEmpty {
                throw FactLoadError.noMatch
            }
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
                let verified = candidate.matched.filter { item in
                    InterestMatching.categoriesMatchInterest(categories, interest: item.interest)
                }
                if let first = verified.first {
                    return (candidate.hook, first.interest.label)
                }
            } catch {
                // Web: if category verify fails but keyword score is very strong, accept.
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
        selectedInterests: [Interest]
    ) async throws -> LoadedFact {
        if ContentSafety.isRestrictedTitle(hook.articleTitle) {
            throw FactLoadError.noMatch
        }
        let summary = try? await wikipedia.fetchSummary(title: hook.articleTitle)
        if ContentSafety.isRestrictedSummary(summary) {
            throw FactLoadError.noMatch
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
        interestsMode: Bool
    ) async throws -> LoadedFact {
        // Image + Read more come from the curated **list page**, not a blurb hyperlink
        // (those links are often tangents like "Autopsy").
        let listPageSummary = try? await wikipedia.fetchSummary(title: pick.entry.listTitle)
        let matchedFromSelection = selectedInterests.filter { pick.source.nicheIDs.contains($0.id) }
        let matchedNicheIDs = matchedFromSelection.map(\.id)
        let matchedLabel = matchedFromSelection.first?.label
            ?? (interestsMode ? "Wikipedia list" : "From a Wikipedia list")
        let fact = FactFactory.makeFact(
            from: pick.entry,
            listPageSummary: listPageSummary,
            matchedNicheIDs: matchedNicheIDs
        )
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

    private func pickListEntry(nicheIDs: [String], seenIDs: [String]) async -> (entry: ListEntry, source: ListSource)? {
        let sources = TextUtils.shuffle(ListSources.forNicheIDs(nicheIDs))
        for source in sources {
            let entries = await loadListEntries(listTitle: source.title)
            guard !entries.isEmpty else { continue }
            let unused = entries.filter { !seenIDs.contains($0.id) }
            var pool = unused.isEmpty ? entries : unused
            pool = pool.filter {
                !ContentSafety.isRestrictedTitle($0.articleTitle)
                    && !ContentSafety.isRestrictedFactText(
                        title: $0.articleTitle,
                        summary: $0.blurb,
                        highlight: ""
                    )
            }
            guard !pool.isEmpty else { continue }
            pool.sort { a, b in
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
