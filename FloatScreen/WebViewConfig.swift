import WebKit

final class WebViewConfig: NSObject, WKNavigationDelegate, WKUIDelegate,
                           WKDownloadDelegate, WKScriptMessageHandler {
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

        let script = WKUserScript(
            source: Self.fullscreenScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        let ucc = webView.configuration.userContentController
        ucc.addUserScript(script)
        ucc.add(WeakMessageHandler(delegate: self), name: "fullscreen")
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

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        guard message.name == "fullscreen",
              let body = message.body as? [String: String],
              let action = body["action"] else { return }

        if action == "enter" {
            containerWindow?.enterContainerFullscreen()
        } else if action == "exit" {
            containerWindow?.exitContainerFullscreen()
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        containerWindow?.webViewDidUpdate()
        containerWindow?.syncFullscreenFlag()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        containerWindow?.webViewDidUpdate()
        containerWindow?.exitContainerFullscreen()
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
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

// MARK: - Fullscreen-in-Container Script

extension WebViewConfig {
    static let fullscreenScript = """
    (function() {
        'use strict';
        if (window.__fsInit) return;
        window.__fsInit = true;
        window.__fsFake = true;

        var _el = null;

        var s = document.createElement('style');
        s.textContent = '.__fs_fill{position:fixed!important;top:0!important;left:0!important;' +
            'width:100vw!important;height:100vh!important;z-index:2147483647!important;' +
            'background:#000!important;margin:0!important;padding:0!important;' +
            'border:none!important;transform:none!important;object-fit:contain!important;}';
        (document.head || document.documentElement).appendChild(s);

        var _reqFS = Element.prototype.requestFullscreen;
        var _reqWK = Element.prototype.webkitRequestFullscreen;
        var _reqWK2 = Element.prototype.webkitRequestFullScreen;
        var _exitFS = Document.prototype.exitFullscreen;
        var _exitWK = Document.prototype.webkitExitFullscreen;
        var _exitWK2 = Document.prototype.webkitCancelFullScreen;

        function fire(t) {
            t.dispatchEvent(new Event('fullscreenchange', {bubbles:true}));
            t.dispatchEvent(new Event('webkitfullscreenchange', {bubbles:true}));
        }

        function enter(el) {
            if (_el) exit();
            _el = el;
            el.classList.add('__fs_fill');
            fire(el); fire(document);
            try { window.webkit.messageHandlers.fullscreen.postMessage({action:'enter'}); } catch(e) {}
        }

        function exit() {
            if (!_el) return;
            var el = _el;
            _el = null;
            el.classList.remove('__fs_fill');
            fire(el); fire(document);
            try { window.webkit.messageHandlers.fullscreen.postMessage({action:'exit'}); } catch(e) {}
        }

        Element.prototype.requestFullscreen = function(o) {
            if (!window.__fsFake) return _reqFS ? _reqFS.call(this, o) : Promise.resolve();
            enter(this); return Promise.resolve();
        };
        Element.prototype.webkitRequestFullscreen = function() {
            if (!window.__fsFake) { if (_reqWK) _reqWK.call(this); return; }
            enter(this);
        };
        Element.prototype.webkitRequestFullScreen = function() {
            if (!window.__fsFake) { if (_reqWK2) _reqWK2.call(this); return; }
            enter(this);
        };

        Document.prototype.exitFullscreen = function() {
            if (!window.__fsFake) return _exitFS ? _exitFS.call(this) : Promise.resolve();
            exit(); return Promise.resolve();
        };
        Document.prototype.webkitExitFullscreen = function() {
            if (!window.__fsFake) { if (_exitWK) _exitWK.call(this); return; }
            exit();
        };
        Document.prototype.webkitCancelFullScreen = function() {
            if (!window.__fsFake) { if (_exitWK2) _exitWK2.call(this); return; }
            exit();
        };

        Object.defineProperty(document, 'fullscreenElement', {
            get: function() { return window.__fsFake ? _el : null; }, configurable: true
        });
        Object.defineProperty(document, 'webkitFullscreenElement', {
            get: function() { return window.__fsFake ? _el : null; }, configurable: true
        });
        Object.defineProperty(document, 'webkitCurrentFullScreenElement', {
            get: function() { return window.__fsFake ? _el : null; }, configurable: true
        });
        Object.defineProperty(document, 'fullscreenEnabled', {
            get: function() { return true; }, configurable: true
        });
        Object.defineProperty(document, 'webkitFullscreenEnabled', {
            get: function() { return true; }, configurable: true
        });
        Object.defineProperty(document, 'webkitIsFullScreen', {
            get: function() { return _el !== null; }, configurable: true
        });

        document.addEventListener('keydown', function(e) {
            if (e.key === 'Escape' && _el) {
                e.preventDefault();
                e.stopPropagation();
                exit();
            }
        }, true);
    })();
    """
}

// Weak proxy to avoid the retain cycle:
// WKUserContentController retains the handler strongly.
private class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ ucc: WKUserContentController,
                                didReceive message: WKScriptMessage) {
        delegate?.userContentController(ucc, didReceive: message)
    }
}
