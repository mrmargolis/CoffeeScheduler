import SwiftUI
import WebKit

/// What "Use this page" reads off a web page.
struct PageContent: Decodable, Sendable {
    /// The page's main heading, else its title: a product page's coffee.
    var heading: String
    /// The browser's title, which often ends with the site's name.
    var title: String
    /// The site's name from its `og:site_name`: a roaster's shop's name.
    var site: String
    var text: String
    var url = ""

    private enum CodingKeys: String, CodingKey {
        case heading, title, site, text
    }
}

/// A browser for finding the coffee's page, with a button that reads the
/// page into the bag. The page is read only when that's tapped.
struct PageBrowser: View {
    let start: URL
    let onUse: (PageContent) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var browser = BrowserState()
    @State private var failed = false

    var body: some View {
        NavigationStack {
            WebViewHost(webView: browser.webView)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(browser.host)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use this page") { Task { await use() } }
                            .disabled(browser.isLoading || browser.isSearchPage)
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button("Back", systemImage: "chevron.backward") { browser.webView.goBack() }
                            .disabled(!browser.canGoBack)
                        Spacer()
                        Text(browser.isSearchPage ? "Open the coffee's page, then tap Use this page." : "")
                            .font(.caption)
                            .foregroundStyle(Theme.text3)
                        Spacer()
                    }
                }
                .alert("Couldn't read this page", isPresented: $failed) {
                    Button("OK", role: .cancel) {}
                }
        }
        .onAppear { browser.load(start) }
    }

    private func use() async {
        guard var content = await browser.content() else {
            failed = true
            return
        }
        content.url = browser.webView.url?.absoluteString ?? ""
        onUse(content)
        dismiss()
    }
}

/// The web view and what the toolbar shows about it.
@MainActor @Observable
final class BrowserState {
    let webView = WKWebView()
    private(set) var canGoBack = false
    private(set) var isLoading = false
    private(set) var host = ""
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init() {
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.canGoBack) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.isLoading) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.isLoading = view.isLoading }
            },
            webView.observe(\.url) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.host = view.url?.host() ?? "" }
            },
        ]
    }

    /// Google's results, which aren't the coffee's page.
    var isSearchPage: Bool {
        host.hasPrefix("www.google.") || host.hasPrefix("google.")
    }

    func load(_ url: URL) {
        guard webView.url == nil else { return }
        webView.load(URLRequest(url: url))
    }

    /// The page's heading, site name and text; nil when it can't be read.
    func content() async -> PageContent? {
        let script = """
            JSON.stringify({
              heading: ((document.querySelector('h1') || {}).innerText || document.title || '').trim(),
              title: document.title || '',
              site: (document.querySelector('meta[property="og:site_name"]') || {}).content || '',
              text: document.body ? document.body.innerText : ''
            })
            """
        guard let json = try? await webView.evaluateJavaScript(script) as? String else { return nil }
        return try? JSONDecoder().decode(PageContent.self, from: Data(json.utf8))
    }
}

private struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
