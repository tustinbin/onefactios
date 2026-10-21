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
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
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
    @Published var expandedParentIDs: Set<String> = []
    @Published var currentFact: Fact?
    @Published var loadState: LoadState = .idle
    @Published var toastMessage: String?
    @Published var matchedTopicLabel: String?
    @Published var isCardFlipped = false
    @Published var factDetail: FactDetail?
    @Published var isLoadingDetail = false
    @Published var detailFailed = false
    @Published private(set) var didRestore = false
    private var detailTask: Task<Void, Never>?
    private var detailCache: [String: FactDetail] = [:]

    var selectedInterests: [Interest] {
        selectedIDs.compactMap { id in
            InterestCatalog.leaf(id: id) ?? additions.first { $0.id == id }
        }
    }

    /// Interests mode only sticks when at least one niche is selected.
    var effectiveMode: FactMode {
        mode == .interests && !selectedInterests.isEmpty ? .interests : .random
    }

    var hasLoadedFact: Bool {
        currentFact != nil || loadState == .loaded || loadState == .loading
    }

    var homeStatsLabel: String {
        let nicheCount = selectedIDs.count
        let nicheBit = nicheCount == 0
            ? "no niches selected"
            : "\(nicheCount) niche\(nicheCount == 1 ? "" : "s") selected"
        return "\(saved.count) saved · \(seenIDs.count) facts seen · \(nicheBit)"
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
        // Default to Random when nothing is selected.
        mode = (state.mode == .interests && !selectedInterests.isEmpty) ? .interests : .random
        // Landing first, like the web app — don't jump back into Learn on launch.
        screen = .landing
        currentFact = nil
        loadState = .idle
        resetCardFace()
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
                completedFactIDs: [],
                factHistory: [],
                historyIndex: -1
            )
            PersistenceStore.save(state)
        }
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
    }

    func openInterests() {
        screen = .interests
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
        let parts = lower
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 }
        var keywords = Array(Set([lower] + parts))
        // Soft expansions for common short brands / plurals
        if lower.count >= 3, !lower.hasSuffix("s") {
            keywords.append(lower + "s")
        }
        return Interest(
            id: id,
            label: label,
            keywords: keywords,
            categoryHints: [lower] + parts.filter { $0.count >= 4 },
            parentID: nil,
            parentLabel: "Custom",
            overview: "A niche you created. Matching uses “\(label)” as a keyword against Did You Know hooks and Wikipedia categories.",
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
                seenIDs: seenIDs
            )
            currentFact = loaded.fact
            matchedTopicLabel = loaded.matchedLabel
            if !seenIDs.contains(loaded.fact.id) {
                seenIDs.append(loaded.fact.id)
            }
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
        if let cached = detailCache[fact.id] {
            factDetail = cached
            detailFailed = false
            isLoadingDetail = false
            return
        }
        if isLoadingDetail { return }

        isLoadingDetail = true
        detailFailed = false
        detailTask?.cancel()
        let lookup = fact.lookupTitle
        let factID = fact.id
        detailTask = Task { @MainActor in
            do {
                let detail = try await wikipedia.fetchArticleDetail(title: lookup)
                guard !Task.isCancelled, currentFact?.id == factID else { return }
                detailCache[factID] = detail
                if detailCache.count > 40 {
                    detailCache = Dictionary(uniqueKeysWithValues: detailCache.suffix(30))
                }
                factDetail = detail
                detailFailed = false
            } catch {
                guard !Task.isCancelled, currentFact?.id == factID else { return }
                detailFailed = factDetail == nil
            }
            if currentFact?.id == factID {
                isLoadingDetail = false
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
        guard var fact = currentFact else { return }
        if let index = saved.firstIndex(where: { $0.id == fact.id }) {
            saved.remove(at: index)
            showToast("Removed from saved")
        } else {
            fact.savedAt = Date()
            saved.insert(fact, at: 0)
            showToast("Saved")
        }
        persistSoon()
    }

    func isSaved(_ id: String) -> Bool {
        saved.contains { $0.id == id }
    }

    func removeSaved(_ id: String) {
        saved.removeAll { $0.id == id }
        persistSoon()
        showToast("Removed from saved")
    }

    func isHearted(_ id: String) -> Bool {
        heartedIDs.contains(id)
    }

    func heartCurrent() async {
        guard let fact = currentFact else { return }
        if heartedIDs.contains(fact.id) {
            heartedIDs.removeAll { $0 == fact.id }
            showToast("Removed")
            persistSoon()
            return
        }
        heartedIDs.append(fact.id)
        persistSoon()

        do {
            let categories = try await wikipedia.fetchCategoryTitles(forArticleTitle: fact.lookupTitle)
            var added = 0
            for title in categories {
                guard let interest = FactFactory.interestFromCategoryTitle(title) else { continue }
                if InterestCatalog.leaf(id: interest.id) != nil { continue }
                if additions.contains(where: { $0.id == interest.id }) { continue }
                additions.insert(interest, at: 0)
                added += 1
                if added >= 4 { break }
            }
            showToast(added > 1 ? "Added \(added) to interests" : "Added to interests")
            persistSoon()
        } catch {
            showToast("Added to interests")
        }
    }

    var shareText: String {
        currentFact?.shareText ?? ""
    }
}
