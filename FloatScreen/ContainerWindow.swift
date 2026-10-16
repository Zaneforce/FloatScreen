import AppKit
import WebKit

final class ContainerWindow: NSPanel {
    private(set) var webView: WKWebView
    let toolbarView: ToolbarView
    var webConfig: WebViewConfig
    let containerID: UUID
    private(set) var profile: Profile

    private var toolbarHeightConstraint: NSLayoutConstraint!
    private var isToolbarAutoHidden = false
    private var accentBar: NSView!

    var fullscreenFillsContainer = true
    private var isInContainerFullscreen = false
    private var toolbarWasVisibleBeforeFullscreen = true

    private(set) var isMobileMode = false
    var isAutoMobile = false
    private static let autoMobileOnThreshold: CGFloat = 500
    private static let autoMobileOffThreshold: CGFloat = 600
    private var autoMobileDebounceTimer: Timer?

    enum SoundMode: String, CaseIterable {
        case siteSounds = "site"
        case floatScreenSound = "floatscreen"
        case silent = "silent"

        var label: String {
            switch self {
            case .siteSounds: return "Site Sounds"
            case .floatScreenSound: return "FloatScreen Sound"
            case .silent: return "Silent"
            }
        }
    }

    var soundMode: SoundMode = .floatScreenSound
    var savedFrameBeforeMinimize: NSRect?
    var savedBubbleOrigin: NSPoint?
    var savedBubbleEdge: String?
    private var zoomHideTimer: Timer?

    private static let slackHosts = ["app.slack.com", "slack.com"]

    private var webViewTopConstraint: NSLayoutConstraint!
    private var containerView: NSView!

    private static let mobileDomainMap: [(mobile: String, desktop: String)] = [
        ("m.youtube.com", "www.youtube.com"),
        ("m.facebook.com", "www.facebook.com"),
        ("m.twitter.com", "twitter.com"),
        ("mobile.twitter.com", "twitter.com"),
        ("m.reddit.com", "www.reddit.com"),
        ("m.wikipedia.org", "en.wikipedia.org"),
    ]

    init(id: UUID = UUID(), url: URL? = nil, state: ContainerState? = nil,
         profile: Profile? = nil) {
        self.containerID = id
        self.profile = profile ?? ProfileManager.shared.defaultProfile
        self.webConfig = WebViewConfig()
        self.toolbarView = ToolbarView()
        self.webView = WKWebView(
            frame: .zero,
            configuration: WebViewConfig.makeConfiguration(profile: self.profile)
        )

        let rect: NSRect
        if let s = state {
            rect = NSRect(x: s.x, y: s.y, width: s.width, height: s.height)
        } else {
            rect = NSRect(x: 200, y: 200, width: 800, height: 600)
        }

        super.init(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable,
                        .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        self.title = "FloatScreen"
        level = .floating
        isOpaque = false
        backgroundColor = .black
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        contentMinSize = NSSize(width: 320, height: 200)
        becomesKeyOnlyIfNeeded = false

        let container = HoverContentView(owner: self)
        container.wantsLayer = true
        self.contentView = container
        self.containerView = container

        accentBar = NSView()
        accentBar.wantsLayer = true
        accentBar.layer?.backgroundColor = self.profile.color.cgColor
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(accentBar)

        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbarView)

        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)

