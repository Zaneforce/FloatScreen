import WebKit

final class WebViewConfig: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private weak var webView: WKWebView?
    private weak var containerWindow: ContainerWindow?

    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.isElementFullscreenEnabled = true

        return config
    }

    func attach(to webView: WKWebView, container: ContainerWindow) {
        self.webView = webView
        self.containerWindow = container
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = Self.safariUserAgent
        webView.allowsBackForwardNavigationGestures = true
    }

    static func navigate(_ webView: WKWebView, to input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let url: URL?
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            url = URL(string: trimmed)
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            url = URL(string: "https://\(trimmed)")
        } else {
            let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            url = URL(string: "https://www.google.com/search?q=\(query)")
        }

        if let url {
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        containerWindow?.webViewDidUpdate()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        containerWindow?.webViewDidUpdate()
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            decisionHandler(.download)
        }
    }

    func webView(_ webView: WKWebView,
                 navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView,
                 navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: - WKDownloadDelegate

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        var destination = downloadsURL.appendingPathComponent(suggestedFilename)

        // Avoid overwriting
        var counter = 1
        let name = destination.deletingPathExtension().lastPathComponent
        let ext = destination.pathExtension
        while FileManager.default.fileExists(atPath: destination.path) {
            let newName = ext.isEmpty ? "\(name) (\(counter))" : "\(name) (\(counter)).\(ext)"
            destination = downloadsURL.appendingPathComponent(newName)
            counter += 1
        }

        completionHandler(destination)
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target=_blank: open in the same container
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
