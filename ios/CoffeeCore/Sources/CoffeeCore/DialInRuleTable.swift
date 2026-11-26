import Foundation

/// The rules, tried in this order; the first that matches with a move still
/// open wins. Defects come before missing qualities, and the rules for
/// missing qualities need a clean cup, so a defect whose changes are all
/// ruled out gives no suggestion rather than a push in the wrong direction.
/// Drawdown only sharpens what the taste says; it never acts alone. Ids
/// follow the rule set this came from, with D (drying, 101–102) and G
/// (generic fruit, 111–113) added.
extension DialInRule {
    static let all: [DialInRule] = flowAndConflicts + defects + concentration + missing + isolated
}

extension DialInRule {
    /// Drawdown with a problem, and defects that pull different ways.
    static let flowAndConflicts: [DialInRule] = [
        DialInRule(
            1, .medium, .lessAgitation, else: .coarser, effect: "Cleaner and smoother, draining faster",
            why: "A slow bed with off flavours points to fines and uneven extraction."
        ) { $0.slow && ($0.has(.muddy) || $0.has(.bitter) || $0.has(.sharp)) },
        DialInRule(
            2, .medium, .coarser, else: .lessAgitation, effect: "Clearer, sweeter and more expressive",
            why: "Letting water through more freely may help more than a longer contact time."
        ) { $0.slow && ($0.low(.clarity) || $0.low(.sweetness) || $0.low(.finish)) },
        DialInRule(
            3, .medium, .lessAgitation, else: .coarser, effect: "Lighter and less harsh",
            why: "Heavy and sharp together argue against simply extracting more."
        ) { $0.has(.sharp) && ($0.has(.heavy) || $0.high(.body)) },
        DialInRule(
            4, .medium, .lessAgitation, else: .coarser, effect: "More distinct, recognisable flavour",
            why: "Muddy and weak can come with plenty of extraction: blurred, not missing."
        ) { $0.has(.muddy) && $0.low(.intensity) },
        DialInRule(
            5, .medium, .cooler, else: .coarser, effect: "Less bitter, with more apparent sweetness",
            why: "Bitterness can hide sweetness that's already there."
        ) { $0.has(.bitter) && $0.low(.sweetness) },
        DialInRule(
            6, .medium, .lessAgitation, else: .coarser, effect: "Smoother and cleaner",
            why: "Sharp and bitter together suggest uneven extraction, not too little."
        ) { $0.has(.sharp) && $0.has(.bitter) },
        DialInRule(
            101, .medium, .lessAgitation, else: .coarser, effect: "Less drying, and cleaner",
            why: "A slow bed and a drying feel point to fines and uneven extraction."
        ) { $0.has(.drying) && $0.slow },
        DialInRule(
            102, .medium, .coarser, else: .lessAgitation, effect: "A smoother finish",
            why: "Astringency usually means extracting too hard: ease off before anything that extracts more."
        ) { $0.has(.drying) },
        DialInRule(
            7, .medium, .finer, else: .moreAgitation, effect: "Fuller and more intense",
            why: "A fast drawdown and weak flavour support extracting more."
        ) { $0.fast && $0.low(.intensity) && $0.clean },
        DialInRule(
            8, .medium, .finer, else: .hotter, effect: "Sweeter, and less sour",
            why: "Fast flow with sourness and little sweetness suggests too little extraction."
        ) { cup in
            cup.fast && cup.low(.sweetness) && cup.has(.sharp)
                && !cup.has(.bitter) && !cup.has(.muddy) && !cup.has(.heavy) && !cup.has(.drying)
        },
    ]

    /// Something tasted wrong.
    static let defects: [DialInRule] = [
        DialInRule(
            9, .medium, .cooler, else: .coarser, effect: "Less bitter, and smoother",
            why: "Gentler extraction is a reasonable first test for bitterness."
        ) { $0.has(.bitter) },
        DialInRule(
            10, .medium, .lessAgitation, else: .coarser, effect: "Clearer and more distinct",
            why: "Less turbulence, or a freer-flowing bed, can separate the flavours."
        ) { $0.has(.muddy) },
        DialInRule(
            11, .medium, .finer, else: .hotter, effect: "Sweeter, and less sour",
            why: "Sourness with little sweetness often means too little extraction."
        ) { $0.has(.sharp) && $0.low(.sweetness) && !$0.high(.body) },
        DialInRule(
            12, .medium, .cooler, else: .longerRatio, effect: "Softer, and less sharp",
            why: "Gentler extraction or less concentration may take the edge off strong acidity."
        ) { $0.has(.sharp) && $0.high(.acidity) },
        DialInRule(
            13, .low, .cooler, else: .longerRatio, effect: "Smoother acidity",
            why: "Exploratory: sharpness alone could also mean too little extraction (finer, hotter) if this doesn't help."
        ) { $0.has(.sharp) },
        DialInRule(
            14, .medium, .lessAgitation, else: .longerRatio, effect: "Lighter and cleaner",
            why: "Fewer fines stirred up, or less concentration, can reduce the weight."
        ) { $0.has(.heavy) },
        DialInRule(
            111, .low, .cooler, else: .lessAgitation, effect: "More distinct fruit",
            why: "Grind hasn't helped, so try a gentler extraction to see if the fruit sharpens up."
        ) { $0.has(.genericFruit) && $0.grindTried },
        DialInRule(
            112, .low, .lessAgitation, else: .cooler, effect: "More distinct fruit",
            why: "There's enough flavour; it isn't separating, which calmer extraction may help."
        ) { $0.has(.genericFruit) && $0.notLow(.intensity) },
        DialInRule(
            113, .low, .cooler, else: .lessAgitation, effect: "Less generic fruit",
            why: "Exploratory: gentler extraction to test whether the fruit gets more specific."
        ) { $0.has(.genericFruit) },
    ]
}
