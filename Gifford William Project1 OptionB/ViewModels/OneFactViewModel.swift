import Combine
import Foundation
import SwiftUI

@MainActor
final class OneFactViewModel: ObservableObject {
    enum Screen: Hashable {
        case landing
        case learn
        case saved
        case interests
        case challenge
    }

    enum ChallengePhase: Equatable {
        case intro
        case loading
        case reading
        case quiz
        case results
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum SavedSortField: String, CaseIterable, Identifiable {
        case dateAdded
        case name

        var id: String { rawValue }

        var label: String {
            switch self {
            case .dateAdded: "Added"
            case .name: "Name"
            }
        }
    }

    private let wikipedia: WikipediaService
    private let factLoader: FactLoader
    private var persistTask: Task<Void, Never>?

    @Published var screen: Screen = .landing
    @Published var mode: FactMode = .random
    @Published var selectedIDs: [String] = []
    @Published var additions: [Interest] = []
    @Published var seenIDs: [String] = []
    @Published var saved: [Fact] = []
    @Published var heartedIDs: [String] = []
    @Published var challengesCompleted = 0
    /// Recent finished Challenge sessions (newest first) for the intro list.
    @Published var challengeHistory: [ChallengeSessionRecord] = []
    @Published var expandedParentIDs: Set<String> = []
    @Published var currentFact: Fact?
    @Published var loadState: LoadState = .idle
    @Published var toastMessage: String?
    @Published var matchedTopicLabel: String?
    @Published var isCardFlipped = false
    @Published var factDetail: FactDetail?
    @Published var isLoadingDetail = false
    @Published var detailFailed = false
    /// Saved tab: list → opened card (nil = browsing the list).
    @Published var selectedSavedID: String?
    @Published var savedFlippedID: String?
    @Published var savedDetailLoadingID: String?
    @Published var savedDetailFailedID: String?
    @Published var savedSearchText = ""
    @Published var savedSortField: SavedSortField = .dateAdded
    @Published var savedSortAscending = false
    @Published var showHeartSheet = false
    @Published var isLoadingHeartSuggestions = false
    @Published var heartSuggestions: [Interest] = []
    @Published var selectedHeartSuggestionIDs: Set<String> = []
    @Published var completedFactIDs: [String] = []
    @Published var factHistory: [Fact] = []
    @Published var dailyChallenge: DailyChallengeState?
    @Published var challengePhase: ChallengePhase = .intro
    /// Random or Interests — chosen on the Challenge intro screen (independent of Learn).
    @Published var challengeDeckMode: FactMode = .random
    @Published var challengeLoadProgress = 0
    @Published var challengeLoadTotal = DailyChallengeState.deckSize
    @Published var challengeFlipped = false
    @Published var challengeDetail: FactDetail?
    @Published var challengeDetailLoading = false
    @Published var challengeDetailFailed = false
    @Published var quizQuestions: [QuizQuestion] = []
    @Published var quizIndex = 0
    @Published var quizSelectedOption: Int? = nil
    @Published var quizAnswers: [String: Int] = [:]
    @Published var selectedHistoryID: String?
    @Published var historyFlipped = false
    /// Saved tab showing History instead of the bookmark list.
    @Published var showHistory = false
    /// Session-complete list → opened fact (nil = browsing the list).
    @Published var selectedChallengeReviewID: String?
    @Published private(set) var didRestore = false
    private var detailTask: Task<Void, Never>?
    private var detailCache: [String: FactDetail] = [:]
    private var challengeLoadTask: Task<Void, Never>?
    /// Fact the sparkles sheet is targeting (Learn, Challenge, Saved, or History).
    private var heartTargetFactID: String?

    var selectedInterests: [Interest] {
        selectedIDs.compactMap { id in
            InterestCatalog.leaf(id: id) ?? additions.first { $0.id == id }
        }
    }

    /// Niches you typed yourself, not currently selected.
    var availableHandwrittenAdditions: [Interest] {
        additions.filter { $0.source == .custom && !selectedIDs.contains($0.id) }
    }

    /// Sparkle / “more like this” niches, not currently selected.
    var availableGeneratedAdditions: [Interest] {
        additions.filter { $0.source == .addition && !selectedIDs.contains($0.id) }
    }

    /// Interests mode only sticks when at least one niche is selected.
    var effectiveMode: FactMode {
        mode == .interests && !selectedInterests.isEmpty ? .interests : .random
    }

    var hasLoadedFact: Bool {
        currentFact != nil || loadState == .loaded || loadState == .loading
    }

    var homeStatsLabel: String {
        "\(seenIDs.count) Facts Seen · \(saved.count) Facts Saved · \(challengesCompleted) Quizzes Taken"
    }

    init(wikipedia: WikipediaService = WikipediaService()) {
        self.wikipedia = wikipedia
        self.factLoader = FactLoader(wikipedia: wikipedia)
    }

    // MARK: - Persistence

