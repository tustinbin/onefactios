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

    enum ArticleBlock: Equatable, Hashable {
        case heading(String)
        case body(String)
    }

    /// Parse Wikipedia extract into headings + body, with readable body spacing.
    static func articleBlocks(from text: String, preferredMaxChars: Int = 260) -> [ArticleBlock] {
        let unified = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            // Turn wiki headings into plain marker lines we can spot.
            .replacingOccurrences(
                of: #"(?m)^[ \t]*=+\s*(.+?)\s*=+[ \t]*$"#,
                with: "§§$1",
                options: [.regularExpression]
            )

        var blocks: [ArticleBlock] = []
        var bodyBuffer: [String] = []

        func flushBody() {
            let joined = bodyBuffer.joined(separator: "\n\n")
            bodyBuffer = []
            for chunk in readableBodyChunks(from: joined, preferredMaxChars: preferredMaxChars) {
                blocks.append(.body(chunk))
            }
        }

        for rawLine in unified.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.hasPrefix("§§") {
                flushBody()
                let heading = String(line.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !heading.isEmpty {
                    blocks.append(.heading(heading))
                }
                continue
            }

            if looksLikeSectionHeading(line) {
                flushBody()
                blocks.append(.heading(line))
                continue
            }

            bodyBuffer.append(line)
        }
        flushBody()
        return blocks
    }

    /// Split walls of text into readable chunks (paragraphs, then sentences).
    static func readableChunks(from text: String, preferredMaxChars: Int = 260) -> [String] {
        readableBodyChunks(from: text, preferredMaxChars: preferredMaxChars)
    }

    struct WikiSectionRef: Equatable {
        let index: Int
        let line: String
        let level: Int
    }

    private static let skippedSectionTitles: Set<String> = [
        "see also", "references", "notes", "external links", "bibliography",
        "further reading", "citations", "sources", "footnotes", "gallery",
        "discography", "filmography", "awards", "honours", "honors"
    ]

    /// Prefer beginning-context sections (Early life, Background, …), else first real section.
    private static let preferredSectionTitles: [String] = [
        "early life", "early life and career", "early years", "childhood",
        "early life and education", "background", "biography", "history",
        "career", "education", "life and career"
    ]

    /// Choose which Wikipedia section to load in full for the card back.
    static func pickCloserLookSection(from sections: [WikiSectionRef]) -> WikiSectionRef? {
        let usable = sections.filter { section in
            guard section.level <= 2 else { return false }
            let lower = section.line.lowercased()
            if skippedSectionTitles.contains(lower) { return false }
            if skippedSectionTitles.contains(where: { lower.hasPrefix($0) }) { return false }
            return true
        }
        for preferred in preferredSectionTitles {
            if let match = usable.first(where: { $0.line.lowercased() == preferred }) {
                return match
            }
            if let match = usable.first(where: { $0.line.lowercased().hasPrefix(preferred) }) {
                return match
            }
        }
        return usable.first
    }

    /// One complete Wikipedia section for the card back (not an arbitrary mid-cut).
    static func closerLookBlocks(
        from extract: String,
        frontPieces: [String],
        preferredMaxChars: Int = 280
    ) -> [ArticleBlock] {
        let cleaned = cleanCloserLookText(extract)
        let stripped = stripFrontOverlap(from: cleaned, frontPieces: frontPieces)
        let all = articleBlocks(from: stripped, preferredMaxChars: preferredMaxChars)
            .filter { block in
                if case .body(let text) = block {
                    return !overlapsFrontContent(text, frontPieces: frontPieces)
                }
                return true
            }

        let sections = groupIntoSections(all)
        let usable = sections.filter { section in
            guard let title = section.title?.lowercased() else {
                return section.bodyTextCount > 80
            }
            return !skippedSectionTitles.contains(title)
                && !skippedSectionTitles.contains(where: { title.hasPrefix($0) })
                && section.bodyTextCount > 40
        }

        if let preferred = preferredSection(from: usable) {
            return preferred.blocks
        }
        if let first = usable.first(where: { $0.title != nil }) ?? usable.first {
            return first.blocks
        }

        // No sections — keep a sentence-bounded amount of leftover body.
        var fallback: [ArticleBlock] = []
        var chars = 0
        for block in all {
            guard case .body(let text) = block else { continue }
            fallback.append(block)
            chars += text.count
            if chars >= 900 { break }
        }
        return fallback
    }

    private struct ArticleSection {
        var title: String?
        var blocks: [ArticleBlock]
        var bodyTextCount: Int {
            blocks.reduce(0) { sum, block in
                if case .body(let text) = block { return sum + text.count }
                return sum
            }
        }
    }

    private static func groupIntoSections(_ blocks: [ArticleBlock]) -> [ArticleSection] {
        var sections: [ArticleSection] = []
        var current = ArticleSection(title: nil, blocks: [])

        for block in blocks {
            switch block {
            case .heading(let title):
                if !current.blocks.isEmpty || current.title != nil {
                    sections.append(current)
                }
                current = ArticleSection(title: title, blocks: [.heading(title)])
            case .body:
                current.blocks.append(block)
            }
        }
        if !current.blocks.isEmpty || current.title != nil {
            sections.append(current)
        }
        return sections
    }

    private static func preferredSection(from sections: [ArticleSection]) -> ArticleSection? {
        for preferred in preferredSectionTitles {
            if let match = sections.first(where: { $0.title?.lowercased() == preferred }) {
                return match
            }
            if let match = sections.first(where: {
                ($0.title?.lowercased() ?? "").hasPrefix(preferred)
            }) {
                return match
            }
        }
        return nil
    }

    private static func readableBodyChunks(from text: String, preferredMaxChars: Int) -> [String] {
        var chunks: [String] = []
        for paragraph in paragraphs(from: text) {
            if paragraph.count <= preferredMaxChars {
                chunks.append(paragraph)
                continue
            }
            let sentences = splitSentences(paragraph)
            var current = ""
            for sentence in sentences {
                let next = current.isEmpty ? sentence : "\(current) \(sentence)"
                if !current.isEmpty, next.count > preferredMaxChars {
                    chunks.append(current)
                    current = sentence
                } else {
                    current = next
                }
            }
            if !current.isEmpty {
                chunks.append(current)
            }
        }
        return chunks
    }

    /// Short title-ish lines that Wikipedia plain extracts often leave as section labels.
    private static func looksLikeSectionHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 48 else { return false }
        if trimmed.contains(".") || trimmed.contains("?") || trimmed.contains("!") { return false }
        if trimmed.contains(",") { return false }
        if trimmed.range(of: #"^\d+$"#, options: .regularExpression) != nil { return false }
        // Prefer lines that look like titles: start with a letter, not a long sentence.
        guard let first = trimmed.first, first.isLetter || first.isNumber else { return false }
        let words = trimmed.split(separator: " ")
        guard words.count <= 8 else { return false }
        // Common bio / article section names and Title Case heuristics.
        let lower = trimmed.lowercased()
        let known: Set<String> = [
            "profile", "early life", "early life and career", "career", "biography",
            "history", "background", "personal life", "later life", "death",
            "legacy", "education", "family", "military career", "political career",
            "overview", "description", "see also", "references", "notes"
        ]
        if known.contains(lower) { return true }
        if lower.hasPrefix("early life") || lower.hasPrefix("later life") { return true }
        let titled = words.filter { word in
            guard let c = word.first else { return false }
            return c.isUppercase || c.isNumber
        }.count
        return titled == words.count && words.count >= 1 && words.count <= 6
    }

    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            current.append(chars[i])
            let isEnd = chars[i] == "." || chars[i] == "!" || chars[i] == "?"
            let nextIsSpaceOrEnd = i + 1 >= chars.count || chars[i + 1].isWhitespace
            if isEnd, nextIsSpaceOrEnd {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
                while i + 1 < chars.count, chars[i + 1].isWhitespace {
                    i += 1
                }
            }
            i += 1
        }
        let leftover = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !leftover.isEmpty { sentences.append(leftover) }
        return sentences.isEmpty ? [text] : sentences
    }

    /// Drop anything already shown on the front of the card.
    /// If the extract has section headings, the whole lead is dropped — back starts at the first section.
    static func stripFrontOverlap(from longText: String, frontPieces: [String]) -> String {
        let unified = longText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let frontCorpus = normalizeWhitespace(frontPieces.joined(separator: " "))
        let frontLower = frontCorpus.lowercased()

        // Prefer exclusive back content: start at the first Wikipedia section.
        if let headingRange = unified.range(
            of: #"(?m)^[ \t]*=+\s*.+?\s*=+[ \t]*$"#,
            options: [.regularExpression]
        ) {
            return String(unified[headingRange.lowerBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // No sections — drop every paragraph that overlaps the front summary/highlight.
        let kept = paragraphs(from: unified).filter { paragraph in
            !overlapsFrontContent(paragraph, frontLower: frontLower)
        }
        return kept.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when a back paragraph is largely the same as front-card copy.
    static func overlapsFrontContent(_ paragraph: String, frontPieces: [String]) -> Bool {
        let frontLower = normalizeWhitespace(frontPieces.joined(separator: " ")).lowercased()
        return overlapsFrontContent(paragraph, frontLower: frontLower)
    }

    private static func overlapsFrontContent(_ paragraph: String, frontLower: String) -> Bool {
        let para = normalizeWhitespace(paragraph)
        guard para.count >= 24 else { return false }
        let paraLower = para.lowercased()
        guard !frontLower.isEmpty else { return false }

        if frontLower.contains(paraLower) || paraLower.contains(frontLower) {
            return true
        }
        // Shared prefix (REST summary vs longer extract lead).
        let prefixLen = min(paraLower.count, frontLower.count, 160)
        if prefixLen >= 48 {
            let a = paraLower.prefix(prefixLen)
            let b = frontLower.prefix(prefixLen)
            if a == b { return true }
        }

        let paraTokens = significantTokens(paraLower)
        let frontTokens = Set(significantTokens(frontLower))
        guard !paraTokens.isEmpty, !frontTokens.isEmpty else { return false }
        let shared = paraTokens.filter { frontTokens.contains($0) }.count
        return Double(shared) / Double(paraTokens.count) >= 0.62
    }

    private static func significantTokens(_ text: String) -> [String] {
        text
            .lowercased()
            .replacingOccurrences(of: #"[^\w\s]"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 }
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

    /// Turn a single section’s wikitext into clean reading copy (no CSS, no [1] citations).
    static func wikitextToPlain(_ wikitext: String) -> String {
        var text = wikitext
        // Drop refs entirely.
        text = text.replacingOccurrences(
            of: #"<ref[^>]*>[\s\S]*?</ref>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"<ref[^>]*/>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Drop templates {{...}} (repeat for light nesting).
        for _ in 0..<8 {
            let next = text.replacingOccurrences(
                of: #"\{\{[^{}]*\}\}"#,
                with: "",
                options: .regularExpression
            )
            if next == text { break }
            text = next
        }
        // [[Link|Label]] -> Label, [[Link]] -> Link
        text = text.replacingOccurrences(
            of: #"\[\[([^|\]]+)\|([^\]]+)\]\]"#,
            with: "$2",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\[\[([^\]]+)\]\]"#,
            with: "$1",
            options: .regularExpression
        )
        // External links [http://… label]
        text = text.replacingOccurrences(
            of: #"\[https?://[^\]\s]+ ([^\]]+)\]"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\[https?://[^\]\s]+\]"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"'{2,}"#, with: "", options: .regularExpression)
        text = stripHTML(text)
        text = decodeHTMLEntities(text)
        return cleanCloserLookText(text)
    }

    /// Strip citation markers, hatnotes, and leftover wiki noise from closer-look text.
    static func cleanCloserLookText(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: #"\[\s*\d+\s*\]"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[\s*(?:citation needed|clarification needed)[^\]]*\]"#, with: "", options: [.regularExpression, .caseInsensitive])
        // Drop common hatnote / maintenance lines.
        let lines = text.components(separatedBy: .newlines).filter { line in
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return true }
            let lower = t.lowercased()
            if lower.hasPrefix("main article:") { return false }
            if lower.hasPrefix("see also:") { return false }
            if lower.hasPrefix("further information:") { return false }
            if lower.hasPrefix("for other uses") { return false }
            if lower.hasPrefix(".mw-parser-output") { return false }
            if t.hasPrefix("{") || t.hasPrefix("|") { return false }
            return true
        }
        text = lines.joined(separator: "\n")
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return normalizeParagraphs(text)
    }
}
