import Foundation

/// Reading the coffee's page, from "Use this page".
extension BagLabel {
    /// The details on a web page, from its text: only what's labelled, since
    /// a page's menus and other coffees name countries and flavours too. The
    /// page's heading, site name and address are the coffee, roaster and
    /// link (see `coffeeName(inHeading:)`); without a site name, the roaster is the end of the browser's
    /// title ("suke quto – delicate coffee roasters"), and a roaster the app
    /// knows keeps its name in the app. All of it is stated: it's the page
    /// for the coffee.
    public static func details(of page: Page, knownRoasters: [String], today: String) -> BagDraft {
        let lines = page.text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var draft = labelled(lines, today: today)
        draft.coffee = coffeeName(inHeading: page.heading)
        let roaster = tidy(page.site.isEmpty ? siteName(inTitle: page.title, heading: draft.coffee) : page.site, name: true)
        draft.roaster = knownRoaster(named: roaster, from: knownRoasters) ?? roaster
        draft.url = page.url
        for field in [BagField.coffee, .roaster, .url] where draft.has(field) {
            draft.certainty[field] = .stated
        }
        return draft
    }

    /// What "Use this page" reads off a page.
    public struct Page: Sendable {
        /// The main heading: on a product page, the coffee.
        public var heading: String
        /// The browser's title, which often ends with the site's name.
        public var title: String
        /// The site's own name for itself, from its `og:site_name`.
        public var site: String
        public var text: String
        public var url: String

        public init(heading: String, title: String, site: String, text: String, url: String) {
            self.heading = heading
            self.title = title
            self.site = site
            self.text = text
            self.url = url
        }
    }

    /// The site's name at the end of a browser title, after the page's own:
    /// "delicate coffee roasters" in "suke quto – delicate coffee roasters".
    static func siteName(inTitle title: String, heading: String) -> String {
        let parts = title.components(separatedBy: CharacterSet(charactersIn: "|–—·")).flatMap { $0.components(separatedBy: " - ") }
        guard parts.count > 1, let last = parts.last?.trimmingCharacters(in: .whitespaces), fold(last) != fold(heading) else { return "" }
        return last
    }

    /// The coffee's name in a page's heading, without what shops add to it:
    /// the bag's size ("Gititu AB 100g"), parts that are only its origin,
    /// variety or process ("Dege Mullugeta - Ethiopia Anaerobic Natural",
    /// "Juliana Guevara & Wbeimar Lasso | Java"), a roast level or year in
    /// brackets ("Muchagara AB (Extra-light)"), and a country in front
    /// ("Ethiopia Habtamu Fekadu").
    static func coffeeName(inHeading heading: String) -> String {
        guard let firstLine = heading.split(whereSeparator: \.isNewline).first else { return "" }
        var text = String(firstLine)
        for pattern in [#"(?i)\s*\d+(?:[.,]\d+)?\s*(?:kg|g|oz|lbs?)\b"#, #"\s*\([^)]*\)"#] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        let parts = text.components(separatedBy: CharacterSet(charactersIn: "|–—·")).flatMap { $0.components(separatedBy: " - ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let named = parts.filter { !isOnlyDetails($0) }
        guard var name = (named.isEmpty ? parts : named).first.map({ withoutLeadingCountry($0) }) else { return "" }
        // Further name parts: "Abana Estate | Anderacha"
        for part in named.dropFirst() { name += " " + part }
        return tidy(name, name: true)
    }

    /// Whether every word is an origin, variety, process or roast word.
    private static func isOnlyDetails(_ text: String) -> Bool {
        let words = fold(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return !words.isEmpty && words.allSatisfy(detailVocabulary.contains)
    }

    /// "Habtamu Fekadu" from "Ethiopia Habtamu Fekadu"; a name that's only a
    /// country is left alone.
    private static func withoutLeadingCountry(_ text: String) -> String {
        let folded = fold(text)
        for country in countries.flatMap({ [fold($0.name)] + $0.spellings }) where folded.hasPrefix(country + " ") {
            let rest = text.dropFirst(country.count).trimmingCharacters(in: .whitespaces)
            return isOnlyDetails(rest) ? text : rest
        }
        return text
    }

    private static var detailVocabulary: Set<String> {
        let names = (countries + regions + varieties).flatMap { [fold($0.name)] + $0.spellings }
        let words = names.flatMap { $0.split { !$0.isLetter && !$0.isNumber }.map(String.init) }
        let roast = ["light", "medium", "dark", "roast", "extra", "ultralight", "espresso", "filter", "omni", "field", "blend"]
        return Set(words).union(processWords).union(processQualifiers).union(roast)
    }
}