        toolbarHeightConstraint = toolbarView.heightAnchor.constraint(
            equalToConstant: ToolbarView.height
        )
        webViewTopConstraint = webView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor)

        NSLayoutConstraint.activate([
            accentBar.topAnchor.constraint(equalTo: container.topAnchor),
            accentBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            accentBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            accentBar.heightAnchor.constraint(equalToConstant: 2),

            toolbarView.topAnchor.constraint(equalTo: accentBar.bottomAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbarHeightConstraint,

            webViewTopConstraint,
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        toolbarView.delegate = self
        toolbarView.setProfile(self.profile)
        webConfig.attach(to: webView, container: self)

        if let s = state {
            alphaValue = CGFloat(s.opacity)
            if !s.isAlwaysOnTop { level = .normal }
            if s.isToolbarAutoHidden { setToolbarAutoHidden(true, animated: false) }
            fullscreenFillsContainer = s.fullscreenFillsContainer ?? true
            isMobileMode = s.isMobileMode ?? false
            isAutoMobile = s.isAutoMobile ?? false
            WebViewConfig.applyUserAgent(to: webView, mobile: isMobileMode)
            if let sm = s.soundMode, let mode = SoundMode(rawValue: sm) {
                soundMode = mode
            }
        }

        // Default Slack to site sounds so we don't double-play
        if state == nil, let host = url?.host,
           Self.slackHosts.contains(where: { host.hasSuffix($0) }) {
            soundMode = .siteSounds
        }

        toolbarView.updateMobileMode(isMobileMode)

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResize),
            name: NSWindow.didResizeNotification, object: self
        )

        if let url {
            webView.load(URLRequest(url: url))
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Escape must never hide/close the panel. Exit fake fullscreen if active,
    // otherwise forward to the web page (e.g. close a dialog).
    override func cancelOperation(_ sender: Any?) {
        if isInContainerFullscreen {
            webView.evaluateJavaScript(
                "document.fullscreenElement ? document.exitFullscreen() : null",
                completionHandler: nil
            )
            exitContainerFullscreen()
        }
        // Don't call super — that would close/hide the panel
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
            makeKeyAndOrderFront(nil)
        }
        super.sendEvent(event)
    }

    var currentURL: URL? { webView.url }
    var pageTitle: String { webView.title ?? webView.url?.host ?? "New Tab" }
    private(set) var unreadCount: Int = 0
    private(set) var hasUnreadDot: Bool = false

    func webViewDidUpdate() {
        toolbarView.updateURL(webView.url?.absoluteString ?? "")
        toolbarView.updateNavigation(canGoBack: webView.canGoBack, canGoForward: webView.canGoForward)
        toolbarView.updateMobileMode(isMobileMode, disabled: isAlwaysDesktopSite)
        title = pageTitle
        detectUnreadFromTitle()
        applySavedZoom()
        syncVisibilityPolyfill()
    }

    func updateUnreadCount(_ count: Int) {
        unreadCount = count
        hasUnreadDot = false
        if let bubble = (NSApp.delegate as? AppDelegate)?.bubbles.first(where: { $0.container === self }) {
            bubble.setBadge(count: count)
        }
    }

    func updateUnreadDot() {
        hasUnreadDot = true
        unreadCount = 0
        if let bubble = (NSApp.delegate as? AppDelegate)?.bubbles.first(where: { $0.container === self }) {
            bubble.setBadgeDot()
        }
    }

    func clearUnreadBadge() {
        unreadCount = 0
        hasUnreadDot = false
        if let bubble = (NSApp.delegate as? AppDelegate)?.bubbles.first(where: { $0.container === self }) {
            bubble.clearBadge()
        }
    }

    private func detectUnreadFromTitle() {
        let t = webView.title ?? ""
        if let count = UnreadDetector.parseCountFromTitle(t) {
            updateUnreadCount(count)
        } else if UnreadDetector.hasUnreadIndicator(t) {
            updateUnreadDot()
        } else if unreadCount > 0 || hasUnreadDot {
            clearUnreadBadge()
        }
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        level = enabled ? .floating : .normal
    }

    func setOpacity(_ value: CGFloat) {
        alphaValue = max(0.3, min(1.0, value))
    }

    func setClickThrough(_ enabled: Bool) {
        ignoresMouseEvents = enabled
    }

    func cleanupAndClose() {
        webView.evaluateJavaScript(
            "document.querySelectorAll('video,audio').forEach(function(m){m.pause()})",
            completionHandler: nil
        )
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        close()
    }

    func syncVisibilityPolyfill() {
        let isMedia = webView.url.flatMap { WebViewConfig.isMediaSite(host: $0.host ?? "") } ?? false
        let flag = isMedia ? "true" : "false"
        webView.evaluateJavaScript("window.__fsKeepVisible = \(flag)", completionHandler: nil)
    }

    func setKeepVisible(_ keep: Bool) {
        let flag = keep ? "true" : "false"
        webView.evaluateJavaScript("window.__fsKeepVisible = \(flag)", completionHandler: nil)
    }

    // MARK: - Profile Switching

    func switchProfile(to newProfile: Profile) {
        let currentURL = webView.url
        self.profile = newProfile
        accentBar.layer?.backgroundColor = newProfile.color.cgColor
        toolbarView.setProfile(newProfile)

        webView.removeFromSuperview()
        webViewTopConstraint.isActive = false

        let newWebView = WKWebView(
            frame: .zero,
            configuration: WebViewConfig.makeConfiguration(profile: newProfile)
        )
        newWebView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(newWebView)

        webViewTopConstraint = newWebView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor)
        NSLayoutConstraint.activate([
            webViewTopConstraint,
            newWebView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            newWebView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            newWebView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        self.webView = newWebView
        self.webConfig = WebViewConfig()
        webConfig.attach(to: newWebView, container: self)

        if let url = currentURL {
            newWebView.load(URLRequest(url: url))
        }
    }

    // MARK: - Container Fullscreen

    func syncFullscreenFlag() {
        let flag = fullscreenFillsContainer ? "true" : "false"
        webView.evaluateJavaScript("window.__fsFake = \(flag)", completionHandler: nil)
    }

    func enterContainerFullscreen() {
        guard !isInContainerFullscreen else { return }
        isInContainerFullscreen = true
        toolbarWasVisibleBeforeFullscreen = !toolbarView.isHidden

        toolbarHeightConstraint.constant = 0
        toolbarView.isHidden = true
    }

    func exitContainerFullscreen() {
        guard isInContainerFullscreen else { return }
        isInContainerFullscreen = false

        if toolbarWasVisibleBeforeFullscreen && !isToolbarAutoHidden {
            toolbarView.isHidden = false
            toolbarHeightConstraint.constant = ToolbarView.height
        }
    }

    // MARK: - Page Zoom

    func zoomIn() {
        let steps = WebViewConfig.zoomSteps
        let current = webView.pageZoom
        if let next = steps.first(where: { $0 > current + 0.01 }) {
            setZoom(next)
        }
    }

    func zoomOut() {
        let steps = WebViewConfig.zoomSteps
        let current = webView.pageZoom
        if let prev = steps.last(where: { $0 < current - 0.01 }) {
            setZoom(prev)
        }
    }

    func zoomReset() {
        setZoom(1.0)
    }

    private func setZoom(_ level: CGFloat) {
        webView.pageZoom = level
        if let host = webView.url?.host {
            WebViewConfig.saveZoom(level, for: host, profileId: profile.id)
        }
        toolbarView.showZoomLevel(level)
    }

    func applySavedZoom() {
        guard let host = webView.url?.host else { return }
        if let saved = WebViewConfig.savedZoom(for: host, profileId: profile.id) {
            webView.pageZoom = saved
        } else {
            webView.pageZoom = 1.0
        }
    }

    // MARK: - Mobile Mode

    var isAlwaysDesktopSite: Bool {
        guard let host = webView.url?.host else { return false }
        return WebViewConfig.isAlwaysDesktop(host: host)
    }

    func setMobileMode(_ enabled: Bool) {
        if enabled && isAlwaysDesktopSite { return }
        guard enabled != isMobileMode else { return }
        isMobileMode = enabled
        toolbarView.updateMobileMode(enabled, disabled: isAlwaysDesktopSite)

        WebViewConfig.applyUserAgent(to: webView, mobile: enabled)

        if let url = webView.url {
            let switchedURL = Self.switchDomain(url: url, toMobile: enabled)
            if switchedURL != url {
                webView.load(URLRequest(url: switchedURL))
            } else {
                webView.reload()
            }
        }
    }

    func applySizePreset(width: CGFloat, height: CGFloat, enableMobile: Bool? = nil) {
        let origin = frame.origin
        setFrame(NSRect(x: origin.x, y: origin.y, width: width, height: height), display: true)
        if let mobile = enableMobile {
            setMobileMode(mobile)
        }
    }

    @objc private func windowDidResize(_ notification: Notification) {
        guard isAutoMobile else { return }
        autoMobileDebounceTimer?.invalidate()
        autoMobileDebounceTimer = Timer.scheduledTimer(
            withTimeInterval: 0.5, repeats: false
        ) { [weak self] _ in
            self?.evaluateAutoMobile()
        }
    }

    private func evaluateAutoMobile() {
        guard !isAlwaysDesktopSite else { return }
        let w = frame.width
        if isMobileMode && w > Self.autoMobileOffThreshold {
            setMobileMode(false)
        } else if !isMobileMode && w < Self.autoMobileOnThreshold {
            setMobileMode(true)
        }
    }

    private static func switchDomain(url: URL, toMobile: Bool) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host else { return url }

        if toMobile {
            return url
        }

        for mapping in mobileDomainMap {
            if host == mapping.mobile {
                components.host = mapping.desktop
                return components.url ?? url
            }
        }
        return url
    }

    // MARK: - Toolbar Auto-hide

    func setToolbarAutoHidden(_ hidden: Bool, animated: Bool = true) {
        isToolbarAutoHidden = hidden
        let newHeight: CGFloat = hidden ? 0 : ToolbarView.height
        toolbarView.isHidden = hidden

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                toolbarHeightConstraint.animator().constant = newHeight
            }
        } else {
            toolbarHeightConstraint.constant = newHeight
        }
    }

    func handleMouseNearTop() {
        guard isToolbarAutoHidden else { return }
        toolbarView.isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            toolbarHeightConstraint.animator().constant = ToolbarView.height
        }
    }

    func handleMouseLeftTop() {
        guard isToolbarAutoHidden else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            toolbarHeightConstraint.animator().constant = 0
        }, completionHandler: { [weak self] in
            if self?.isToolbarAutoHidden == true {
                self?.toolbarView.isHidden = true
            }
        })
    }

    // MARK: - State

    func captureState() -> ContainerState {
        let f = savedFrameBeforeMinimize ?? frame
        let bubble = (NSApp.delegate as? AppDelegate)?.bubbles.first { $0.container === self }
        return ContainerState(
            id: containerID,
            urlString: webView.url?.absoluteString ?? "",
            x: Double(f.origin.x),
            y: Double(f.origin.y),
            width: Double(f.width),
            height: Double(f.height),
            opacity: Double(alphaValue),
            isAlwaysOnTop: level == .floating,
            isToolbarAutoHidden: isToolbarAutoHidden,
            fullscreenFillsContainer: fullscreenFillsContainer,
            profileId: profile.id.uuidString,
            isMobileMode: isMobileMode,
            isAutoMobile: isAutoMobile,
            isMinimized: bubble != nil,
            bubbleX: bubble.map { Double($0.frame.origin.x) },
            bubbleY: bubble.map { Double($0.frame.origin.y) },
            bubbleEdge: savedBubbleEdge,
            soundMode: soundMode.rawValue
        )
    }
}

