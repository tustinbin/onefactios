import Foundation

struct WikipediaSummaryDTO: Decodable, Sendable {
    let title: String?
    let description: String?
    let extract: String?
    let thumbnail: ImageDTO?
    let originalimage: ImageDTO?
    let content_urls: ContentURLs?

    struct ImageDTO: Decodable, Sendable {
        let source: String?
    }

    struct ContentURLs: Decodable, Sendable {
        let desktop: PageURL?
        let mobile: PageURL?
        struct PageURL: Decodable, Sendable { let page: String? }
    }
}

struct WikipediaExtractQueryDTO: Decodable, Sendable {
    let query: Query?

    struct Query: Decodable, Sendable {
        let pages: [String: Page]?
    }

    struct Page: Decodable, Sendable {
        let title: String?
        let extract: String?
        let description: String?
    }
}

struct WikipediaParseDTO: Decodable, Sendable {
    let parse: Parse?

    struct Parse: Decodable, Sendable {
        let title: String?
        let text: TextBlob?

        struct TextBlob: Decodable, Sendable {
            let star: String?

            enum CodingKeys: String, CodingKey {
                case star = "*"
            }
        }
    }
}

struct WikipediaCategoriesDTO: Decodable, Sendable {
    let query: Query?

    struct Query: Decodable, Sendable {
        let pages: [String: Page]?
    }

    struct Page: Decodable, Sendable {
        let categories: [Category]?
    }

    struct Category: Decodable, Sendable {
        let title: String
    }
}

struct ArchiveTarget: Equatable, Sendable {
    let year: Int
    let monthName: String
    var key: String { "\(year)/\(monthName)" }
}

enum WikipediaServiceError: LocalizedError {
    case rateLimited
    case badResponse
    case decode

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "Wikipedia asked us to slow down. Try again in a moment."
        case .badResponse:
            return "Wikipedia didn’t return a fact."
        case .decode:
            return "Wikipedia returned data we couldn’t read."
        }
    }
}

