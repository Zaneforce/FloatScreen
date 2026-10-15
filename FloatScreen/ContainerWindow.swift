import AppKit
import WebKit

final class ContainerWindow: NSPanel {
    let webView: WKWebView
    let toolbarView: ToolbarView
    let webConfig: WebViewConfig
    let containerID: UUID

    private var toolbarHeightConstraint: NSLayoutConstraint!
    private var isToolbarAutoHidden = false
    private var hoverTrackingArea: NSTrackingArea?

    var fullscreenFillsContainer = true
    private var isInContainerFullscreen = false
    private var toolbarWasVisibleBeforeFullscreen = true

    init(id: UUID = UUID(), url: URL? = nil, state: ContainerState? = nil) {
        self.containerID = id
        self.webConfig = WebViewConfig()
        self.toolbarView = ToolbarView()
        self.webView = WKWebView(frame: .zero, configuration: WebViewConfig.makeConfiguration())

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

        // Without this, .nonactivatingPanel only becomes key when a key-view
        // (like NSTextField) is clicked. WKWebView text inputs need the panel
        // to be key for typing to work, so always accept key status on click.
        becomesKeyOnlyIfNeeded = false

        let container = HoverContentView(owner: self)
        container.wantsLayer = true
        self.contentView = container

        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbarView)

        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)

        toolbarHeightConstraint = toolbarView.heightAnchor.constraint(
            equalToConstant: ToolbarView.height
        )

        NSLayoutConstraint.activate([
            toolbarView.topAnchor.constraint(equalTo: container.topAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbarHeightConstraint,

            webView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        toolbarView.delegate = self
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
            fullscreenFillsContainer: fullscreenFillsContainer
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
