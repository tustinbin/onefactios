import Foundation

/// Lightweight row for the Challenge intro “recent sessions” list.
struct ChallengeSessionRecord: Identifiable, Codable, Equatable {
    let id: String
    let finishedAt: Date
    let score: Int
    let total: Int
    let mode: FactMode
    let titles: [String]

    var scoreLabel: String {
        "\(score)/\(max(total, 1))"
    }
}

/// A short Challenge session: read a small deck, then a light recall check.
struct DailyChallengeState: Codable, Equatable {
    var dayKey: String
    var deck: [Fact]
    var order: [Int]
    var index: Int
    /// Kept for persistence compatibility; Challenge UI no longer uses studied checkmarks.
    var studiedIDs: [String]
    var quizDone: Bool
    var quizScore: Int
    var quizTotal: Int
    /// Unused Wikipedia titles loaded with the deck — recognition-quiz decoys (not history).
    var decoyTitles: [String]

    static let deckSize = 5
    /// Total Wikipedia facts fetched per session (deck + quiz decoys). Loading UI still shows 5.
    static let fetchPoolSize = 13
    /// Extra titles for wrong answers (fetchPoolSize − deckSize).
    static let decoyPoolSize = fetchPoolSize - deckSize
    /// Card copy this short (or shorter) is decoy-only — not used as a reading/quiz subject.
    static let maxDecoySentenceCount = 2
    /// Up to 5: 2 recognition + 2 excerpt + 1 image→title (when a deck fact has an image).
    static let quizSize = 5
    static let recognitionQuizCount = 2
    static let excerptQuizCount = 2
    static let imageQuizCount = 1

    enum CodingKeys: String, CodingKey {
        case dayKey, deck, order, index, studiedIDs
        case quizDone, quizScore, quizTotal, decoyTitles
    }

    init(
        dayKey: String,
        deck: [Fact],
        order: [Int],
        index: Int,
        studiedIDs: [String],
        quizDone: Bool,
        quizScore: Int,
        quizTotal: Int,
        decoyTitles: [String]
    ) {
        self.dayKey = dayKey
        self.deck = deck
        self.order = order
        self.index = index
        self.studiedIDs = studiedIDs
        self.quizDone = quizDone
        self.quizScore = quizScore
        self.quizTotal = quizTotal
        self.decoyTitles = decoyTitles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try c.decode(String.self, forKey: .dayKey)
        deck = try c.decode([Fact].self, forKey: .deck)
        order = try c.decode([Int].self, forKey: .order)
        index = try c.decode(Int.self, forKey: .index)
        studiedIDs = try c.decodeIfPresent([String].self, forKey: .studiedIDs) ?? []
        quizDone = try c.decode(Bool.self, forKey: .quizDone)
        quizScore = try c.decode(Int.self, forKey: .quizScore)
        quizTotal = try c.decode(Int.self, forKey: .quizTotal)
        decoyTitles = try c.decodeIfPresent([String].self, forKey: .decoyTitles) ?? []
    }

    static func dayKey(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func fresh(dayKey: String, deck: [Fact], decoyTitles: [String] = []) -> DailyChallengeState {
        DailyChallengeState(
            dayKey: dayKey,
            deck: deck,
            order: Array(deck.indices),
            index: 0,
            studiedIDs: [],
            quizDone: false,
            quizScore: 0,
            quizTotal: quizSize,
            decoyTitles: decoyTitles
        )
    }

    var orderedDeck: [Fact] {
        order.compactMap { idx in
            guard deck.indices.contains(idx) else { return nil }
            return deck[idx]
        }
    }

    var currentFact: Fact? {
        let ordered = orderedDeck
        guard ordered.indices.contains(index) else { return nil }
        return ordered[index]
    }

    var progressLabel: String {
        let total = max(orderedDeck.count, 1)
        return "\(min(index + 1, total)) / \(total)"
    }
}

struct QuizQuestion: Identifiable, Equatable {
    let id: String
    let prompt: String
    /// Redacted blurb for excerpt→title questions; nil otherwise.
    let excerpt: String?
    /// Thumbnail for image→title questions; nil otherwise.
    let imageURL: URL?
    let options: [String]
    let correctIndex: Int
    let factID: String
}

enum QuizBuilder {
    /// Full Challenge check: recognition + excerpt + optional image→title.
    static func makeSessionQuestions(
        deck: [Fact],
        decoyTitles: [String]
    ) -> [QuizQuestion] {
        // List-page facts are excluded from Challenge decks; filter again for safety.
        let quizDeck = deck.filter { $0.source != .list }
        let recognition = makeRecognitionQuestions(
            deck: quizDeck,
            decoyTitles: decoyTitles,
            count: DailyChallengeState.recognitionQuizCount
        )
        var usedIDs = Set(recognition.map(\.factID))
        let excerpts = makeExcerptQuestions(
            deck: quizDeck,
            count: DailyChallengeState.excerptQuizCount,
            excludingIDs: usedIDs
        )
        usedIDs.formUnion(excerpts.map(\.factID))
        let images = makeImageQuestions(
            deck: quizDeck,
            decoyTitles: decoyTitles,
            count: DailyChallengeState.imageQuizCount,
            excludingIDs: usedIDs
        )
        return recognition + excerpts + images
    }

    /// Shared decoy pool: unused Wikipedia titles, never the user’s history.
    private static func decoyPool(for deck: [Fact], decoyTitles: [String]) -> [String] {
        let deckTitleSet = Set(deck.map { $0.title.lowercased() })
        var decoySeen = Set<String>()
        var pool: [String] = []
        for title in decoyTitles {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !key.isEmpty, !deckTitleSet.contains(key), decoySeen.insert(key).inserted else { continue }
            pool.append(trimmed)
        }
        if pool.count < 3 {
            for fact in deck {
                let key = fact.title.lowercased()
                guard !key.isEmpty, decoySeen.insert(key).inserted else { continue }
                pool.append(fact.title)
            }
        }
        return pool
    }