actor WikipediaService {
    private let session: URLSession
    private var dykArchiveCache: [String: String] = [:]
    private var lastRequestAt: Date?

    private static let archiveStartYear = 2015
    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    /// Wikimedia asks for an identifiable UA with contact info. A generic string gets 429s.
    private static let userAgent =
        "OneFact/1.0 (https://github.com/tustinbin; student iOS project; mailto:tustinbin@users.noreply.github.com)"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSummary(title: String) async throws -> WikipediaSummaryDTO {
        let encoded = title
            .replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)")!
        return try await fetchJSON(url: url)
    }

    func fetchDykArchive(year: Int, monthName: String) async throws -> String {
        let key = "\(year)/\(monthName)"
        if let cached = dykArchiveCache[key] { return cached }

        let page = "Wikipedia:Did_you_know_archive/\(year)/\(monthName)"
        let data = try await fetchParse(page: page)
        guard let html = data.parse?.text?.star, !html.isEmpty else {
            throw WikipediaServiceError.decode
        }
        if dykArchiveCache.count > 24 {
            dykArchiveCache.removeValue(forKey: dykArchiveCache.keys.first!)
        }
        dykArchiveCache[key] = html
        return html
    }

    func fetchParsedPageHTML(title: String) async throws -> (html: String, title: String) {
        let data = try await fetchParse(page: title)
        guard let html = data.parse?.text?.star, !html.isEmpty else {
            throw WikipediaServiceError.decode
        }
        return (html, data.parse?.title ?? title)
    }

    func fetchCategoryTitles(forArticleTitle title: String) async throws -> [String] {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "prop", value: "categories"),
            .init(name: "titles", value: title),
            .init(name: "cllimit", value: "40"),
            .init(name: "clshow", value: "!hidden"),
            .init(name: "format", value: "json"),
            .init(name: "origin", value: "*"),
            .init(name: "redirects", value: "1")
        ]
        let dto: WikipediaCategoriesDTO = try await fetchJSON(url: components.url!)
        guard let pages = dto.query?.pages?.values else { return [] }
        return pages.flatMap { page in
            (page.categories ?? []).map(\.title)
        }
    }

    /// Longer plaintext lead + short description for the fact-card back.
    func fetchArticleDetail(title: String) async throws -> FactDetail {
        async let extractDTO = fetchPlainExtract(title: title)
        async let rawCategories = fetchCategoryTitles(forArticleTitle: title)
        async let summary = fetchSummaryIfAvailable(title: title)

        let extract = try await extractDTO
        let categoriesRaw = (try? await rawCategories) ?? []
        let summaryDTO = await summary

        let page = extract.query?.pages?.values.first
        // Keep paragraph breaks so the card back isn't one dense block.
        let longExtract = TextUtils.normalizeParagraphs(page?.extract ?? summaryDTO?.extract ?? "")
        let shortDescription = TextUtils.normalizeWhitespace(
            page?.description ?? summaryDTO?.description ?? ""
        )
        let categories = FactFactory.displayCategories(from: categoriesRaw)

        guard !longExtract.isEmpty || !shortDescription.isEmpty || !categories.isEmpty else {
            throw WikipediaServiceError.decode
        }

        return FactDetail(
            shortDescription: shortDescription,
            longExtract: longExtract,
            categories: categories
        )
    }

    private func fetchPlainExtract(title: String) async throws -> WikipediaExtractQueryDTO {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"),
            .init(name: "prop", value: "extracts|description"),
            .init(name: "titles", value: title),
            .init(name: "explaintext", value: "1"),
            .init(name: "exsectionformat", value: "plain"),
            .init(name: "exchars", value: "2200"),
            .init(name: "format", value: "json"),
            .init(name: "origin", value: "*"),
            .init(name: "redirects", value: "1")
        ]
        return try await fetchJSON(url: components.url!)
    }

    private func fetchSummaryIfAvailable(title: String) async -> WikipediaSummaryDTO? {
        try? await fetchSummary(title: title)
    }

    /// Pick a random DYK archive month, optionally avoiding the previous key.
    nonisolated func pickArchiveTarget(avoidKey: String? = nil) -> ArchiveTarget {
        let now = Date()
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: now)
        let currentMonthIndex = calendar.component(.month, from: now) - 1
        var options: [ArchiveTarget] = []

        for year in Self.archiveStartYear...currentYear {
            let lastMonth = year == currentYear ? currentMonthIndex : 11
            for monthIndex in 0...lastMonth {
                let target = ArchiveTarget(year: year, monthName: Self.monthNames[monthIndex])
                if target.key != avoidKey {
                    options.append(target)
                }
            }
        }
        return options.randomElement()
            ?? ArchiveTarget(year: currentYear, monthName: Self.monthNames[max(0, currentMonthIndex)])
    }

    private func fetchParse(page: String) async throws -> WikipediaParseDTO {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "parse"),
            .init(name: "page", value: page),
            .init(name: "prop", value: "text"),
            .init(name: "format", value: "json"),
            .init(name: "origin", value: "*"),
            .init(name: "redirects", value: "1")
        ]
        return try await fetchJSON(url: components.url!)
    }

    private func fetchJSON<T: Decodable>(url: URL) async throws -> T {
        var lastError: Error = WikipediaServiceError.badResponse

        for attempt in 0..<4 {
            try await throttleIfNeeded()

            var request = URLRequest(url: url)
            request.timeoutInterval = 25
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(Self.userAgent, forHTTPHeaderField: "Api-User-Agent")

            do {
                let (data, response) = try await session.data(for: request)
                lastRequestAt = Date()

                guard let http = response as? HTTPURLResponse else {
                    throw WikipediaServiceError.badResponse
                }

                if http.statusCode == 429 || http.statusCode == 503 {
                    lastError = WikipediaServiceError.rateLimited
                    let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 0
                    let delay = max(retryAfter, pow(1.6, Double(attempt)) * 0.7)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }

                guard (200..<300).contains(http.statusCode) else {
                    throw WikipediaServiceError.badResponse
                }

                // Wikimedia sometimes returns an HTML error page; don't try to decode it as JSON.
                if let prefix = String(data: data.prefix(32), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   prefix.lowercased().hasPrefix("<!DOCTYPE") || prefix.lowercased().hasPrefix("<html") {
                    lastError = WikipediaServiceError.rateLimited
                    try await Task.sleep(nanoseconds: UInt64((0.8 + Double(attempt)) * 1_000_000_000))
                    continue
                }

                do {
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    throw WikipediaServiceError.decode
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as WikipediaServiceError {
                lastError = error
                if error == .rateLimited {
                    try await Task.sleep(nanoseconds: UInt64((0.8 + Double(attempt)) * 1_000_000_000))
                    continue
                }
                throw error
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: UInt64((0.4 + Double(attempt) * 0.4) * 1_000_000_000))
            }
        }

        throw lastError
    }

    /// Keep a little breathing room between Wikimedia calls to avoid 429 storms.
    private func throttleIfNeeded() async throws {
        guard let last = lastRequestAt else { return }
        let gap = 0.35 - Date().timeIntervalSince(last)
        if gap > 0 {
            try await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000))
        }
    }
}

extension WikipediaServiceError: Equatable {}
