import Foundation

/// Reading the coffee's page, from "Use this page".
extension BagLabel {
    /// The details on a web page, from its text: only what's labelled, since
    /// a page's menus and other coffees name countries and flavours too. The
    /// page's heading, site name and address are the coffee, roaster and
    /// link (see `coffeeName(inHeading:)`); without a site name, the roaster
    /// is the end of the browser's title ("suke quto – delicate coffee
    /// roasters"), and a roaster the app knows keeps its name in the app.
    /// All of it is stated: it's the page for the coffee.
    public static func details(of page: Page, knownRoasters: [String], today: String) -> BagDraft {
        // The page's summary for search engines last, in sentences: "Chelbesa — Ethiopia, Gedeb, Gedeo.
        // Tasting notes: Yellow Nectarine, Wildflower Honey, Orange Zest"
        let summary = page.summary.components(separatedBy: ". ")
        let lines = (page.text.split(whereSeparator: \.isNewline).map(String.init) + summary)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var draft = labelled(lines, today: today)
        draft.coffee = coffeeName(inHeading: page.heading)
        let roaster = tidy(page.site.isEmpty ? siteName(inTitle: page.title, heading: draft.coffee) : page.site, name: true)
        draft.roaster = knownRoaster(named: roaster, from: knownRoasters) ?? roaster
        draft.url = page.url
        for field in [BagField.coffee, .roaster, .url] where draft.has(field) {
            draft.certainty[field] = .stated
        }
        // A country, variety or process in the heading, where no label gave one
        fillEmpty(&draft, from: details(inHeading: page.heading))
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
        /// The page's summary for search engines, its `description`, which
        /// some shops write as the coffee's details.
        public var summary: String

        public init(heading: String, title: String, site: String, text: String, url: String, summary: String = "") {
            self.heading = heading
            self.title = title
            self.site = site
            self.text = text
            self.url = url
            self.summary = summary
        }
    }

    /// The site's name at the end of a browser title, after the page's own:
    /// "delicate coffee roasters" in "suke quto – delicate coffee roasters".
    static func siteName(inTitle title: String, heading: String) -> String {
        let parts = title.components(separatedBy: CharacterSet(charactersIn: "|–—·")).flatMap { $0.components(separatedBy: " - ") }
        guard parts.count > 1, let last = parts.last?.trimmingCharacters(in: .whitespaces), fold(last) != fold(heading) else { return "" }
        return last
    }
}
