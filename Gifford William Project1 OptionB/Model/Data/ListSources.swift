import Foundation

/// Curated Wikipedia list pages mapped to niche ids — port of web `list-sources.js`.
struct ListSource: Identifiable, Equatable {
    let id: String
    let title: String
    let nicheIDs: [String]
}

enum ListSources {
    static let all: [ListSource] = [
        .init(id: "list-individual-cats", title: "List of individual cats", nicheIDs: ["nature-animals"]),
        .init(id: "list-individual-dogs", title: "List of individual dogs", nicheIDs: ["nature-animals"]),

        // Park incidents — by operator (Park incidents category)
        .init(id: "list-disneyland-incidents", title: "List of incidents at Disneyland Resort", nicheIDs: ["incidents-disney"]),
        .init(id: "list-wdw-incidents", title: "List of incidents at Walt Disney World", nicheIDs: ["incidents-disney"]),
        .init(id: "list-dlp-incidents", title: "List of incidents at Disneyland Paris", nicheIDs: ["incidents-disney"]),
        .init(id: "list-tdr-incidents", title: "List of incidents at Tokyo Disney Resort", nicheIDs: ["incidents-disney"]),
        .init(id: "list-hkdl-incidents", title: "List of incidents at Hong Kong Disneyland Resort", nicheIDs: ["incidents-disney"]),
        .init(id: "list-shdr-incidents", title: "List of incidents at Shanghai Disney Resort", nicheIDs: ["incidents-disney"]),

        .init(id: "list-universal-incidents", title: "Incidents at Universal parks", nicheIDs: ["incidents-universal"]),
        .init(id: "list-sixflags-incidents", title: "Incidents at Six Flags parks", nicheIDs: ["incidents-sixflags"]),
        .init(id: "list-cedarfair-incidents", title: "Incidents at Cedar Fair parks", nicheIDs: ["incidents-cedarfair"]),
        .init(id: "list-seaworld-incidents", title: "Incidents at SeaWorld parks", nicheIDs: ["incidents-seaworld"]),
        .init(id: "list-european-park-incidents", title: "Incidents at European amusement parks", nicheIDs: ["incidents-european"]),
        .init(id: "list-independent-park-incidents", title: "List of incidents at independent amusement parks", nicheIDs: ["incidents-independent"]),

        .init(id: "list-herschend-incidents", title: "List of incidents at Herschend parks", nicheIDs: ["incidents-other-chains"]),
        .init(id: "list-legoland-incidents", title: "Incidents at LEGOLAND parks", nicheIDs: ["incidents-other-chains"]),
        .init(id: "list-warner-incidents", title: "List of incidents at Warner Bros. parks", nicheIDs: ["incidents-other-chains"]),

        .init(id: "list-inventors-killed", title: "List of inventors killed by their own invention", nicheIDs: ["invention-gadgets", "invention-engineering", "curio-unusual-deaths"]),
        // Crime & intrigue — keep lists on-theme (not broad “unusual deaths”, which pulls random tangents).
        .init(id: "list-hoaxes", title: "List of hoaxes", nicheIDs: ["odd-crime", "odd-customs", "curio-hoaxes-frauds"]),
        .init(id: "list-spies", title: "List of spies", nicheIDs: ["odd-crime"]),
        .init(id: "list-cryptonyms", title: "List of espionage operations", nicheIDs: ["odd-crime"]),

        // Curiosities / oddities
        .init(id: "list-unusual-deaths", title: "List of unusual deaths", nicheIDs: ["curio-unusual-deaths", "odd-customs"]),
        .init(id: "list-unusual-deaths-21c", title: "List of unusual deaths in the 21st century", nicheIDs: ["curio-unusual-deaths"]),
        .init(id: "list-unusual-animal-deaths", title: "List of unusual animal deaths", nicheIDs: ["curio-unusual-deaths", "nature-animals"]),
        .init(id: "list-common-misconceptions", title: "List of common misconceptions", nicheIDs: ["curio-misconceptions", "people-language", "odd-customs"]),

        // Nature extras
        .init(id: "list-individual-horses", title: "List of individual horses", nicheIDs: ["nature-animals"]),
        .init(id: "list-individual-elephants", title: "List of individual elephants", nicheIDs: ["nature-animals"]),
        .init(id: "list-individual-apes", title: "List of individual apes", nicheIDs: ["nature-animals"]),

        // Maritime / disasters
        .init(id: "list-shipwrecks", title: "List of shipwrecks", nicheIDs: ["sea-shipwrecks", "disasters-maritime", "sea-exploration"]),
        .init(id: "list-maritime-disasters", title: "List of maritime disasters", nicheIDs: ["sea-shipwrecks", "disasters-maritime", "disasters-transport"])
    ]

