import Foundation

extension BagLabel {
    /// The roaster found on a label, and which lines are its logo and its
    /// "Coffee Roasters": none of them is the coffee's name.
    struct RoasterMatch {
        var name: String?
        var lines: Set<Int> = []
    }

    /// The roaster: one the app knows, matched by the distinctive part of
    /// its name ("September" for "September Coffee Co."), or else the logo
    /// over a "Coffee Roasters" or "Coffee Co." line.
    static func roaster(in lines: [Line], knownRoasters: [String]) -> RoasterMatch {
        let generic = Set(lines.indices.filter { isGeneric(lines[$0]) })
        var match = knownRoaster(in: lines, from: knownRoasters) ?? printedRoaster(in: lines, generic: generic)
        match.lines.formUnion(generic)
        return match
    }

    /// The part of a roaster's name that tells it apart: without "Coffee",
    /// "Roasters", "Co." and the like.
    static func distinctiveName(_ roaster: String) -> String {
        let core = fold(roaster).split(separator: " ").filter { !wordSet(String($0)).isSubset(of: roasterWords) }
        return core.isEmpty ? fold(roaster) : core.joined(separator: " ")
    }

    /// The known roaster with the longest distinctive name on the label.
    private static func knownRoaster(in lines: [Line], from roasters: [String]) -> RoasterMatch? {
        let folded = lines.map { fold($0.text) }
        let matches = roasters.compactMap { roaster -> (String, String, Set<Int>)? in
            let core = distinctiveName(roaster)
            guard core.filter(\.isLetter).count >= 2 else { return nil }
            let found = Set(folded.indices.filter { contains(folded[$0], phrase: core) })
            return found.isEmpty ? nil : (roaster, core, found)
        }
        guard let best = matches.max(by: { ($0.1.count, $0.0.count) < ($1.1.count, $1.0.count) }) else { return nil }
        return RoasterMatch(name: best.0, lines: best.2)
    }

    /// The roaster as printed: a line like "Thankfully Coffee", or the logo
    /// over a line of only "Coffee Roasters" (climbing past a separate
    /// "Coffee" over "Roasters"). The biggest such logo wins.
    private static func printedRoaster(in lines: [Line], generic: Set<Int>) -> RoasterMatch {
        let stacks = generic.compactMap { start -> [Int]? in
            var stack = [start]
            while stack.count < 4, let above = line(above: stack[stack.count - 1], in: lines) {
                stack.append(above)
                if !generic.contains(above) { return stack.reversed() }
            }
            return nil
        }
        // The biggest logo; of two climbs to it, the one with more words
        if let logo = stacks.max(by: { (lines[$0[0]].height, $0.count) < (lines[$1[0]].height, $1.count) }) {
            return RoasterMatch(name: logo.map { lines[$0].text }.joined(separator: " "), lines: Set(logo))
        }
        if let named = lines.indices.filter({ endsInRoasterWords(lines[$0]) }).max(by: { lines[$0].height < lines[$1].height }) {
            return RoasterMatch(name: lines[named].text, lines: [named])
        }
        return RoasterMatch()
    }

    /// The nearest line just over this one, sharing some of its width.
    private static func line(above index: Int, in lines: [Line]) -> Int? {
        let line = lines[index]
        return lines.indices.filter { other in
            let candidate = lines[other]
            let gap = candidate.y - line.top
            return other != index && candidate.y >= line.y + line.height * 0.5
                && gap <= max(line.height, candidate.height) * 1.5 && candidate.overlapsHorizontally(line)
        }
        .min { lines[$0].y < lines[$1].y }
    }

    /// A line of only "Coffee", "Roasters", "Co." and the like.
    private static func isGeneric(_ line: Line) -> Bool {
        let words = wordSet(fold(line.text))
        return !words.isEmpty && words.isSubset(of: roasterWords)
    }

    /// "Thankfully Coffee" or "Onyx Coffee Lab": a name, then roaster words
    /// that say it's a roaster's.
    private static func endsInRoasterWords(_ line: Line) -> Bool {
        let words = fold(line.text).split { !$0.isLetter }.map(String.init)
        guard words.count >= 2, let first = words.first, let last = words.last else { return false }
        let saysRoaster = words.contains { $0 == "coffee" || $0.hasPrefix("roast") }
        return saysRoaster && roasterWords.contains(last) && !roasterWords.contains(first) && nameCandidate(line) != nil
    }
}
