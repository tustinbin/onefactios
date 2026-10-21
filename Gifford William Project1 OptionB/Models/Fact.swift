import Foundation

struct Fact: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let title: String
    /// Wikipedia article title used for API lookups (may differ from display title for list facts).
    let lookupTitle: String
    let summary: String
    let highlight: String
    let imageURL: URL?
    let pageURL: URL?
    let matchedNicheIDs: [String]
    let source: FactSource
    var isComplete: Bool
    var savedAt: Date?

    enum FactSource: String, Codable {
        case random
        case search
        case dyk
        case list
    }

    var shareText: String {
        var parts = [title]
        if !shareBlurb.isEmpty { parts.append(shareBlurb) }
        if let pageURL { parts.append(pageURL.absoluteString) }
        return parts.joined(separator: "\n\n")
    }

    /// Short blurb for Messages / Mail (keeps the share sheet useful, not a wall of text).
    var shareBlurb: String {
        let raw = highlight.isEmpty ? summary : highlight
        let trimmed = TextUtils.normalizeWhitespace(raw)
        guard trimmed.count > 220 else { return trimmed }
        return String(trimmed.prefix(217)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var shareSubject: String {
        "One Fact: \(title)"
    }

    enum CodingKeys: String, CodingKey {
        case id, title, lookupTitle, summary, highlight, imageURL, pageURL
        case matchedNicheIDs, source, isComplete, savedAt
    }

    init(
        id: String,
        title: String,
        lookupTitle: String,
        summary: String,
        highlight: String,
        imageURL: URL?,
        pageURL: URL?,
        matchedNicheIDs: [String],
        source: FactSource,
        isComplete: Bool,
        savedAt: Date?
    ) {
        self.id = id
        self.title = title
        self.lookupTitle = lookupTitle
        self.summary = summary
        self.highlight = highlight
        self.imageURL = imageURL
        self.pageURL = pageURL
        self.matchedNicheIDs = matchedNicheIDs
        self.source = source
        self.isComplete = isComplete
        self.savedAt = savedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        lookupTitle = try c.decodeIfPresent(String.self, forKey: .lookupTitle) ?? title
        summary = try c.decode(String.self, forKey: .summary)
        highlight = try c.decode(String.self, forKey: .highlight)
        imageURL = try c.decodeIfPresent(URL.self, forKey: .imageURL)
        pageURL = try c.decodeIfPresent(URL.self, forKey: .pageURL)
        matchedNicheIDs = try c.decode([String].self, forKey: .matchedNicheIDs)
        source = try c.decode(FactSource.self, forKey: .source)
        isComplete = try c.decode(Bool.self, forKey: .isComplete)
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(lookupTitle, forKey: .lookupTitle)
        try c.encode(summary, forKey: .summary)
        try c.encode(highlight, forKey: .highlight)
        try c.encodeIfPresent(imageURL, forKey: .imageURL)
        try c.encodeIfPresent(pageURL, forKey: .pageURL)
        try c.encode(matchedNicheIDs, forKey: .matchedNicheIDs)
        try c.encode(source, forKey: .source)
        try c.encode(isComplete, forKey: .isComplete)
        try c.encodeIfPresent(savedAt, forKey: .savedAt)
    }
}

/// Extra Wikipedia content shown on the back of a fact card.
struct FactDetail: Equatable {
    let shortDescription: String
    let longExtract: String
    let categories: [String]
    /// Section shown on the back (e.g. "Early life", "History"), when known.
    var sectionTitle: String? = nil
}

enum FactMode: String, Codable, CaseIterable, Identifiable {
    case random
    case interests

    var id: String { rawValue }

    var label: String {
        switch self {
        case .random: "Random"
        case .interests: "Interests"
        }
    }
}
