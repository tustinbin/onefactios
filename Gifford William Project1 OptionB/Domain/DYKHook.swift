import Foundation

struct DYKHook: Identifiable, Equatable {
    let id: String
    let hookText: String
    let articleTitle: String
}

enum DYKParser {
    /// Port of web `parseDykHooks` — DYK archive HTML → hooks.
    static func parseHooks(from html: String) -> [DYKHook] {
        var hooks: [DYKHook] = []
        let pattern = #"<li>\s*((?:\.\.\.|…)\s*that[\s\S]*?)</li>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))

        let boldLinkPattern = ##"<b>\s*(?:<[^>]+>\s*)*<a[^>]+href="/wiki/([^"#?]+)"[^>]*>"##
        let anyLinkPattern = ##"href="/wiki/([^"#?]+)""##
        let boldRegex = try? NSRegularExpression(pattern: boldLinkPattern, options: [.caseInsensitive])
        let anyRegex = try? NSRegularExpression(pattern: anyLinkPattern, options: [.caseInsensitive])

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let itemHTML = ns.substring(with: match.range(at: 1))
            let itemNS = itemHTML as NSString
            let itemRange = NSRange(location: 0, length: itemNS.length)

            var rawTitle: String?
            if let bold = boldRegex?.firstMatch(in: itemHTML, range: itemRange), bold.numberOfRanges > 1 {
                rawTitle = itemNS.substring(with: bold.range(at: 1))
            } else if let any = anyRegex?.firstMatch(in: itemHTML, range: itemRange), any.numberOfRanges > 1 {
                rawTitle = itemNS.substring(with: any.range(at: 1))
            }
            guard let rawTitle else { continue }

            let articleTitle = TextUtils.wikiTitleFromHref(rawTitle)
            if TextUtils.isSkippableWikiTitle(articleTitle) { continue }

            var hookText = TextUtils.stripHTML(itemHTML)
            hookText = TextUtils.decodeHTMLEntities(hookText)
            hookText = TextUtils.normalizeWhitespace(hookText)
            hookText = hookText.replacingOccurrences(of: #"^\.{3}\s*"#, with: "… ", options: .regularExpression)
            hookText = hookText.replacingOccurrences(of: #"(pictured)"#, with: "", options: [.regularExpression, .caseInsensitive])
            hookText = TextUtils.normalizeWhitespace(hookText)
                .replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
            guard hookText.count >= 24 else { continue }

            let id = "\(articleTitle)::\(hookText)".lowercased()
            hooks.append(DYKHook(id: id, hookText: hookText, articleTitle: articleTitle))
        }
        return hooks
    }
}