    static func forNicheIDs(_ nicheIDs: [String]) -> [ListSource] {
        let set = Set(nicheIDs)
        if set.isEmpty { return all }
        return all.filter { source in source.nicheIDs.contains { set.contains($0) } }
    }

    /// Niche ids that have curated Wikipedia list pages.
    static let listBackedNicheIDs: Set<String> = Set(all.flatMap(\.nicheIDs))

    static func isListBacked(_ nicheID: String) -> Bool {
        listBackedNicheIDs.contains(nicheID)
    }

    /// True when every selected niche is list-backed (e.g. only “Disney incidents”).
    static func areAllListBacked(_ interests: [Interest]) -> Bool {
        !interests.isEmpty && interests.allSatisfy { isListBacked($0.id) }
    }

    /// Generic list-blurb noise — not useful as article search terms.
    private static let genericListKeywords: Set<String> = [
        "ride accident", "park accident", "amusement park accident",
        "roller coaster accident", "marine park"
    ]

    /// Remap a list niche into a custom-style keyword interest (e.g. Disney incidents → search “disney”).
    /// Matching label is the primary brand token so we don’t require “incidents” in every article.
    /// UI still shows the catalog label via `InterestCatalog.leaf(id:)`.
    static func keywordSearchInterest(from interest: Interest) -> Interest {
        guard isListBacked(interest.id) else { return interest }
        let brandKeywords = interest.keywords.filter {
            !genericListKeywords.contains($0.lowercased())
        }
        let keywords = brandKeywords.isEmpty ? interest.keywords : brandKeywords
        let brandHints = interest.categoryHints.filter {
            !$0.localizedCaseInsensitiveContains("accident")
        }
        // Single brand token as the custom label so we don’t require “incidents” (or
        // every word of “disney world”) — keywords still include the full brand set.
        let matchLabel = keywords
            .filter { !$0.contains(" ") }
            .max(by: { $0.count < $1.count })
            ?? keywords.first
            ?? interest.label
        return Interest(
            id: interest.id,
            label: matchLabel,
            keywords: keywords,
            categoryHints: brandHints.isEmpty ? keywords : brandHints,
            parentID: interest.parentID,
            parentLabel: interest.parentLabel,
            overview: interest.overview,
            purpose: interest.purpose,
            symbolName: interest.symbolName,
            source: .custom
        )
    }

    static func keywordSearchInterests(from interests: [Interest]) -> [Interest] {
        interests.map(keywordSearchInterest(from:))
    }

    static let interestingListTitlePattern =
        #"\b(incidents?|accidents?|unusual|notable|famous|individual|hoaxes?|deaths?|misconceptions?|shipwrecks?|disasters?|inventors?)\b"#
    static let boringListTitlePattern =
        #"\b(discograph|episode|filmograph|roster|stations?|species of|bibliography|awards?\b.*\bleaders?|scoring leaders|death toll)\b"#

    static func isInterestingListTitle(_ title: String) -> Bool {
        if title.range(of: boringListTitlePattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return false
        }
        if title.range(of: #"\bincidents?\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if title.range(of: #"^list of "#, options: [.regularExpression, .caseInsensitive]) == nil {
            return false
        }
        return title.range(of: interestingListTitlePattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
