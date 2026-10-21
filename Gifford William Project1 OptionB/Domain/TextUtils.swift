import Foundation

enum TextUtils {
    static func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Keep paragraph breaks; collapse runs of spaces inside each paragraph.
    static func normalizeParagraphs(_ text: String) -> String {
        let unified = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let paragraphs = unified
            .components(separatedBy: "\n")
            .map { normalizeWhitespace($0) }
            .filter { !$0.isEmpty }
        return paragraphs.joined(separator: "\n\n")
    }

    static func paragraphs(from text: String) -> [String] {
        normalizeParagraphs(text)
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Drop front-of-card copy so the back doesn't repeat the same opening.
    static func stripFrontOverlap(from longText: String, frontPieces: [String]) -> String {
        var remaining = normalizeParagraphs(longText)
        let pieces = frontPieces
            .map { normalizeWhitespace($0) }
            .filter { $0.count >= 40 }

        for piece in pieces {
            let remainingNorm = normalizeWhitespace(remaining)
            let pieceNorm = piece
            if remainingNorm.localizedCaseInsensitiveCompare(pieceNorm) == .orderedSame {
                return ""
            }
            if remainingNorm.lowercased().hasPrefix(pieceNorm.lowercased()) {
                let idx = remainingNorm.index(remainingNorm.startIndex, offsetBy: pieceNorm.count)
                remaining = normalizeParagraphs(String(remainingNorm[idx...]))
                continue
            }
            // Drop a leading paragraph that substantially overlaps the front summary.
            var paras = paragraphs(from: remaining)
            if let first = paras.first {
                let firstNorm = normalizeWhitespace(first).lowercased()
                let pieceLower = pieceNorm.lowercased()
                let overlap = Double(min(firstNorm.count, pieceLower.count))
                let sharedPrefix = zip(firstNorm, pieceLower).prefix { $0 == $1 }.count
                if overlap > 0, Double(sharedPrefix) / overlap >= 0.82 {
                    paras.removeFirst()
                    remaining = paras.joined(separator: "\n\n")
                }
            }
        }
        return remaining.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let named: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&quot;", "\""),
            ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">")
        ]
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        // Decimal numeric entities
        while let match = result.range(of: #"&#(\d+);"#, options: .regularExpression) {
            let token = String(result[match])
            if let num = Int(token.dropFirst(2).dropLast()) ,
               let scalar = UnicodeScalar(num) {
                result.replaceSubrange(match, with: String(Character(scalar)))
            } else {
                break
            }
        }
        // Hex numeric entities
        while let match = result.range(of: #"&#x([0-9a-fA-F]+);"#, options: .regularExpression) {
            let token = String(result[match])
            let hex = String(token.dropFirst(3).dropLast())
            if let num = Int(hex, radix: 16), let scalar = UnicodeScalar(num) {
                result.replaceSubrange(match, with: String(Character(scalar)))
            } else {
                break
            }
        }
        return result
    }

    static func shuffle<T>(_ list: [T]) -> [T] {
        var copy = list
        guard copy.count > 1 else { return copy }
        for i in stride(from: copy.count - 1, through: 1, by: -1) {
            let j = Int.random(in: 0...i)
            copy.swapAt(i, j)
        }
        return copy
    }

    static func pickRandom<T>(_ list: [T]) -> T? {
        guard !list.isEmpty else { return nil }
        return list[Int.random(in: 0..<list.count)]
    }

    static func slugify(_ label: String, prefix: String = "", max: Int = 48) -> String {
        let body = label
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let clipped = String(body.prefix(max))
        return prefix.isEmpty ? clipped : prefix + clipped
    }

    static func wikiTitleFromHref(_ hrefTitle: String) -> String {
        let decoded = hrefTitle.removingPercentEncoding ?? hrefTitle
        return decoded.replacingOccurrences(of: "_", with: " ")
    }

    static func isSkippableWikiTitle(_ title: String) -> Bool {
        title.range(
            of: #"^(File|Image|Wikipedia|Talk|Template|Category|Help|Portal|Special|User|Draft):"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }
}