    func restoreIfNeeded() {
        guard !didRestore else { return }
        didRestore = true

        let state = PersistenceStore.load()
        selectedIDs = Self.migrateSelectedIDs(state.selectedIDs)
        additions = state.additions
        seenIDs = state.seenIDs
        saved = state.saved
        heartedIDs = state.heartedIDs
        completedFactIDs = state.completedFactIDs
        factHistory = state.factHistory
        challengesCompleted = state.challengesCompleted
        challengeHistory = state.challengeHistory
        // Default to Random when nothing is selected.
        mode = (state.mode == .interests && !selectedInterests.isEmpty) ? .interests : .random
        // Landing first, like the web app — don't jump back into Learn on launch.
        screen = .landing
        currentFact = nil
        loadState = .idle
        // Drop stale closer-look caches (HTML bloat / truncated extracts from older builds).
        detailCache.removeAll()
        selectedSavedID = nil
        savedFlippedID = nil
        savedDetailLoadingID = nil
        savedDetailFailedID = nil
        savedSearchText = ""
        resetCardFace()
        restoreDailyChallenge(from: state.dailyChallenge)
    }

    /// Saved list after search + sort (name or date added, asc/desc).
    var filteredSortedSaved: [Fact] {
        let query = savedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var items = saved
        if !query.isEmpty {
            items = items.filter { fact in
                fact.title.lowercased().contains(query)
                    || fact.summary.lowercased().contains(query)
                    || fact.highlight.lowercased().contains(query)
            }
        }
        items.sort { a, b in
            let ascending = savedSortAscending
            switch savedSortField {
            case .name:
                let cmp = a.title.localizedCaseInsensitiveCompare(b.title)
                return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
            case .dateAdded:
                let aDate = a.savedAt ?? .distantPast
                let bDate = b.savedAt ?? .distantPast
                return ascending ? aDate < bDate : aDate > bDate
            }
        }
        return items
    }

    var selectedSavedFact: Fact? {
        guard let selectedSavedID else { return nil }
        return saved.first { $0.id == selectedSavedID }
    }

    private func persistSoon() {
        persistTask?.cancel()
        persistTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let state = PersistedState(
                mode: mode,
                selectedIDs: selectedIDs,
                additions: additions,
                seenIDs: seenIDs,
                saved: saved,
                heartedIDs: heartedIDs,
                completedTopicIDs: [],
                completedFactIDs: completedFactIDs,
                factHistory: factHistory,
                historyIndex: -1,
                dailyChallenge: dailyChallenge,
                challengesCompleted: challengesCompleted,
                challengeHistory: challengeHistory
            )
            PersistenceStore.save(state)
        }
    }