    /// Title recognition — “Which of these was in this session?”
    static func makeRecognitionQuestions(
        deck: [Fact],
        decoyTitles: [String],
        count: Int = DailyChallengeState.recognitionQuizCount
    ) -> [QuizQuestion] {
        let deckFacts = deck.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !deckFacts.isEmpty else { return [] }

        let decoys = decoyPool(for: deckFacts, decoyTitles: decoyTitles)
        let picks = Array(TextUtils.shuffle(deckFacts).prefix(count))
        return picks.compactMap { fact -> QuizQuestion? in
            titledOptionsQuestion(
                idPrefix: "rec",
                fact: fact,
                prompt: "Which of these was in this session?",
                decoyPool: decoys,
                imageURL: nil,
                excerpt: nil
            )
        }
    }

    /// Image → title when a session fact has a thumbnail.
    static func makeImageQuestions(
        deck: [Fact],
        decoyTitles: [String],
        count: Int = DailyChallengeState.imageQuizCount,
        excludingIDs: Set<String> = []
    ) -> [QuizQuestion] {
        let withImage = deck.filter {
            $0.imageURL != nil
                && !excludingIDs.contains($0.id)
                && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !withImage.isEmpty else { return [] }

        let decoys = decoyPool(for: deck, decoyTitles: decoyTitles)
        let picks = Array(TextUtils.shuffle(withImage).prefix(count))
        return picks.compactMap { fact -> QuizQuestion? in
            guard let imageURL = fact.imageURL else { return nil }
            return titledOptionsQuestion(
                idPrefix: "img",
                fact: fact,
                prompt: "Which article is this?",
                decoyPool: decoys,
                imageURL: imageURL,
                excerpt: nil
            )
        }
    }

    private static func titledOptionsQuestion(
        idPrefix: String,
        fact: Fact,
        prompt: String,
        decoyPool: [String],
        imageURL: URL?,
        excerpt: String?
    ) -> QuizQuestion? {
        var distractors = TextUtils.shuffle(
            decoyPool.filter { $0.caseInsensitiveCompare(fact.title) != .orderedSame }
        )
        distractors = Array(distractors.prefix(3))
        guard !distractors.isEmpty else { return nil }

        var options = TextUtils.shuffle(distractors + [fact.title])
        guard let correctIndex = options.firstIndex(of: fact.title) else { return nil }

        return QuizQuestion(
            id: "\(idPrefix)-\(fact.id)",
            prompt: prompt,
            excerpt: excerpt,
            imageURL: imageURL,
            options: options,
            correctIndex: correctIndex,
            factID: fact.id
        )
    }

    /// Excerpt → title using options from every fact in this session’s deck.
    static func makeExcerptQuestions(
        deck: [Fact],
        count: Int = DailyChallengeState.excerptQuizCount,
        excludingIDs: Set<String> = []
    ) -> [QuizQuestion] {
        let titled = deck.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard titled.count >= 2 else { return [] }

        let withCopy = titled.filter {
            !$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !$0.highlight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !withCopy.isEmpty else { return [] }

        let preferred = withCopy.filter { !excludingIDs.contains($0.id) }
        let pool = preferred.count >= count ? preferred : withCopy
        let picks = Array(TextUtils.shuffle(pool).prefix(count))
        let sessionTitles = titled.map(\.title)

        return picks.compactMap { fact -> QuizQuestion? in
            let raw = fact.highlight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? fact.summary
                : fact.highlight
            let excerpt = redactTitleLeak(in: raw, title: fact.title, also: fact.lookupTitle)
            let clipped = clipExcerpt(excerpt)
            guard clipped.count >= 36 else { return nil }

            var options = TextUtils.shuffle(sessionTitles)
            guard let correctIndex = options.firstIndex(of: fact.title) else { return nil }

            return QuizQuestion(
                id: "ex-\(fact.id)",
                prompt: "Which title matches this excerpt?",
                excerpt: clipped,
                imageURL: nil,
                options: options,
                correctIndex: correctIndex,
                factID: fact.id
            )
        }
    }

    // MARK: - Excerpt helpers

    private static func clipExcerpt(_ text: String, maxChars: Int = 220) -> String {
        let trimmed = TextUtils.normalizeWhitespace(text)
        guard trimmed.count > maxChars else { return trimmed }
        let clipped = String(trimmed.prefix(maxChars))
        if let stop = clipped.lastIndex(where: { ".!?".contains($0) }) {
            return String(clipped[...stop]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return clipped.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// Soft-redact the article name so the question isn’t a free giveaway.
    private static func redactTitleLeak(in text: String, title: String, also lookupTitle: String) -> String {
        var result = text
        var phrases: [String] = [title, lookupTitle]
        // Significant title words (skip tiny connectors).
        let stop = Set(["the", "a", "an", "of", "and", "or", "in", "on", "at", "to", "for"])
        for piece in [title, lookupTitle] {
            for word in piece.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                let w = String(word)
                guard w.count >= 4, !stop.contains(w.lowercased()) else { continue }
                phrases.append(w)
            }
        }
        phrases = Array(Set(phrases)).sorted { $0.count > $1.count }

        for phrase in phrases {
            guard phrase.count >= 3 else { continue }
            result = result.replacingOccurrences(
                of: phrase,
                with: "____",
                options: [.caseInsensitive]
            )
        }
        return TextUtils.normalizeWhitespace(result)
    }
}
