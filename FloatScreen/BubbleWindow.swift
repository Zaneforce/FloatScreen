import AppKit

final class BubbleWindow: NSPanel {
    static let bubbleSize: CGFloat = 56
    static let spacing: CGFloat = 8

    weak var container: ContainerWindow?
    fileprivate var faviconImage: NSImage?
    private var dragStart: NSPoint?
    private var windowOriginAtDragStart: NSPoint?
    private var isDragging = false

    init(container: ContainerWindow) {
        self.container = container

        let rect = NSRect(x: 0, y: 0, width: Self.bubbleSize, height: Self.bubbleSize)
        super.init(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let bubbleView = BubbleContentView(owner: self)
        contentView = bubbleView

        contentView?.toolTip = container.pageTitle
        fetchFavicon()
    }

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragStart = NSEvent.mouseLocation
            windowOriginAtDragStart = frame.origin
            isDragging = false
        case .leftMouseDragged:
            guard let start = dragStart, let origin = windowOriginAtDragStart else { break }
            let current = NSEvent.mouseLocation
            let dx = current.x - start.x
            let dy = current.y - start.y
            if !isDragging && (abs(dx) > 3 || abs(dy) > 3) {
                isDragging = true
            }
            if isDragging {
                setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
            }
        case .leftMouseUp:
            if isDragging {
                snapToEdge()
            } else {
                (NSApp.delegate as? AppDelegate)?.restoreFromBubble(self)
            }
            dragStart = nil
            windowOriginAtDragStart = nil
            isDragging = false
        case .rightMouseDown:
            showContextMenu(at: event)
        default:
            break
        }
        super.sendEvent(event)
    }

    func updatePosition(index: Int) {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let x: CGFloat
        if frame.midX > visibleFrame.midX {
            x = visibleFrame.maxX - Self.bubbleSize - Self.spacing
        } else {
            x = visibleFrame.minX + Self.spacing
        }
        let y = visibleFrame.maxY - CGFloat(index + 1) * (Self.bubbleSize + Self.spacing)
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func updateContent() {
        contentView?.toolTip = container?.pageTitle
        (contentView as? BubbleContentView)?.needsDisplay = true
    }

    // MARK: - Favicon

    private func fetchFavicon() {
        guard let webView = container?.webView else { return }
        let js = """
        (function(){
            var link = document.querySelector('link[rel*="icon"]');
            return link ? link.href : (location.origin + '/favicon.ico');
        })()
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let urlStr = result as? String, let url = URL(string: urlStr) else { return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let img = NSImage(data: data), img.isValid else { return }
                DispatchQueue.main.async {
                    self?.faviconImage = img
                    (self?.contentView as? BubbleContentView)?.needsDisplay = true
                }
            }.resume()
        }
    }

    // MARK: - Edge Snapping

    private func snapToEdge() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let center = frame.midX
        let targetX: CGFloat
        if center > visibleFrame.midX {
            targetX = visibleFrame.maxX - Self.bubbleSize - Self.spacing
        } else {
            targetX = visibleFrame.minX + Self.spacing
        }
        let clampedY = max(visibleFrame.minY + Self.spacing,
                           min(frame.origin.y, visibleFrame.maxY - Self.bubbleSize - Self.spacing))
        let target = NSRect(x: targetX, y: clampedY,
                            width: Self.bubbleSize, height: Self.bubbleSize)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(target, display: true)
        }
    }

    // MARK: - Context Menu

    private func showContextMenu(at event: NSEvent) {
        let menu = NSMenu()

        let restoreItem = NSMenuItem(title: "Restore", action: #selector(restoreAction), keyEquivalent: "")
        restoreItem.target = self
        menu.addItem(restoreItem)

        let closeItem = NSMenuItem(title: "Close", action: #selector(closeAction), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)

        menu.addItem(.separator())

        if let profile = container?.profile {
            let profileItem = NSMenuItem(title: "\(profile.emoji) \(profile.name)", action: nil, keyEquivalent: "")
            profileItem.isEnabled = false
            menu.addItem(profileItem)
        }

        NSMenu.popUpContextMenu(menu, with: event, for: contentView!)
    }

    @objc private func restoreAction() {
        (NSApp.delegate as? AppDelegate)?.restoreFromBubble(self)
    }

    @objc private func closeAction() {
        (NSApp.delegate as? AppDelegate)?.closeBubble(self)
    }
}

// MARK: - Bubble Drawing View

private class BubbleContentView: NSView {
    weak var owner: BubbleWindow?

    init(owner: BubbleWindow) {
        self.owner = owner
        super.init(frame: NSRect(x: 0, y: 0, width: BubbleWindow.bubbleSize, height: BubbleWindow.bubbleSize))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let size = BubbleWindow.bubbleSize
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let profileColor = owner?.container?.profile.color ?? .controlAccentColor

        // Ring
        let ringPath = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
        profileColor.setStroke()
        ringPath.lineWidth = 2.5
        ringPath.stroke()

        // Fill circle
        let innerRect = rect.insetBy(dx: 3, dy: 3)
        let fillPath = NSBezierPath(ovalIn: innerRect)

        // Clip to circle
        ctx.saveGState()
        fillPath.addClip()

        profileColor.withAlphaComponent(0.85).setFill()
        fillPath.fill()

        if let favicon = owner?.faviconImage {
            let iconSize: CGFloat = 28
            let iconRect = NSRect(
                x: innerRect.midX - iconSize / 2,
                y: innerRect.midY - iconSize / 2,
                width: iconSize, height: iconSize
            )
            favicon.draw(in: iconRect, from: NSRect.zero, operation: .sourceOver, fraction: 1.0)
        } else {
            let letter = String(owner?.container?.pageTitle.prefix(1) ?? "?")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 20, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let attrStr = NSAttributedString(string: letter, attributes: attrs)
            let strSize = attrStr.size()
            let strPoint = NSPoint(
                x: innerRect.midX - strSize.width / 2,
                y: innerRect.midY - strSize.height / 2
            )
            attrStr.draw(at: strPoint)
        }

        ctx.restoreGState()
    }
}
