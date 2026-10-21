import Foundation

struct ListEntry: Identifiable, Equatable {
    let id: String
    let articleTitle: String
    let blurb: String
    let highlight: String
    let listTitle: String
    let score: Int
}

/// Port of web `domain/list-pages.js`.
enum ListPageParser {
    private static let minEntryChars = 70
    private static let maxEntryChars = 420

    static func parseListEntries(html: String, listTitle: String) -> [ListEntry] {
        let interesting = ListSources.isInterestingListTitle(listTitle)
            || listTitle.range(of: #"\bincidents?\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        guard interesting else { return [] }

        var entries: [ListEntry] = []
        var seen = Set<String>()
        let itemPattern = #"<li>([\s\S]*?)</li>"#
        guard let regex = try? NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let itemHTML = ns.substring(with: match.range(at: 1))
            if itemHTML.range(of: "mw-empty-elt", options: .caseInsensitive) != nil { continue }
            if itemHTML.range(of: #"<(ul|ol|table)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            if itemHTML.range(of: #"ISBN|mw-parser-output\s+cite|citation"#, options: [.regularExpression, .caseInsensitive]) != nil {
                continue
            }

            var blurb = plainTextFromHTML(itemHTML)
            if blurb.count < minEntryChars { continue }
            if blurb.range(of: #"^list of "#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            if blurb.range(of: #"^acts of god\b"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            if blurb.count < 90, blurb.range(of: #"[.!?]"#, options: .regularExpression) == nil { continue }

            guard let articleTitle = pickArticleTitle(itemHTML: itemHTML, blurb: blurb) else { continue }

            if blurb.count > maxEntryChars {
                let clipped = String(blurb.prefix(maxEntryChars))
                let stops = [". ", "? ", "! "]
                let lastStop = stops.compactMap { delim -> String.Index? in
                    clipped.range(of: delim, options: .backwards)?.lowerBound
                }.max()
                if let lastStop, clipped.distance(from: clipped.startIndex, to: lastStop) > 80 {
                    blurb = String(clipped[...lastStop]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    blurb = clipped.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
                }
            }

            let score = scoreEntry(blurb, articleTitle: articleTitle)
            guard score >= 2 else { continue }

            let id = "list::\(listTitle)::\(articleTitle)::\(blurb.prefix(48))".lowercased()
            if seen.contains(id) { continue }
            seen.insert(id)

            entries.append(
                ListEntry(
                    id: id,
                    articleTitle: articleTitle,
                    blurb: blurb,
                    highlight: firstSentence(blurb),
                    listTitle: listTitle,
                    score: score
                )
            )
        }
        return entries
    }

    static func scoreListPage(listTitle: String, entryCount: Int) -> Int {
        scoreListTitle(listTitle) * 10 + min(40, entryCount)
    }

    private static func scoreListTitle(_ title: String) -> Int {
        if title.range(of: ListSources.boringListTitlePattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return 0
        }
        var score = 1
        if title.range(of: ListSources.interestingListTitlePattern, options: [.regularExpression, .caseInsensitive]) != nil {
            score += 2
        }
        if title.range(of: #"\bincidents?\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            score += 2
        }
        if title.range(of: #"^list of individual "#, options: [.regularExpression, .caseInsensitive]) != nil {
            score += 2
        }
        if title.range(of: #"unusual|hoax|misconception"#, options: [.regularExpression, .caseInsensitive]) != nil {
            score += 1
        }
        return score
    }

    private static func scoreEntry(_ text: String, articleTitle: String) -> Int {
        var score = 0
        if text.count >= minEntryChars { score += 1 }
        if text.count >= 110 { score += 1 }
        if text.range(of: #"[.!?]"#, options: .regularExpression) != nil { score += 1 }
        let shortName = articleTitle.lowercased().split(separator: "(").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        if !shortName.isEmpty, text.lowercased().contains(shortName) { score += 1 }
        if text.range(
            of: #"\b(was|were|became|helped|killed|died|discovered|known for|worked|arrested|rescued)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            score += 1
        }
        return score
    }

    private static func plainTextFromHTML(_ html: String) -> String {
        var text = TextUtils.stripHTML(html)
        text = TextUtils.decodeHTMLEntities(text)
        return TextUtils.normalizeWhitespace(text)
            .replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
    }

    private static func firstSentence(_ text: String) -> String {
        let clean = TextUtils.normalizeWhitespace(text)
        if let match = clean.range(of: #"^.+?[.!?]"#, options: .regularExpression) {
            let sentence = String(clean[match])
            if sentence.count >= 40 { return sentence }
        }
        if clean.count <= 220 { return clean }
        return String(clean.prefix(217)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private static func pickArticleTitle(itemHTML: String, blurb: String) -> String? {
        let blurbLower = blurb.lowercased()
        let candidates = linkCandidates(itemHTML)
        let ranked: [(title: String, score: Int)] = candidates.compactMap { item in
            let title = TextUtils.wikiTitleFromHref(item.href)
            if TextUtils.isSkippableWikiTitle(title) { return nil }
            if title.range(of: #"^List of "#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }

            var score = item.priority
            let label = (item.text.isEmpty ? title : item.text).lowercased()
            if !label.isEmpty {
                let prefix = String(label.prefix(min(12, label.count)))
                if blurbLower.hasPrefix(prefix) {
                    score += 4
                } else if label.count >= 4, blurbLower.contains(label) {
                    score += 1
                }
            }
            if title.range(of: #"language|script|alphabet|romanization"#, options: [.regularExpression, .caseInsensitive]) != nil {
                score -= 3
            }
            // Penalize short one-word side topics that aren't the blurb's lead subject
            // (classic failure: "Autopsy" winning over the ride/incident).
            let wordCount = title.split(whereSeparator: \.isWhitespace).count
            if wordCount == 1, title.count <= 14 {
                let lead = String(blurbLower.prefix(96))
                if !lead.contains(title.lowercased()) {
                    score -= 6
                }
            }
            return (title, score)
        }
        .sorted { $0.score > $1.score }

        return ranked.first?.title
    }

    private struct LinkCandidate {
        let href: String
        let text: String
        let priority: Int
    }

    private static func linkCandidates(_ itemHTML: String) -> [LinkCandidate] {
        var candidates: [LinkCandidate] = []
        let ns = itemHTML as NSString
        let full = NSRange(location: 0, length: ns.length)

        let boldPattern = ##"<b>\s*(?:<[^>]+>\s*)*<a[^>]+href="/wiki/([^"#?]+)"[^>]*>([\s\S]*?)</a>"##
        if let boldRegex = try? NSRegularExpression(pattern: boldPattern, options: [.caseInsensitive]),
           let bold = boldRegex.firstMatch(in: itemHTML, range: full),
           bold.numberOfRanges > 2 {
            candidates.append(
                LinkCandidate(
                    href: ns.substring(with: bold.range(at: 1)),
                    text: plainTextFromHTML(ns.substring(with: bold.range(at: 2))),
                    priority: 3
                )
            )
        }

        let linkPattern = ##"<a[^>]+href="/wiki/([^"#?]+)"[^>]*>([\s\S]*?)</a>"##
        if let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive]) {
            for match in linkRegex.matches(in: itemHTML, range: full) where match.numberOfRanges > 2 {
                candidates.append(
                    LinkCandidate(
                        href: ns.substring(with: match.range(at: 1)),
                        text: plainTextFromHTML(ns.substring(with: match.range(at: 2))),
                        priority: 1
                    )
                )
            }
        }
        return candidates
    }
}
