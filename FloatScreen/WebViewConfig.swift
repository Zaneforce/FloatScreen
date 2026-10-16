import WebKit

final class WebViewConfig: NSObject, WKNavigationDelegate, WKUIDelegate,
                           WKDownloadDelegate, WKScriptMessageHandler {
    private weak var webView: WKWebView?
    private weak var containerWindow: ContainerWindow?

    static let safariVersion: String = {
        let paths = [
            "/Applications/Safari.app/Contents/Info.plist",
            "/System/Cryptexes/App/System/Applications/Safari.app/Contents/Info.plist",
        ]
        for path in paths {
            if let plist = NSDictionary(contentsOfFile: path),
               let version = plist["CFBundleShortVersionString"] as? String {
                print("[FloatScreen] Safari version \(version) from \(path)")
                return version
            }
        }
        if let safariURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Safari"
        ) {
            let plistURL = safariURL.appendingPathComponent("Contents/Info.plist")
            if let plist = NSDictionary(contentsOf: plistURL),
               let version = plist["CFBundleShortVersionString"] as? String {
                print("[FloatScreen] Safari version \(version) from NSWorkspace: \(plistURL.path)")
                return version
            }
        }
        print("[FloatScreen] Could not detect Safari version, using fallback 26.0")
        return "26.0"
    }()

    static var desktopUserAgent: String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariVersion) Safari/605.1.15"
    }

    private static var iosVersionString: String {
        safariVersion.replacingOccurrences(of: ".", with: "_")
    }

    static var mobileUserAgent: String {
        "Mozilla/5.0 (iPhone; CPU iPhone OS \(iosVersionString) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariVersion) Mobile/15E148 Safari/604.1"
    }

    // Per-domain UA overrides. Add entries here when a site needs a specific UA.
    static var siteUserAgentOverrides: [String: String] = [:]

    // MARK: - Page Zoom

    static let zoomSteps: [CGFloat] = [0.5, 0.67, 0.75, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5]

    private static let zoomKey = "siteZoomLevels"

    static func savedZoom(for host: String, profileId: UUID) -> CGFloat? {
        guard let dict = UserDefaults.standard.dictionary(forKey: zoomKey) as? [String: Double] else { return nil }
        return dict["\(profileId.uuidString):\(host)"].map { CGFloat($0) }
    }

    static func saveZoom(_ zoom: CGFloat, for host: String, profileId: UUID) {
        var dict = (UserDefaults.standard.dictionary(forKey: zoomKey) as? [String: Double]) ?? [:]
        dict["\(profileId.uuidString):\(host)"] = Double(zoom)
        UserDefaults.standard.set(dict, forKey: zoomKey)
    }

    // MARK: - Always-Desktop Sites

    private static let alwaysDesktopKey = "alwaysDesktopSites"
    private static let defaultAlwaysDesktop = ["app.slack.com", "slack.com", "*.slack.com"]

    static var alwaysDesktopSites: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: alwaysDesktopKey) ?? defaultAlwaysDesktop
        }
        set {
            UserDefaults.standard.set(newValue, forKey: alwaysDesktopKey)
        }
    }

    static func isAlwaysDesktop(host: String) -> Bool {
        for pattern in alwaysDesktopSites {
            if pattern == host { return true }
            if pattern.hasPrefix("*.") {
                let suffix = String(pattern.dropFirst(1))
                if host.hasSuffix(suffix) || host == String(pattern.dropFirst(2)) { return true }
            }
        }
        return false
    }

    static func makeConfiguration(profile: Profile = .personal) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = ProfileManager.dataStore(for: profile)

        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.isElementFullscreenEnabled = true
        config.mediaTypesRequiringUserActionForPlayback = []

        return config
    }

    func attach(to webView: WKWebView, container: ContainerWindow) {
        self.webView = webView
        self.containerWindow = container
        webView.navigationDelegate = self
        webView.uiDelegate = self
        Self.applyUserAgent(to: webView, mobile: container.isMobileMode)
        webView.allowsBackForwardNavigationGestures = true

        let script = WKUserScript(
            source: Self.fullscreenScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        let ucc = webView.configuration.userContentController
        ucc.addUserScript(script)
        let weakHandler = WeakMessageHandler(delegate: self)
        ucc.add(weakHandler, name: "fullscreen")
        ucc.add(weakHandler, name: "unread")
        ucc.add(weakHandler, name: "notification")

        let notifScript = WKUserScript(
            source: Self.notificationPolyfill,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        ucc.addUserScript(notifScript)

        ContentBlocker.shared.apply(to: ucc)

        let ytScript = WKUserScript(
            source: YouTubeAdSkipper.script,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        ucc.addUserScript(ytScript)

        let slackScript = WKUserScript(
            source: UnreadDetector.slackScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        ucc.addUserScript(slackScript)
    }

    static func applyUserAgent(to webView: WKWebView, mobile: Bool, host: String? = nil) {
        if let host, let override = siteUserAgentOverrides[host] {
            webView.customUserAgent = override
            print("[FloatScreen] UA override for \(host): \(override)")
        } else if mobile {
            webView.customUserAgent = mobileUserAgent
            print("[FloatScreen] UA (mobile): \(mobileUserAgent)")
        } else {
            webView.customUserAgent = desktopUserAgent
            print("[FloatScreen] UA (desktop): \(desktopUserAgent)")
        }
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
        switch message.name {
        case "fullscreen":
            guard let body = message.body as? [String: String],
                  let action = body["action"] else { return }
            if action == "enter" {
                containerWindow?.enterContainerFullscreen()
            } else if action == "exit" {
                containerWindow?.exitContainerFullscreen()
            }
        case "unread":
            guard let body = message.body as? [String: Any],
                  let count = body["count"] as? Int else { return }
            containerWindow?.updateUnreadCount(count)
        case "notification":
            guard let body = message.body as? [String: Any],
                  let title = body["title"] as? String else { return }
            let notifBody = body["body"] as? String
            let notifId = body["id"] as? String ?? UUID().uuidString
            NotificationForwarder.shared.post(
                id: notifId,
                title: title,
                body: notifBody,
                container: containerWindow
            )
        default:
            break
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        containerWindow?.webViewDidUpdate()
        containerWindow?.syncFullscreenFlag()
        webView.evaluateJavaScript("navigator.userAgent") { result, _ in
            if let ua = result as? String {
                let host = webView.url?.host ?? "unknown"
                print("[FloatScreen] navigator.userAgent on \(host): \(ua)")
            }
        }
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
        // window.open() / OAuth popups need a real child webview so
        // window.opener and postMessage work for "Sign in with Google" etc.
        let isWindowOpen = navigationAction.navigationType == .other
        let hasFeatures = windowFeatures.width != nil || windowFeatures.height != nil

        if isWindowOpen || hasFeatures {
            return openPopup(configuration: configuration, windowFeatures: windowFeatures)
        }

        // Plain target=_blank link click: load in the same container
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        // OAuth popup called window.close()
        webView.window?.close()
    }

    private func openPopup(configuration: WKWebViewConfiguration,
                            windowFeatures: WKWindowFeatures) -> WKWebView {
        let w = windowFeatures.width?.doubleValue ?? 500
        let h = windowFeatures.height?.doubleValue ?? 600
        let popupRect = NSRect(x: 300, y: 300, width: w, height: h)

        let popupView = WKWebView(frame: .zero, configuration: configuration)
        popupView.customUserAgent = Self.desktopUserAgent
        popupView.uiDelegate = self

        let popup = NSPanel(
            contentRect: popupRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        popup.title = "Sign In"
        popup.level = .floating
        popup.hidesOnDeactivate = false
        popup.becomesKeyOnlyIfNeeded = false
        popup.appearance = NSAppearance(named: .darkAqua)
        popup.contentView = popupView
        popup.center()
        popup.orderFront(nil)

        return popupView
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

// MARK: - Notification Polyfill Script

extension WebViewConfig {
    static let notificationPolyfill = """
    (function() {
        'use strict';
        if (window.__fsNotifInit) return;
        window.__fsNotifInit = true;

        var _id = 0;
        var _callbacks = {};

        function FSNotification(title, options) {
            options = options || {};
            this.title = title;
            this.body = options.body || '';
            this.icon = options.icon || '';
            this.tag = options.tag || '';
            this._id = String(++_id);
            this.onclick = null;

            _callbacks[this._id] = this;

            try {
                window.webkit.messageHandlers.notification.postMessage({
                    id: this._id,
                    title: title,
                    body: this.body,
                    icon: this.icon,
                    tag: this.tag
                });
            } catch(e) {}
        }

        FSNotification.permission = 'granted';
        FSNotification.requestPermission = function(cb) {
            if (cb) cb('granted');
            return Promise.resolve('granted');
        };
        FSNotification.prototype.close = function() {};
        FSNotification.prototype.addEventListener = function() {};

        window.Notification = FSNotification;
    })();
    """
}

// MARK: - Native Notification Forwarder

import UserNotifications

final class NotificationForwarder: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationForwarder()

    private override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private var iconCache: [String: URL] = [:]

    func post(id: String, title: String, body: String?, container: ContainerWindow?) {
        let siteName = container?.webView.url?.host ?? container?.pageTitle ?? "FloatScreen"
        let content = UNMutableNotificationContent()
        content.title = "\(siteName) \u{00b7} \(title)"
        if let body { content.body = body }
        if let name = container?.profile.name {
            content.subtitle = name
        }

        let soundMode = container?.soundMode ?? .floatScreenSound
        switch soundMode {
        case .floatScreenSound:
            content.sound = .default
        case .siteSounds, .silent:
            content.sound = nil
        }

        if let cid = container?.containerID.uuidString {
            content.userInfo["containerId"] = cid
        }
        content.userInfo["notifId"] = id

        if let host = container?.webView.url?.host,
           let cachedURL = iconCache[host],
           let attachment = try? UNNotificationAttachment(identifier: "icon", url: cachedURL) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: "fs-\(id)-\(UUID().uuidString.prefix(4))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)

        cacheSiteIcon(for: container)
    }

    func cacheSiteIcon(for container: ContainerWindow?) {
        guard let webView = container?.webView,
              let host = webView.url?.host,
              iconCache[host] == nil else { return }

        let js = """
        (function(){
            var link = document.querySelector('link[rel*="icon"]');
            return link ? link.href : (location.origin + '/favicon.ico');
        })()
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let urlStr = result as? String, let url = URL(string: urlStr) else { return }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let img = NSImage(data: data), img.isValid else { return }
                let size = NSSize(width: 128, height: 128)
                let resized = NSImage(size: size)
                resized.lockFocus()
                img.draw(in: NSRect(origin: .zero, size: size),
                         from: NSRect(origin: .zero, size: img.size),
                         operation: .copy, fraction: 1.0)
                resized.unlockFocus()

                guard let tiff = resized.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else { return }

                let tmpDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("FloatScreenIcons", isDirectory: true)
                try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                let fileURL = tmpDir.appendingPathComponent("\(host).png")
                try? png.write(to: fileURL)

                DispatchQueue.main.async {
                    self?.iconCache[host] = fileURL
                }
            }.resume()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 didReceive response: UNNotificationResponse,
                                 withCompletionHandler handler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let cidStr = userInfo["containerId"] as? String,
           let cid = UUID(uuidString: cidStr),
           let appDelegate = NSApp.delegate as? AppDelegate {
            if let bubble = appDelegate.bubbles.first(where: { $0.container?.containerID == cid }) {
                appDelegate.restoreFromBubble(bubble)
            } else if let container = appDelegate.containers.first(where: { $0.containerID == cid }) {
                NSApp.activate(ignoringOtherApps: true)
                container.makeKeyAndOrderFront(nil)
            }
        }
        handler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 willPresent notification: UNNotification,
                                 withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }
}
