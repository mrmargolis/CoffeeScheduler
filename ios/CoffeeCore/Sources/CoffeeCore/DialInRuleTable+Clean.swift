import Foundation

/// Rules for a clean cup (no character tags): too much or too little of
/// something, but nothing tasted wrong.
extension DialInRule {
    /// Strength and texture: concentration problems, fixed with water.
    static let concentration: [DialInRule] = [
        DialInRule(
            15, .high, .shorterRatio, else: .finer, effect: "More punch, the same character",
            why: "Less water makes a stronger cup without changing how it's extracted."
        ) { $0.clean && $0.low(.intensity) && $0.othersOnTarget(.intensity) },
        DialInRule(
            16, .high, .longerRatio, else: .coarser, effect: "Less overwhelming, and more approachable",
            why: "More water makes a weaker cup without changing how it's extracted."
        ) { $0.clean && $0.high(.intensity) && $0.othersOnTarget(.intensity) },
        DialInRule(
            17, .high, .shorterRatio, else: .finer, effect: "Fuller and more saturated",
            why: "Weak and thin with sweetness and acidity in place is a concentration problem."
        ) { $0.clean && $0.low(.intensity) && $0.low(.body) && $0.notLow(.sweetness) && $0.notLow(.acidity) },
        DialInRule(
            18, .high, .longerRatio, else: .coarser, effect: "Lighter, and less intense",
            why: "Too strong and too heavy both call for less concentration."
        ) { $0.clean && $0.high(.intensity) && $0.high(.body) },
        DialInRule(
            19, .medium, .lessAgitation, else: .coarser, effect: "Lighter and clearer",
            why: "Heavy and unclear may be fines or uneven extraction."
        ) { $0.clean && $0.high(.body) && $0.low(.clarity) },
        DialInRule(
            20, .medium, .longerRatio, else: .coarser, effect: "A lighter body",
            why: "More water lightens the body without targeting the flavour."
        ) { $0.clean && $0.high(.body) && $0.othersOnTarget(.body) },
        DialInRule(
            21, .medium, .shorterRatio, else: .finer, effect: "A fuller body",
            why: "Less water can make the texture fuller."
        ) { $0.clean && $0.low(.body) && $0.othersOnTarget(.body) },
    ]

    /// Missing what's wanted: sweetness, acidity, clarity.
    static let missing: [DialInRule] = [
        DialInRule(
            22, .low, .cooler, else: .lessAgitation, effect: "More expressive fruit, and more apparent sweetness",
            why: "Grind hasn't helped, so try a different extraction rather than more of the same."
        ) { $0.clean && $0.grindTried && $0.low(.sweetness) && ($0.low(.acidity) || $0.unknown(.acidity)) },
        DialInRule(
            23, .medium, .finer, else: .hotter, effect: "More developed flavour, sweetness and intensity",
            why: "Several subdued attributes support extracting more."
        ) { $0.clean && $0.low(.intensity) && $0.low(.sweetness) && $0.low(.acidity) },
        DialInRule(
            24, .medium, .finer, else: .hotter, effect: "Fuller, sweeter flavour",
            why: "Weak and not sweet together suggest too little extraction."
        ) { $0.clean && $0.low(.intensity) && $0.low(.sweetness) },
        DialInRule(
            25, .medium, .lessAgitation, else: .cooler, effect: "Clearer fruit, and more apparent sweetness",
            why: "Poor definition suggests extracting more won't fix it."
        ) { $0.clean && $0.low(.sweetness) && $0.low(.clarity) },
        DialInRule(
            26, .medium, .finer, else: .hotter, effect: "More developed fruit and sweetness",
            why: "Both missing, with no sign of extracting too much."
        ) { $0.clean && $0.low(.acidity) && $0.low(.sweetness) },
        DialInRule(
            27, .low, .coarser, else: .cooler, effect: "Brighter, more distinct acidity",
            why: "Exploratory: a sweet but subdued cup may brighten with gentler extraction."
        ) { $0.clean && $0.low(.acidity) && $0.notLow(.sweetness) },
        DialInRule(
            28, .medium, .lessAgitation, else: .coarser, effect: "Better separated flavours",
            why: "Enough intensity but poor clarity is about how it extracts, not how much."
        ) { $0.clean && $0.low(.clarity) && $0.notLow(.intensity) },
        DialInRule(
            29, .low, .lessAgitation, else: .coarser, effect: "More recognisable flavours",
            why: "Exploratory: without an intensity rating, there's no case for extracting more."
        ) { $0.clean && $0.low(.clarity) && $0.unknown(.intensity) },
        DialInRule(
            30, .low, .lessAgitation, else: .coarser, effect: "More distinct flavour",
            why: "Exploratory: low clarity makes low intensity hard to read."
        ) { $0.clean && $0.low(.clarity) && $0.low(.intensity) },
        DialInRule(
            33, .medium, .finer, else: .hotter, effect: "Sweeter, and less acid-led",
            why: "More sweetness balances strong acidity."
        ) { $0.clean && $0.high(.acidity) && $0.low(.sweetness) },
        DialInRule(
            34, .low, .longerRatio, else: .hotter, effect: "Less dominant acidity",
            why: "Exploratory: less concentration or more extraction may soften it."
        ) { $0.clean && $0.high(.acidity) && $0.notLow(.sweetness) },
        DialInRule(
            31, .medium, .hotter, else: .finer, effect: "More developed sweetness",
            why: "Nothing tastes wrong and it isn't too strong, so extracting more is a fair test."
        ) { $0.clean && $0.low(.sweetness) && $0.notHigh(.intensity) },
        DialInRule(
            32, .medium, .longerRatio, else: .cooler, effect: "Less overwhelming, and sweeter-seeming",
            why: "Too much intensity can hide sweetness; more water also extracts a little more."
        ) { $0.clean && $0.low(.sweetness) && $0.high(.intensity) },
    ]

