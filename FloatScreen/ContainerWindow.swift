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

    private var webViewTopConstraint: NSLayoutConstraint!
    private var containerView: NSView!

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
                        .fullSizeContentView, .nonactivatingPanel],
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
        }

        if let url {
            webView.load(URLRequest(url: url))
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var currentURL: URL? { webView.url }
    var pageTitle: String { webView.title ?? webView.url?.host ?? "New Tab" }

    func webViewDidUpdate() {
        toolbarView.updateURL(webView.url?.absoluteString ?? "")
        toolbarView.updateNavigation(canGoBack: webView.canGoBack, canGoForward: webView.canGoForward)
        title = pageTitle
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
        let f = frame
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
            profileId: profile.id.uuidString
        )
    }
}

// MARK: - ToolbarViewDelegate

extension ContainerWindow: ToolbarViewDelegate {
    func toolbarDidRequestClose() { close() }
    func toolbarDidRequestBack() { webView.goBack() }
    func toolbarDidRequestForward() { webView.goForward() }
    func toolbarDidRequestReload() { webView.reload() }

    func toolbarDidNavigate(to urlString: String) {
        WebViewConfig.navigate(webView, to: urlString)
    }

    func toolbarDidTogglePin(_ pinned: Bool) {
        setAlwaysOnTop(pinned)
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
