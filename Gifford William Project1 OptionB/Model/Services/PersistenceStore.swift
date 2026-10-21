import Foundation

struct PersistedState: Codable, Equatable {
    var mode: FactMode
    var selectedIDs: [String]
    var additions: [Interest]
    var seenIDs: [String]
    var saved: [Fact]
    var heartedIDs: [String]
    var completedTopicIDs: [String]
    var completedFactIDs: [String]
    var factHistory: [Fact]
    var historyIndex: Int
    var dailyChallenge: DailyChallengeState?
    /// Lifetime count of finished Challenge quizzes.
    var challengesCompleted: Int
    /// Recent finished Challenge sessions (intro list).
    var challengeHistory: [ChallengeSessionRecord]

    static let empty = PersistedState(
        mode: .random,
        selectedIDs: [],
        additions: [],
        seenIDs: [],
        saved: [],
        heartedIDs: [],
        completedTopicIDs: [],
        completedFactIDs: [],
        factHistory: [],
        historyIndex: -1,
        dailyChallenge: nil,
        challengesCompleted: 0,
        challengeHistory: []
    )

    enum CodingKeys: String, CodingKey {
        case mode, selectedIDs, additions, seenIDs, saved, heartedIDs
        case completedTopicIDs, completedFactIDs, factHistory, historyIndex
        case dailyChallenge, challengesCompleted, challengeHistory
    }

    init(
        mode: FactMode,
        selectedIDs: [String],
        additions: [Interest],
        seenIDs: [String],
        saved: [Fact],
        heartedIDs: [String],
        completedTopicIDs: [String],
        completedFactIDs: [String],
        factHistory: [Fact],
        historyIndex: Int,
        dailyChallenge: DailyChallengeState?,
        challengesCompleted: Int,
        challengeHistory: [ChallengeSessionRecord]
    ) {
        self.mode = mode
        self.selectedIDs = selectedIDs
        self.additions = additions
        self.seenIDs = seenIDs
        self.saved = saved
        self.heartedIDs = heartedIDs
        self.completedTopicIDs = completedTopicIDs
        self.completedFactIDs = completedFactIDs
        self.factHistory = factHistory
        self.historyIndex = historyIndex
        self.dailyChallenge = dailyChallenge
        self.challengesCompleted = challengesCompleted
        self.challengeHistory = challengeHistory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decode(FactMode.self, forKey: .mode)
        selectedIDs = try c.decode([String].self, forKey: .selectedIDs)
        additions = try c.decode([Interest].self, forKey: .additions)
        seenIDs = try c.decode([String].self, forKey: .seenIDs)
        saved = try c.decode([Fact].self, forKey: .saved)
        heartedIDs = try c.decode([String].self, forKey: .heartedIDs)
        completedTopicIDs = try c.decodeIfPresent([String].self, forKey: .completedTopicIDs) ?? []
        completedFactIDs = try c.decodeIfPresent([String].self, forKey: .completedFactIDs) ?? []
        factHistory = try c.decodeIfPresent([Fact].self, forKey: .factHistory) ?? []
        historyIndex = try c.decodeIfPresent(Int.self, forKey: .historyIndex) ?? -1
        dailyChallenge = try c.decodeIfPresent(DailyChallengeState.self, forKey: .dailyChallenge)
        challengesCompleted = try c.decodeIfPresent(Int.self, forKey: .challengesCompleted) ?? 0
        challengeHistory = try c.decodeIfPresent([ChallengeSessionRecord].self, forKey: .challengeHistory) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(selectedIDs, forKey: .selectedIDs)
        try c.encode(additions, forKey: .additions)
        try c.encode(seenIDs, forKey: .seenIDs)
        try c.encode(saved, forKey: .saved)
        try c.encode(heartedIDs, forKey: .heartedIDs)
        try c.encode(completedTopicIDs, forKey: .completedTopicIDs)
        try c.encode(completedFactIDs, forKey: .completedFactIDs)
        try c.encode(factHistory, forKey: .factHistory)
        try c.encode(historyIndex, forKey: .historyIndex)
        try c.encodeIfPresent(dailyChallenge, forKey: .dailyChallenge)
        try c.encode(challengesCompleted, forKey: .challengesCompleted)
        try c.encode(challengeHistory, forKey: .challengeHistory)
    }
}

enum PersistenceStore {
    private static let key = "onefact-ios-state-v1"
    private static let seenLimit = 400
    private static let maxAdditions = 40

    static func load() -> PersistedState {
        guard let data = UserDefaults.standard.data(forKey: key) else { return .empty }
        return (try? JSONDecoder().decode(PersistedState.self, from: data)) ?? .empty
    }

    static func save(_ state: PersistedState) {
        var trimmed = state
        if trimmed.seenIDs.count > seenLimit {
            trimmed.seenIDs = Array(trimmed.seenIDs.suffix(seenLimit))
        }
        if trimmed.additions.count > maxAdditions {
            trimmed.additions = Array(trimmed.additions.prefix(maxAdditions))
        }
        if trimmed.factHistory.count > 80 {
            trimmed.factHistory = Array(trimmed.factHistory.suffix(80))
            trimmed.historyIndex = min(trimmed.historyIndex, trimmed.factHistory.count - 1)
        }
        if trimmed.challengeHistory.count > 20 {
            trimmed.challengeHistory = Array(trimmed.challengeHistory.prefix(20))
        }
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