// MARK: - ToolbarViewDelegate

extension ContainerWindow: ToolbarViewDelegate {
    func toolbarDidRequestClose() { cleanupAndClose() }
    func toolbarDidRequestMinimize() {
        (NSApp.delegate as? AppDelegate)?.minimizeToBubble(self)
    }
    func toolbarDidRequestBack() { webView.goBack() }
    func toolbarDidRequestForward() { webView.goForward() }
    func toolbarDidRequestReload() { webView.reload() }

    func toolbarDidNavigate(to urlString: String) {
        WebViewConfig.navigate(webView, to: urlString)
    }

    func toolbarDidTogglePin(_ pinned: Bool) {
        setAlwaysOnTop(pinned)
    }

    func toolbarDidToggleMobileMode() {
        setMobileMode(!isMobileMode)
    }

    func toolbarDidRequestFillVideo() {
        webView.evaluateJavaScript("window.__fsFillVideo && window.__fsFillVideo()", completionHandler: nil)
    }

    func toolbarDidRequestSwitchProfile(relativeTo view: NSView) {
        let menu = NSMenu()
        for p in ProfileManager.shared.profiles {
            let item = NSMenuItem(title: "\(p.emoji) \(p.name)",
                                  action: #selector(profileMenuItemSelected(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = p.id.uuidString
            if p.id == profile.id { item.state = .on }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height), in: view)
    }

    @objc private func profileMenuItemSelected(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let id = UUID(uuidString: idStr) else { return }
        let newProfile = ProfileManager.shared.profile(for: id)
        guard newProfile.id != profile.id else { return }
        switchProfile(to: newProfile)
    }
}

// MARK: - Hover Detection Content View

private class HoverContentView: NSView {
    weak var owner: ContainerWindow?
    private var topTracker: NSTrackingArea?

    init(owner: ContainerWindow) {
        self.owner = owner
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = topTracker { removeTrackingArea(old) }

        let hoverRect = NSRect(x: 0, y: bounds.height - 8, width: bounds.width, height: 8)
        let area = NSTrackingArea(
            rect: hoverRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        topTracker = area
    }

    override func mouseEntered(with event: NSEvent) {
        owner?.handleMouseNearTop()
    }

    override func mouseExited(with event: NSEvent) {
        owner?.handleMouseLeftTop()
    }
}