    /// One attribute off, little else to go on.
    static let isolated: [DialInRule] = [
        DialInRule(
            39, .medium, .shorterRatio, else: .finer, effect: "More persistent flavour",
            why: "More concentrated flavour may last longer."
        ) { $0.clean && $0.low(.finish) && $0.low(.intensity) },
        DialInRule(
            40, .low, .hotter, else: .finer, effect: "Sweeter, with a longer finish",
            why: "Exploratory: more extraction may help the flavour persist."
        ) { $0.clean && $0.low(.finish) && $0.low(.sweetness) },
        DialInRule(
            42, .medium, .longerRatio, else: .coarser, effect: "Less persistent, and less intense",
            why: "Less strength may shorten the finish."
        ) { $0.clean && $0.high(.finish) && $0.high(.intensity) },
        DialInRule(
            35, .medium, .finer, else: .shorterRatio, effect: "More intense flavour",
            why: "More extraction or more concentration may lift weak flavour."
        ) { $0.clean && $0.low(.intensity) },
        DialInRule(
            36, .high, .longerRatio, else: .coarser, effect: "Less intense",
            why: "More water directly reduces strength."
        ) { $0.clean && $0.high(.intensity) },
        DialInRule(
            37, .low, .coarser, else: .cooler, effect: "Brighter acidity",
            why: "Exploratory: gentler extraction may brighten it, but the evidence is thin."
        ) { $0.clean && $0.low(.acidity) },
        DialInRule(
            38, .low, .longerRatio, else: .hotter, effect: "Less dominant acidity",
            why: "Exploratory: more water is a cautious first step."
        ) { $0.clean && $0.high(.acidity) },
        DialInRule(
            41, .low, .shorterRatio, else: .finer, effect: "A longer, more noticeable finish",
            why: "Exploratory: a stronger cup may hold its finish longer."
        ) { $0.clean && $0.low(.finish) },
        DialInRule(
            43, .low, .longerRatio, else: .coarser, effect: "A shorter, lighter finish",
            why: "Exploratory: finish length has many causes; more water is the gentlest test."
        ) { $0.clean && $0.high(.finish) },
        DialInRule(
            44, .medium, .shorterRatio, else: .finer, effect: "Fuller texture",
            why: "Concentration is the first thing to try for a thin body."
        ) { $0.clean && $0.low(.body) },
        DialInRule(
            45, .medium, .longerRatio, else: .lessAgitation, effect: "Lighter texture",
            why: "Less concentration, or fewer fines, may reduce the weight."
        ) { $0.clean && $0.high(.body) },
        DialInRule(
            46, .low, .hotter, else: .finer, effect: "More apparent sweetness",
            why: "Exploratory: with little else to go on, extract a bit more."
        ) { $0.clean && $0.low(.sweetness) },
        DialInRule(
            47, .low, .longerRatio, else: .coarser, effect: "Less cloying",
            why: "Exploratory: less concentration may make it less cloying."
        ) { $0.clean && $0.high(.sweetness) },
        DialInRule(
            48, .low, .moreAgitation, else: .finer, effect: "Fuller, more integrated flavour",
            why: "Exploratory: too much separation can taste thin."
        ) { $0.clean && $0.high(.clarity) },
    ]
}
