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
        historyIndex: -1
    )
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
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