    private func restoreDailyChallenge(from saved: DailyChallengeState?) {
        if let saved, !saved.deck.isEmpty {
            dailyChallenge = saved
            // Seed the intro list once if we have a finished session but no history yet.
            if saved.quizDone, challengeHistory.isEmpty {
                challengeHistory = [
                    ChallengeSessionRecord(
                        id: saved.dayKey,
                        finishedAt: Date(),
                        score: saved.quizScore,
                        total: saved.quizTotal,
                        mode: challengeDeckMode,
                        titles: saved.orderedDeck.map(\.title)
                    )
                ]
            }
        } else {
            dailyChallenge = nil
        }
        challengePhase = .intro
        challengeFlipped = false
        challengeDetail = nil
        challengeDetailLoading = false
        challengeDetailFailed = false
        quizIndex = 0
        quizSelectedOption = nil
        quizAnswers = [:]
        selectedHistoryID = nil
        historyFlipped = false
        showHistory = false
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    // MARK: - Navigation (matches web: landing + Saved / Learn / Interests)

    func openHome() {
        screen = .landing
    }

    func openLearn(loadIfNeeded: Bool = true) {
        screen = .learn
        if loadIfNeeded && currentFact == nil && loadState != .loading {
            Task { await loadNextFact() }
        }
    }

    func openSaved() {
        screen = .saved
        showHistory = false
        selectedHistoryID = nil
        historyFlipped = false
    }

    func openHistory() {
        screen = .saved
        showHistory = true
        selectedSavedID = nil
        selectedHistoryID = nil
        historyFlipped = false
    }

    func closeHistory() {
        showHistory = false
        selectedHistoryID = nil
        historyFlipped = false
    }

    func openSavedFact(_ fact: Fact) {
        showHistory = false
        selectedSavedID = fact.id
        savedFlippedID = nil
        savedDetailFailedID = nil
    }

    func closeSavedFact() {
        selectedSavedID = nil
        savedFlippedID = nil
        savedDetailLoadingID = nil
    }

    func toggleSavedSortField(_ field: SavedSortField) {
        if savedSortField == field {
            savedSortAscending.toggle()
        } else {
            savedSortField = field
            // Name feels natural A→Z; Added feels natural newest first.
            savedSortAscending = (field == .name)
        }
    }

    func toggleSavedSortDirection() {
        savedSortAscending.toggle()
    }

    func openInterests() {
        screen = .interests
    }

    func openChallenge() {
        screen = .challenge
    }

    var canStartInterestChallenge: Bool {
        !selectedInterests.isEmpty
    }

    var hasResumableChallenge: Bool {
        guard let challenge = dailyChallenge, !challenge.deck.isEmpty else { return false }
        return !challenge.quizDone
    }

    var hasChallengeResults: Bool {
        dailyChallenge?.quizDone == true
    }

    // MARK: - Mode & interests

    func setMode(_ newMode: FactMode) {
        if newMode == .interests && selectedInterests.isEmpty {
            mode = .random
            persistSoon()
            showToast("Select niches in Interests first")
            return
        }

        guard newMode != mode else { return }
        mode = newMode
        persistSoon()
        showToast(newMode == .interests ? "Interests mode" : "Random mode")
    }

    func toggleNiche(_ id: String) {
        if let index = selectedIDs.firstIndex(of: id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(id)
            mode = .interests
        }
        ensureRandomWhenNoInterests()
        persistSoon()
    }

    func setGroupSelection(parentID: String, selectAll: Bool) {
        let childIDs = InterestCatalog.childIDs(forParent: parentID)
        if selectAll {
            selectedIDs = Array(Set(selectedIDs + childIDs))
            mode = .interests
        } else {
            let drop = Set(childIDs)
            selectedIDs.removeAll { drop.contains($0) }
        }
        ensureRandomWhenNoInterests()
        persistSoon()
    }

    func clearAllNiches() {
        selectedIDs = []
        mode = .random
        persistSoon()
    }

    private func ensureRandomWhenNoInterests() {
        if selectedInterests.isEmpty {
            mode = .random
        }
    }

    /// Old single "parks-incidents" niche → new per-operator incident niches.
    private static func migrateSelectedIDs(_ ids: [String]) -> [String] {
        let incidentLeaves = [
            "incidents-disney", "incidents-universal", "incidents-sixflags",
            "incidents-cedarfair", "incidents-seaworld", "incidents-european",
            "incidents-independent", "incidents-other-chains"
        ]
        var result: [String] = []
        var seen = Set<String>()
        var didExpandIncidents = false
        for id in ids {
            let replacements = (id == "parks-incidents") ? incidentLeaves : [id]
            if id == "parks-incidents" {
                if didExpandIncidents { continue }
                didExpandIncidents = true
            }
            for item in replacements where seen.insert(item).inserted {
                result.append(item)
            }
        }
        return result
    }

    func toggleParentExpanded(_ parentID: String) {
        if expandedParentIDs.contains(parentID) {
            expandedParentIDs.remove(parentID)
        } else {
            expandedParentIDs.insert(parentID)
        }
    }

    func removeAddition(_ id: String) {
        additions.removeAll { $0.id == id }
        selectedIDs.removeAll { $0 == id }
        ensureRandomWhenNoInterests()
        persistSoon()
    }

    /// Create a custom niche from plain text (e.g. "LEGO").
    /// Uses the label as keywords/category hints — distinctive names work well;
    /// vague ones ("stuff") will match poorly compared to curated niches.
    @discardableResult
    func createCustomNiche(from rawName: String) -> Bool {
        let label = rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard label.count >= 2 else {
            showToast("Name needs at least 2 characters")
            return false
        }
        guard label.count <= 40 else {
            showToast("Keep names under 40 characters")
            return false
        }

        let id = "custom-\(TextUtils.slugify(label))"
        if InterestCatalog.leaf(id: id) != nil || additions.contains(where: { $0.id == id }) {
            // Already exists — just select it
            if !selectedIDs.contains(id), additions.contains(where: { $0.id == id }) {
                selectedIDs.append(id)
                mode = .interests
                persistSoon()
            }
            showToast("Already in your interests")
            return false
        }
        // Avoid colliding with a default leaf that happens to slug the same way
        if InterestCatalog.leaves.contains(where: { $0.label.compare(label, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            showToast("That niche already exists in Browse")
            return false
        }

        let interest = Self.makeCustomInterest(id: id, label: label)
        additions.insert(interest, at: 0)
        if additions.count > 40 {
            let trimmed = Array(additions.prefix(40))
            let keepIDs = Set(trimmed.map(\.id))
            additions = trimmed
            selectedIDs.removeAll { sid in
                (sid.hasPrefix("custom-") || sid.hasPrefix("add-")) && !keepIDs.contains(sid)
            }
        }
        if !selectedIDs.contains(id) {
            selectedIDs.append(id)
        }
        mode = .interests
        persistSoon()
        showToast("Added “\(label)”")
        return true
    }

    private static func makeCustomInterest(id: String, label: String) -> Interest {
        let lower = label.lowercased()
        let significant = InterestMatching.significantMatchWords(from: label)
        // Prefer the full phrase; don't let lone words ("star", "wars") match alone.
        var keywords = [lower]
        if significant.count == 1, let only = significant.first {
            keywords.append(only)
            if only.count >= 3, !only.hasSuffix("s") {
                keywords.append(only + "s")
            }
        } else if significant.count >= 2 {
            keywords.append(significant.joined(separator: " "))
        }
        return Interest(
            id: id,
            label: label,
            keywords: Array(Set(keywords)),
            categoryHints: [lower] + (significant.count >= 2 ? [significant.joined(separator: " ")] : significant.filter { $0.count >= 4 }),
            parentID: nil,
            parentLabel: "Custom",
            overview: "A niche you created. Multi-word names need all important words to match (e.g. “Star Wars”, not just “star”).",
            purpose: "Steer Learn toward topics that mention \(label).",
            symbolName: "pencil",
            source: .custom
        )
    }

    // MARK: - Facts

    func loadNextFact() async {
        guard loadState != .loading else { return }
        loadState = .loading
        currentFact = nil
        matchedTopicLabel = nil
        resetCardFace()
        screen = .learn

        ensureRandomWhenNoInterests()

        do {
            let loaded = try await factLoader.loadFact(
                interestsMode: effectiveMode == .interests,
                selectedInterests: selectedInterests,
                seenIDs: seenIDs,
                recentTitles: factHistory.prefix(12).map(\.title)
            )
            currentFact = loaded.fact
            matchedTopicLabel = loaded.matchedLabel
            if !seenIDs.contains(loaded.fact.id) {
                seenIDs.append(loaded.fact.id)
            }
            recordInHistory(loaded.fact)
            loadState = .loaded
            persistSoon()
        } catch let error as FactLoadError {
            loadState = .failed(error.errorDescription ?? "Wikipedia didn’t return a fact.")
        } catch let error as WikipediaServiceError {
            loadState = .failed(error.errorDescription ?? "Wikipedia didn’t return a fact.")
        } catch {
            loadState = .failed(
                effectiveMode == .interests
                    ? "No facts matched your interests. Add more niches or try Random."
                    : "Wikipedia didn’t return a fact. Try again."
            )
        }
    }

    func toggleCardFlip() {
        guard currentFact != nil else { return }
        let willShowBack = !isCardFlipped
        withAnimation(.easeInOut(duration: 0.45)) {
            isCardFlipped = willShowBack
        }
        if willShowBack {
            Task { await loadFactDetailIfNeeded() }
        }
    }

    func loadFactDetailIfNeeded() async {
        guard let fact = currentFact else { return }
        await loadDetail(for: fact, assignToLearn: true)
    }

    func toggleSavedCardFlip(_ fact: Fact) {
        guard selectedSavedID == fact.id else {
            openSavedFact(fact)
            return
        }
        let willShowBack = savedFlippedID != fact.id
        withAnimation(.easeInOut(duration: 0.35)) {
            savedFlippedID = willShowBack ? fact.id : nil
        }
        if willShowBack {
            Task { await loadDetail(for: fact, assignToLearn: false) }
        }
    }

    func savedDetail(for id: String) -> FactDetail? {
        detailCache[id]
    }

    func isSavedDetailLoading(_ id: String) -> Bool {
        savedDetailLoadingID == id
    }

    func didSavedDetailFail(_ id: String) -> Bool {
        savedDetailFailedID == id && detailCache[id] == nil
    }

    private func loadDetail(for fact: Fact, assignToLearn: Bool) async {
        if let cached = detailCache[fact.id] {
            if assignToLearn {
                factDetail = cached
                detailFailed = false
                isLoadingDetail = false
            }
            savedDetailFailedID = nil
            return
        }

        if assignToLearn {
            guard !isLoadingDetail else { return }
            isLoadingDetail = true
            detailFailed = false
        } else {
            savedDetailLoadingID = fact.id
            if savedDetailFailedID == fact.id { savedDetailFailedID = nil }
        }

        detailTask?.cancel()
        let lookup = fact.lookupTitle
        let factID = fact.id
        detailTask = Task { @MainActor in
            do {
                let detail = try await wikipedia.fetchArticleDetail(title: lookup)
                guard !Task.isCancelled else { return }
                detailCache[factID] = detail
                if detailCache.count > 40 {
                    detailCache = Dictionary(uniqueKeysWithValues: detailCache.suffix(30))
                }
                if assignToLearn, currentFact?.id == factID {
                    factDetail = detail
                    detailFailed = false
                }
                if savedDetailFailedID == factID {
                    savedDetailFailedID = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                if assignToLearn, currentFact?.id == factID, factDetail == nil {
                    detailFailed = true
                }
                if !assignToLearn, selectedSavedID == factID || savedFlippedID == factID {
                    savedDetailFailedID = factID
                }
            }
            if assignToLearn, currentFact?.id == factID {
                isLoadingDetail = false
            }
            if savedDetailLoadingID == factID {
                savedDetailLoadingID = nil
            }
        }
        await detailTask?.value
    }

    private func resetCardFace() {
        detailTask?.cancel()
        detailTask = nil
        isCardFlipped = false
        factDetail = nil
        isLoadingDetail = false
        detailFailed = false
    }

    func topicLabel() -> String {
        if effectiveMode == .interests {
            if let matchedTopicLabel { return matchedTopicLabel }
            return "Matched to your interests"
        }
        return "A fact for you"
    }

    func toggleSaveCurrent() {
        guard let fact = currentFact else { return }
        toggleSave(fact)
    }

    func toggleSave(_ fact: Fact) {
        if let index = saved.firstIndex(where: { $0.id == fact.id }) {
            saved.remove(at: index)
            if selectedSavedID == fact.id {
                closeSavedFact()
            }
            showToast("Removed from saved")
        } else {
            var copy = fact
            copy.savedAt = Date()
            saved.insert(copy, at: 0)
            showToast("Saved")
        }
        persistSoon()
    }

    func isSaved(_ id: String) -> Bool {
        saved.contains { $0.id == id }
    }

    func removeSaved(_ id: String) {
        saved.removeAll { $0.id == id }
        if selectedSavedID == id {
            closeSavedFact()
        }
        if savedFlippedID == id {
            savedFlippedID = nil
        }
        detailCache.removeValue(forKey: id)
        persistSoon()
        showToast("Removed from saved")
    }

    /// Filled when this fact already contributed topics via “more like this”.
    func isHearted(_ id: String) -> Bool {
        heartedIDs.contains(id)
    }

    /// Opens topic suggestions for the current Learn fact.
    func heartCurrent() async {
        guard let fact = currentFact else { return }
        await heartFact(fact)
    }

    /// Opens topic suggestions for any fact (Challenge, Saved, History, Learn).
    func heartFact(_ fact: Fact) async {
        heartTargetFactID = fact.id
        selectedHeartSuggestionIDs = []
        heartSuggestions = []
        isLoadingHeartSuggestions = true
        showHeartSheet = true

        do {
            let categories = try await wikipedia.fetchCategoryTitles(forArticleTitle: fact.lookupTitle)
            let suggestions = FactFactory.heartSuggestions(categories: categories, fact: fact, limit: 8)
            heartSuggestions = suggestions
            // Pre-select broader catalog hits; leave brand-new additions unchecked.
            selectedHeartSuggestionIDs = Set(
                suggestions
                    .filter { $0.source == .default }
                    .prefix(3)
                    .map(\.id)
            )
            isLoadingHeartSuggestions = false
            if suggestions.isEmpty {
                showToast("No broad topics found for this fact")
            }
        } catch {
            isLoadingHeartSuggestions = false
            heartSuggestions = []
            showToast("Couldn’t load topic suggestions")
        }
    }

    func toggleHeartSuggestion(_ id: String) {
        if selectedHeartSuggestionIDs.contains(id) {
            selectedHeartSuggestionIDs.remove(id)
        } else {
            selectedHeartSuggestionIDs.insert(id)
        }
    }

    /// Add checked suggestions to Your additions (available niches), without forcing Interests mode.
    func confirmHeartSuggestionsAddOnly() {
        let hadSelection = !selectedHeartSuggestionIDs.isEmpty
        let count = applyHeartSuggestions(selectForSearch: false)
        dismissHeartSheet()
        guard hadSelection else { return }
        if count == 0 {
            showToast("Already in your interests")
        } else {
            showToast(count == 1 ? "Added to Interests" : "Added \(count) to Interests")
        }
    }

    /// Add checked suggestions and select them for Interests search.
    func confirmHeartSuggestionsAddAndUse() {
        let hadSelection = !selectedHeartSuggestionIDs.isEmpty
        let count = applyHeartSuggestions(selectForSearch: true)
        dismissHeartSheet()
        guard hadSelection else { return }
        mode = .interests
        if count == 0 {
            showToast("Using your selected interests")
        } else {
            showToast(count == 1 ? "Added & selected" : "Added & selected \(count)")
        }
    }

    func dismissHeartSheet() {
        showHeartSheet = false
        heartSuggestions = []
        selectedHeartSuggestionIDs = []
        isLoadingHeartSuggestions = false
        heartTargetFactID = nil
    }

    @discardableResult
    private func applyHeartSuggestions(selectForSearch: Bool) -> Int {
        let selected = heartSuggestions.filter { selectedHeartSuggestionIDs.contains($0.id) }
        guard !selected.isEmpty else { return 0 }

        var changed = 0
        for interest in selected {
            let isCatalog = InterestCatalog.leaf(id: interest.id) != nil
            if !isCatalog, !additions.contains(where: { $0.id == interest.id }) {
                additions.insert(interest, at: 0)
                changed += 1
            }
            if selectForSearch, !selectedIDs.contains(interest.id) {
                selectedIDs.append(interest.id)
                if isCatalog { changed += 1 }
            }
        }
        if additions.count > 40 {
            additions = Array(additions.prefix(40))
        }
        // Mark only after the user confirms with at least one topic selected.
        // (Not now leaves the sparkles button inactive.)
        let factID = heartTargetFactID ?? currentFact?.id
        if let factID, !heartedIDs.contains(factID) {
            heartedIDs.append(factID)
        }
        persistSoon()
        return changed
    }

    /// Niche label for a Challenge card when the session used Interests.
    func challengeTopicLabel(for fact: Fact) -> String? {
        guard challengeDeckMode == .interests else { return nil }
        for id in fact.matchedNicheIDs {
            if let interest = selectedInterests.first(where: { $0.id == id }) {
                return interest.label
            }
            if let leaf = InterestCatalog.leaf(id: id) ?? additions.first(where: { $0.id == id }) {
                return leaf.label
            }
        }
        return "Your interests"
    }

    var shareText: String {
        currentFact?.shareText ?? ""
    }

    // MARK: - Challenge

    var challengeFact: Fact? {
        dailyChallenge?.currentFact
    }

    func isFactCompleted(_ id: String) -> Bool {
        completedFactIDs.contains(id)
    }

    func toggleFactCompleted(_ id: String) {
        if let index = completedFactIDs.firstIndex(of: id) {
            completedFactIDs.remove(at: index)
            showToast("Marked incomplete")
        } else {
            completedFactIDs.append(id)
            showToast("Marked complete")
        }
        persistSoon()
    }

    func startNewChallenge() {
        if challengeDeckMode == .interests, !canStartInterestChallenge {
            showToast("Select niches in Interests first")
            return
        }
        challengeLoadTask?.cancel()
        challengeLoadTask = Task { await loadChallengeDeck() }
    }

    func resumeChallenge() {
        guard let existing = dailyChallenge, !existing.deck.isEmpty else {
            startNewChallenge()
            return
        }
        if existing.quizDone {
            challengePhase = .results
        } else {
            challengePhase = .reading
            resetChallengeCardFace()
        }
    }

    func viewChallengeResults() {
        guard hasChallengeResults else { return }
        challengePhase = .results
    }

    func challengeGoPrevious() {
        guard var challenge = dailyChallenge, challenge.index > 0 else { return }
        challenge.index -= 1
        dailyChallenge = challenge
        resetChallengeCardFace()
        persistSoon()
    }

    func challengeGoNext() {
        guard var challenge = dailyChallenge else { return }
        let last = max(challenge.orderedDeck.count - 1, 0)
        if challenge.index < last {
            challenge.index += 1
            dailyChallenge = challenge
            resetChallengeCardFace()
            persistSoon()
        } else {
            beginChallengeQuiz()
        }
    }

    func beginChallengeQuiz() {
        guard let challenge = dailyChallenge else { return }
        let questions = QuizBuilder.makeSessionQuestions(
            deck: challenge.deck,
            decoyTitles: challenge.decoyTitles
        )
        quizQuestions = questions
        quizIndex = 0
        quizSelectedOption = nil
        quizAnswers = [:]
        if questions.isEmpty {
            // Still complete the session if we can't build any quiz questions yet.
            completeChallengeWithoutQuiz()
            return
        }
        challengePhase = .quiz
    }

    private func completeChallengeWithoutQuiz() {
        let wasAlreadyDone = dailyChallenge?.quizDone == true
        if var challenge = dailyChallenge {
            challenge.quizDone = true
            challenge.quizScore = 0
            challenge.quizTotal = 0
            dailyChallenge = challenge
        }
        if !wasAlreadyDone {
            challengesCompleted += 1
            recordFinishedChallengeSession(score: 0, total: 0)
        }
        selectedChallengeReviewID = nil
        challengePhase = .results
        persistSoon()
        showToast("Session complete")
    }

    func selectQuizOption(_ optionIndex: Int) {
        guard quizQuestions.indices.contains(quizIndex) else { return }
        // Lock in the first answer so feedback stays visible until Next.
        guard quizSelectedOption == nil else { return }
        quizSelectedOption = optionIndex
        let question = quizQuestions[quizIndex]
        quizAnswers[question.id] = optionIndex
    }

    var quizHasAnsweredCurrent: Bool {
        quizSelectedOption != nil
    }

    func submitQuizAnswerAndAdvance() {
        guard quizSelectedOption != nil else {
            showToast("Pick an answer first")
            return
        }
        if quizIndex + 1 < quizQuestions.count {
            quizIndex += 1
            quizSelectedOption = nil
        } else {
            finishChallengeQuiz()
        }
    }

    private func finishChallengeQuiz() {
        var score = 0
        for question in quizQuestions {
            if quizAnswers[question.id] == question.correctIndex {
                score += 1
            }
        }
        let wasAlreadyDone = dailyChallenge?.quizDone == true
        if var challenge = dailyChallenge {
            challenge.quizDone = true
            challenge.quizScore = score
            challenge.quizTotal = quizQuestions.count
            dailyChallenge = challenge
        }
        // Count each finished quiz once (retakes after reset still count as new completions).
        if !wasAlreadyDone {
            challengesCompleted += 1
            recordFinishedChallengeSession(score: score, total: quizQuestions.count)
        }
        selectedChallengeReviewID = nil
        challengePhase = .results
        persistSoon()
        let perfect = !quizQuestions.isEmpty && score == quizQuestions.count
        showToast(perfect ? "Perfect score!" : "Quiz complete")
        // Play after the results transition so audio never races the view update.
        if perfect {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                CelebrationSound.playPerfectQuiz()
            }
        }
    }

    private func recordFinishedChallengeSession(score: Int, total: Int) {
        guard let challenge = dailyChallenge else { return }
        let record = ChallengeSessionRecord(
            id: challenge.dayKey,
            finishedAt: Date(),
            score: score,
            total: total,
            mode: challengeDeckMode,
            titles: challenge.orderedDeck.map(\.title)
        )
        challengeHistory.removeAll { $0.id == record.id }
        challengeHistory.insert(record, at: 0)
        if challengeHistory.count > 20 {
            challengeHistory = Array(challengeHistory.prefix(20))
        }
    }

    func retakeChallengeQuiz() {
        guard let challenge = dailyChallenge else { return }
        let questions = QuizBuilder.makeSessionQuestions(
            deck: challenge.deck,
            decoyTitles: challenge.decoyTitles
        )
        quizQuestions = questions
        quizIndex = 0
        quizSelectedOption = nil
        quizAnswers = [:]
        selectedChallengeReviewID = nil
        if questions.isEmpty {
            showToast("Need a bit more history for a recall check")
            return
        }
        if var updated = dailyChallenge {
            updated.quizDone = false
            updated.quizScore = 0
            dailyChallenge = updated
        }
        challengePhase = .quiz
        persistSoon()
    }

    func reviewChallengeDeck() {
        selectedChallengeReviewID = nil
        guard var challenge = dailyChallenge, !challenge.deck.isEmpty else { return }
        challenge.index = 0
        dailyChallenge = challenge
        challengePhase = .reading
        resetChallengeCardFace()
        persistSoon()
    }

    var selectedChallengeReviewFact: Fact? {
        guard let selectedChallengeReviewID else { return nil }
        return dailyChallenge?.orderedDeck.first { $0.id == selectedChallengeReviewID }
            ?? dailyChallenge?.deck.first { $0.id == selectedChallengeReviewID }
    }

    func openChallengeReviewFact(_ fact: Fact) {
        selectedChallengeReviewID = fact.id
        challengeFlipped = false
        challengeDetail = detailCache[fact.id]
        challengeDetailLoading = false
        challengeDetailFailed = false
    }

    func closeChallengeReviewFact() {
        selectedChallengeReviewID = nil
        challengeFlipped = false
        challengeDetail = nil
        challengeDetailLoading = false
        challengeDetailFailed = false
    }

    func toggleChallengeReviewCardFlip() {
        guard let fact = selectedChallengeReviewFact else { return }
        let willShowBack = !challengeFlipped
        withAnimation(.easeInOut(duration: 0.35)) {
            challengeFlipped = willShowBack
        }
        if willShowBack {
            Task { await loadChallengeDetail(for: fact) }
        }
    }

    func openHistoryFact(_ fact: Fact) {
        selectedHistoryID = fact.id
        historyFlipped = false
    }

    func closeHistoryFact() {
        selectedHistoryID = nil
        historyFlipped = false
    }

    func toggleHistoryCardFlip() {
        guard let id = selectedHistoryID,
              let fact = factHistory.first(where: { $0.id == id }) else { return }
        let willShowBack = !historyFlipped
        withAnimation(.easeInOut(duration: 0.35)) {
            historyFlipped = willShowBack
        }
        if willShowBack {
            Task { await loadDetail(for: fact, assignToLearn: false) }
        }
    }

    var selectedHistoryFact: Fact? {
        guard let selectedHistoryID else { return nil }
        return factHistory.first { $0.id == selectedHistoryID }
    }

    func toggleChallengeCardFlip() {
        guard let fact = challengeFact else { return }
        let willShowBack = !challengeFlipped
        withAnimation(.easeInOut(duration: 0.45)) {
            challengeFlipped = willShowBack
        }
        if willShowBack {
            Task { await loadChallengeDetail(for: fact) }
        }
    }

    private func loadChallengeDetail(for fact: Fact) async {
        if let cached = detailCache[fact.id] {
            challengeDetail = cached
            challengeDetailFailed = false
            challengeDetailLoading = false
            return
        }
        challengeDetailLoading = true
        challengeDetailFailed = false
        do {
            let detail = try await wikipedia.fetchArticleDetail(title: fact.lookupTitle)
            detailCache[fact.id] = detail
            if isShowingChallengeFact(fact.id) {
                challengeDetail = detail
                challengeDetailFailed = false
            }
        } catch {
            if isShowingChallengeFact(fact.id), challengeDetail == nil {
                challengeDetailFailed = true
            }
        }
        if isShowingChallengeFact(fact.id) {
            challengeDetailLoading = false
        }
    }

    private func isShowingChallengeFact(_ id: String) -> Bool {
        challengeFact?.id == id || selectedChallengeReviewID == id
    }

    private func resetChallengeCardFace() {
        challengeFlipped = false
        challengeDetail = nil
        challengeDetailLoading = false
        challengeDetailFailed = false
        if let fact = challengeFact, let cached = detailCache[fact.id] {
            challengeDetail = cached
        }
    }

    private func recordInHistory(_ fact: Fact) {
        factHistory.removeAll { $0.id == fact.id }
        factHistory.insert(fact, at: 0)
        if factHistory.count > 80 {
            factHistory = Array(factHistory.prefix(80))
        }
    }

    private func loadChallengeDeck() async {
        let useInterests = challengeDeckMode == .interests && canStartInterestChallenge
        challengePhase = .loading
        // UI always shows 5 — the extra Wikipedia pulls for decoys stay invisible.
        challengeLoadProgress = 0
        challengeLoadTotal = DailyChallengeState.deckSize

        var pool: [Fact] = []
        var localSeen = Set(seenIDs)
        var failures = 0
        let poolTarget = DailyChallengeState.fetchPoolSize

        while pool.count < poolTarget, failures < 14 {
            if Task.isCancelled { return }
            do {
                let loaded = try await factLoader.loadFact(
                    interestsMode: useInterests,
                    selectedInterests: useInterests ? selectedInterests : [],
                    seenIDs: Array(localSeen),
                    recentTitles: pool.map(\.title) + factHistory.prefix(8).map(\.title)
                )
                localSeen.insert(loaded.fact.id)
                // Quietly skip Wikipedia list-page facts in Challenge.
                if loaded.fact.source == .list {
                    failures += 1
                    continue
                }
                if pool.contains(where: { $0.id == loaded.fact.id }) {
                    failures += 1
                    continue
                }
                let title = loaded.fact.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else {
                    failures += 1
                    continue
                }
                pool.append(loaded.fact)
                // Map silent pool progress onto a 1…5 display.
                challengeLoadProgress = min(
                    DailyChallengeState.deckSize,
                    max(1, Int(round(Double(pool.count) / Double(poolTarget) * Double(DailyChallengeState.deckSize))))
                )
                failures = 0
            } catch {
                failures += 1
            }
        }

        guard !Task.isCancelled else { return }

        let built = Self.buildChallengeDeckAndDecoys(from: pool)
        guard built.deck.count >= 3 else {
            challengePhase = .intro
            showToast(
                useInterests
                    ? "Not enough interest matches — try Random or add niches"
                    : "Couldn’t load enough facts — try again"
            )
            return
        }

        challengeLoadProgress = DailyChallengeState.deckSize

        for fact in built.deck {
            if !seenIDs.contains(fact.id) {
                seenIDs.append(fact.id)
            }
            recordInHistory(fact)
        }

        let sessionKey = DailyChallengeState.dayKey() + "-\(Int(Date().timeIntervalSince1970))"
        dailyChallenge = DailyChallengeState.fresh(
            dayKey: sessionKey,
            deck: built.deck,
            decoyTitles: built.decoyTitles
        )
        challengePhase = .reading
        resetChallengeCardFace()
        persistSoon()
        showToast(useInterests ? "Interest deck ready" : "Random deck ready")
    }

    /// Split a fetched pool into a 5-card reading deck + unused titles for quiz wrong answers.
    /// Very short blurbs become decoys; prefer including at least one imaged fact in the deck.
    private static func buildChallengeDeckAndDecoys(from pool: [Fact]) -> (deck: [Fact], decoyTitles: [String]) {
        let target = DailyChallengeState.deckSize
        var shortPool: [Fact] = []
        var solidPool: [Fact] = []
        for fact in pool {
            if isChallengeDecoyOnly(fact) {
                shortPool.append(fact)
            } else {
                solidPool.append(fact)
            }
        }

        var deck: [Fact] = []
        // Prefer a solid fact with an image so the image→title question can run.
        if let imaged = TextUtils.shuffle(solidPool.filter { $0.imageURL != nil }).first {
            deck.append(imaged)
        }

        let remainingSolid = TextUtils.shuffle(solidPool.filter { fact in
            !deck.contains(where: { $0.id == fact.id })
        })
        for fact in remainingSolid where deck.count < target {
            deck.append(fact)
        }

        // Never promote ultra-short cards into the reading deck — they stay decoys only.
        // If we somehow lack 5 solid facts, keep a smaller deck rather than quiz on stubs.

        let deckIDs = Set(deck.map(\.id))
        var decoyTitles: [String] = []
        var decoySeen = Set(deck.map { $0.title.lowercased() })
        // Short leftovers first (they were pulled to be wrong answers).
        for fact in shortPool + solidPool {
            guard !deckIDs.contains(fact.id) else { continue }
            let title = fact.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = title.lowercased()
            guard !title.isEmpty, decoySeen.insert(key).inserted else { continue }
            decoyTitles.append(title)
        }

        return (deck, decoyTitles)
    }

    /// Super-short cards (≤2 sentences) are decoy-only — not quizzed as the “correct” subject.
    private static func isChallengeDecoyOnly(_ fact: Fact) -> Bool {
        let body = [fact.summary, fact.highlight]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let sentences = TextUtils.sentenceCount(in: body)
        return sentences > 0 && sentences <= DailyChallengeState.maxDecoySentenceCount
    }
}
