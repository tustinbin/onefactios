import Foundation

extension InterestCatalog {
    /// Extra preset niches beyond the original web interest tree.
    static let extraGroups: [InterestGroup] = [
        InterestGroup(
            id: "curiosities",
            label: "Curiosities & oddities",
            keywords: ["unusual", "odd", "curious", "strange", "rare"],
            children: [
                leaf("curio-unusual-deaths", "Unusual deaths",
                     ["unusual death", "bizarre death", "strange death", "accidental death"],
                     ["unusual deaths", "accidental deaths"], "curiosities", "Curiosities & oddities", "flame"),
                leaf("curio-misconceptions", "Common misconceptions",
                     ["misconception", "myth busted", "commonly believed", "false belief"],
                     ["misconceptions", "common misconceptions"], "curiosities", "Curiosities & oddities", "questionmark.circle"),
                leaf("curio-hoaxes-frauds", "Hoaxes & frauds",
                     ["hoax", "fraud", "forgery", "scam", "con artist"],
                     ["hoaxes", "frauds", "forgeries"], "curiosities", "Curiosities & oddities", "theatermasks"),
                leaf("curio-coincidences", "Coincidences & records",
                     ["coincidence", "world record", "first ever", "last of"],
                     ["world records", "firsts"], "curiosities", "Curiosities & oddities", "sparkles"),
                leaf("curio-lost-found", "Lost & found",
                     ["lost", "rediscovered", "missing", "found again", "reappeared"],
                     ["lost works", "rediscoveries"], "curiosities", "Curiosities & oddities", "magnifyingglass")
            ],
            overview: "Strange-but-true edges of history and culture.",
            purpose: "Pull Did You Know and list facts with a curiosity bent.",
            symbolName: "sparkles"
        ),
        InterestGroup(
            id: "maritime",
            label: "Ships & the sea",
            keywords: ["ship", "maritime", "naval", "ocean", "sailor"],
            children: [
                leaf("sea-shipwrecks", "Shipwrecks",
                     ["shipwreck", "sinking", "wreck", "foundered", "maritime disaster"],
                     ["shipwrecks", "maritime disasters"], "maritime", "Ships & the sea", "water.waves"),
                leaf("sea-exploration", "Sea exploration",
                     ["voyage", "circumnavigation", "expedition", "navigator", "age of sail"],
                     ["explorers", "maritime history"], "maritime", "Ships & the sea", "sailboat"),
                leaf("sea-piracy", "Piracy & privateers",
                     ["pirate", "privateer", "buccaneer", "corsair", "piracy"],
                     ["pirates", "piracy"], "maritime", "Ships & the sea", "flag"),
                leaf("sea-lighthouses", "Lighthouses & coasts",
                     ["lighthouse", "coast", "harbor", "beacon", "reef"],
                     ["lighthouses", "harbors"], "maritime", "Ships & the sea", "building.columns"),
                leaf("sea-naval-odd", "Naval oddities",
                     ["warship", "mutiny", "fleet", "naval battle", "submarine"],
                     ["naval history", "warships"], "maritime", "Ships & the sea", "ferry")
            ],
            overview: "Wrecks, voyages, and life on the water.",
            purpose: "Steer facts toward maritime stories.",
            symbolName: "ferry.fill"
        ),
        InterestGroup(
            id: "archaeology",
            label: "Archaeology & ruins",
            keywords: ["archaeology", "ruins", "artifact", "excavation", "ancient"],
            children: [
                leaf("arch-digs", "Famous digs",
                     ["excavation", "archaeologist", "unearthed", "dig site", "tomb"],
                     ["archaeological sites", "excavations"], "archaeology", "Archaeology & ruins", "hammer"),
                leaf("arch-lost-cities", "Lost cities",
                     ["lost city", "ruined city", "abandoned city", "buried city"],
                     ["lost cities", "ruined cities"], "archaeology", "Archaeology & ruins", "building.columns"),
                leaf("arch-artifacts", "Artifacts & treasures",
                     ["artifact", "relic", "treasure", "inscription", "tablet"],
                     ["archaeological artifacts", "treasures"], "archaeology", "Archaeology & ruins", "shippingbox"),
                leaf("arch-mummies", "Mummies & burials",
                     ["mummy", "burial", "sarcophagus", "cemetery", "grave goods"],
                     ["mummies", "burials"], "archaeology", "Archaeology & ruins", "flame"),
                leaf("arch-underwater", "Underwater finds",
                     ["underwater archaeology", "sunken", "marine archaeology", "wreck site"],
                     ["underwater archaeology", "shipwrecks"], "archaeology", "Archaeology & ruins", "water.waves")
            ],
            overview: "What people dig up — and what it changes.",
            purpose: "Match facts about digs, ruins, and artifacts.",
            symbolName: "hammer.fill"
        ),
        InterestGroup(
            id: "business",
            label: "Business & money",
            keywords: ["business", "company", "trade", "finance", "merchant"],
            children: [
                leaf("biz-companies", "Companies & brands",
                     ["company", "corporation", "brand", "startup", "founded"],
                     ["companies", "brands"], "business", "Business & money", "building.2"),
                leaf("biz-scandals", "Scandals & crashes",
                     ["scandal", "bankruptcy", "fraud", "market crash", "ponzi"],
                     ["financial scandals", "bankruptcies"], "business", "Business & money", "chart.line.downtrend.xyaxis"),
                leaf("biz-tycoons", "Tycoons & founders",
                     ["tycoon", "industrialist", "entrepreneur", "mogul", "founder"],
                     ["businesspeople", "entrepreneurs"], "business", "Business & money", "person.fill"),
                leaf("biz-trade", "Trade & markets",
                     ["trade route", "stock market", "commodity", "merchant", "exchange"],
                     ["trade", "markets"], "business", "Business & money", "cart"),
                leaf("biz-inventions-commerce", "Commercial firsts",
                     ["patent", "product launch", "advertising", "retail", "catalog"],
                     ["advertising", "retailing"], "business", "Business & money", "tag")
            ],
            overview: "How money, brands, and markets shape the world.",
            purpose: "Pull business and finance curiosities into Learn.",
            symbolName: "dollarsign.circle"
        ),
        InterestGroup(
            id: "weather",
            label: "Weather & extremes",
            keywords: ["weather", "storm", "climate", "hurricane", "blizzard"],
            children: [
                leaf("wx-storms", "Storms & hurricanes",
                     ["hurricane", "typhoon", "cyclone", "tornado", "storm surge"],
                     ["hurricanes", "tornadoes", "tropical cyclones"], "weather", "Weather & extremes", "cloud.bolt"),
                leaf("wx-cold", "Blizzards & cold",
                     ["blizzard", "ice storm", "freeze", "polar", "frost"],
                     ["blizzards", "winter storms"], "weather", "Weather & extremes", "snowflake"),
                leaf("wx-heat", "Heat & drought",
                     ["heat wave", "drought", "wildfire weather", "desert"],
                     ["heat waves", "droughts"], "weather", "Weather & extremes", "sun.max"),
                leaf("wx-floods", "Floods & rain",
                     ["flood", "deluge", "monsoon", "flash flood", "dam break"],
                     ["floods", "flash floods"], "weather", "Weather & extremes", "cloud.rain"),
                leaf("wx-climate-history", "Climate history",
                     ["little ice age", "climate", "paleoclimate", "greenhouse"],
                     ["climatology", "climate"], "weather", "Weather & extremes", "thermometer")
            ],
            overview: "Weather events that made history.",
            purpose: "Match storm, climate, and extreme-weather facts.",
            symbolName: "cloud.sun"
        ),
        InterestGroup(
            id: "games-culture",
            label: "Games & play",
            keywords: ["game", "toy", "puzzle", "chess", "videogame"],
            children: [
                leaf("games-board", "Board games",
                     ["board game", "chess", "checkers", "mahjong", "monopoly"],
                     ["board games", "chess"], "games-culture", "Games & play", "checkerboard"),
                leaf("games-cards", "Cards & chance",
                     ["playing cards", "poker", "bridge", "gambling", "dice"],
                     ["card games", "gambling"], "games-culture", "Games & play", "suit.spade.fill"),
                leaf("games-video", "Video games",
                     ["video game", "arcade", "console", "nintendo", "atari"],
                     ["video games", "arcade games"], "games-culture", "Games & play", "gamecontroller"),
                leaf("games-toys", "Toys & fads",
                     ["toy", "fad", "doll", "lego", "yo-yo"],
                     ["toys", "fads"], "games-culture", "Games & play", "gift"),
                leaf("games-puzzles", "Puzzles & riddles",
                     ["puzzle", "riddle", "crossword", "rubik", "enigma"],
                     ["puzzles", "riddles"], "games-culture", "Games & play", "puzzlepiece")
            ],
            overview: "How people play — boards, pixels, and puzzles.",
            purpose: "Steer Learn toward games and toys.",
            symbolName: "gamecontroller.fill"
        ),
        InterestGroup(
            id: "fashion",
            label: "Fashion & style",
            keywords: ["fashion", "clothing", "style", "designer", "textile"],
            children: [
                leaf("fashion-history", "Fashion history",
                     ["fashion history", "costume", "dress", "silhouette", "hemline"],
                     ["fashion history", "costume history"], "fashion", "Fashion & style", "tshirt"),
                leaf("fashion-designers", "Designers & houses",
                     ["fashion designer", "couture", "atelier", "runway", "fashion house"],
                     ["fashion designers", "haute couture"], "fashion", "Fashion & style", "scissors"),
                leaf("fashion-textiles", "Textiles & materials",
                     ["textile", "silk", "cotton", "wool", "dye"],
                     ["textiles", "fabrics"], "fashion", "Fashion & style", "square.grid.3x3"),
                leaf("fashion-accessories", "Accessories",
                     ["hat", "shoes", "jewelry", "handbag", "watch"],
                     ["hats", "shoes", "jewelry"], "fashion", "Fashion & style", "eyeglasses"),
                leaf("fashion-subcultures", "Style tribes",
                     ["punk fashion", "streetwear", "dandy", "flapper", "mod"],
                     ["subcultures", "street fashion"], "fashion", "Fashion & style", "person.3")
            ],
            overview: "Clothes, materials, and the people who shaped them.",
            purpose: "Match fashion and textile curiosities.",
            symbolName: "tshirt.fill"
        )
    ]

    private static func leaf(
        _ id: String,
        _ label: String,
        _ keywords: [String],
        _ categoryHints: [String],
        _ parentID: String,
        _ parentLabel: String,
        _ symbol: String
    ) -> Interest {
        Interest(
            id: id,
            label: label,
            keywords: keywords,
            categoryHints: categoryHints,
            parentID: parentID,
            parentLabel: parentLabel,
            overview: "Short Wikipedia-backed facts about \(label.lowercased()).",
            purpose: "Steer Learn toward \(label.lowercased()) when Interests mode is on.",
            symbolName: symbol,
            source: .default
        )
    }
}
