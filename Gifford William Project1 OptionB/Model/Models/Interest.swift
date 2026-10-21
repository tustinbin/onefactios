import Foundation

struct Interest: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let label: String
    let keywords: [String]
    let categoryHints: [String]
    let parentID: String?
    let parentLabel: String?
    let overview: String
    let purpose: String
    let symbolName: String
    let source: InterestSource

    enum InterestSource: String, Codable {
        case `default`
        case addition
        /// Typed by the user on the Interests screen.
        case custom
    }
}

struct InterestGroup: Identifiable, Equatable {
    let id: String
    let label: String
    let keywords: [String]
    let children: [Interest]
    let overview: String
    let purpose: String
    let symbolName: String
}
