import AppKit

final class BubbleWindow: NSPanel {
    static let circleSize: CGFloat = 56
    static let ringWidth: CGFloat = 3
    static let padding: CGFloat = 4
    static let badgeOverhang: CGFloat = 14
    static let windowSize: CGFloat = circleSize + padding * 2 + badgeOverhang
    static let circleGap: CGFloat = 12
    static let topInset: CGFloat = 140

    weak var container: ContainerWindow?
    fileprivate var faviconImage: NSImage?
    fileprivate var faviconLocked = false
    fileprivate var badgeCount: Int = 0
    fileprivate var badgeDot: Bool = false
    private var dragStart: NSPoint?
    private var windowOriginAtDragStart: NSPoint?
    private var isDragging = false

    init(container: ContainerWindow) {
        self.container = container

        let rect = NSRect(x: 0, y: 0, width: Self.windowSize, height: Self.windowSize)
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

    // MARK: - Badge

    func setBadge(count: Int) {
        let increased = count > badgeCount && count > 0
        badgeCount = count
        badgeDot = false
        (contentView as? BubbleContentView)?.needsDisplay = true
        if increased {
            popAnimation()
            pulseAnimation()
            if container?.soundMode == .floatScreenSound {
                NotificationSound.shared.playUnlessRecentlyPosted()
            }
        }
    }

    func setBadgeDot() {
        guard !badgeDot else { return }
        badgeDot = true
        badgeCount = 0
        (contentView as? BubbleContentView)?.needsDisplay = true
        popAnimation()
        pulseAnimation()
    }

    func clearBadge() {
        guard badgeCount > 0 || badgeDot else { return }
        badgeCount = 0
        badgeDot = false
        (contentView as? BubbleContentView)?.needsDisplay = true
    }

    private func popAnimation() {
        let orig = frame
        let expanded = orig.insetBy(dx: -4, dy: -4)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(expanded, display: true)
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(orig, display: true)
            }
        })
    }

    private func pulseAnimation() {
        guard let view = contentView else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            view.animator().alphaValue = 0.7
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                view.animator().alphaValue = 1.0
            }
        })
    }

    // MARK: - Mouse Handling

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
            if !isDragging && (abs(dx) > 3 || abs(dy) > 3) { isDragging = true }
            if isDragging {
                setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
            }
        case .leftMouseUp:
            if isDragging {
                snapToEdge()
                savePosition()
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

    // MARK: - Positioning

    func placeAtSavedOrDefault() {
        guard let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame

        if let saved = container?.savedBubbleOrigin {
            var origin = saved
            origin.x = max(vis.minX, min(origin.x, vis.maxX - Self.windowSize))
            origin.y = max(vis.minY, min(origin.y, vis.maxY - Self.windowSize))
            setFrameOrigin(origin)
        } else {
            let x = vis.maxX - Self.windowSize - 8
            let y = vis.maxY - Self.topInset - Self.windowSize
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        avoidCollisions()
        savePosition()
    }

    func avoidCollisions() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let others = appDelegate.bubbles.filter { $0 !== self && $0.isVisible }
        var myFrame = frame

        for other in others {
            var attempts = 0
            while myFrame.intersects(other.frame) && attempts < 15 {
                myFrame.origin.y -= (Self.circleSize + Self.circleGap)
                attempts += 1
            }
        }

        if let vis = NSScreen.main?.visibleFrame {
            myFrame.origin.x = max(vis.minX, min(myFrame.origin.x, vis.maxX - Self.windowSize))
            myFrame.origin.y = max(vis.minY, min(myFrame.origin.y, vis.maxY - Self.windowSize))
        }

        setFrameOrigin(myFrame.origin)
    }

    func savePosition() {
        container?.savedBubbleOrigin = frame.origin
        guard let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame
        container?.savedBubbleEdge = frame.midX > vis.midX ? "right" : "left"
    }

    func updateContent() {
        contentView?.toolTip = container?.pageTitle
        (contentView as? BubbleContentView)?.needsDisplay = true
    }

    // MARK: - Favicon

    private var faviconHost: String?

    private func fetchFavicon() {
        guard let webView = container?.webView else { return }
        let currentHost = webView.url?.host

        if let fh = faviconHost, fh != currentHost {
            faviconLocked = false
            faviconImage = nil
        }
        guard !faviconLocked else { return }
        faviconHost = currentHost

        let js = """
        (function(){
            var touch = document.querySelector('link[rel="apple-touch-icon"], link[rel="apple-touch-icon-precomposed"]');
            if (touch) return touch.href;
            var manifest = document.querySelector('link[rel="icon"][sizes]');
            if (manifest) return manifest.href;
            var icon = document.querySelector('link[rel*="icon"]');
            if (icon) return icon.href;
            return location.origin + '/apple-touch-icon.png';
        })()
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self, !self.faviconLocked else { return }
            guard let urlStr = result as? String, let url = URL(string: urlStr) else { return }
            self.downloadFavicon(from: url, fallbackHost: currentHost)
        }
    }

    private func downloadFavicon(from url: URL, fallbackHost: String?) {
        URLSession.shared.dataTask(with: url) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let data, ok >= 200, ok < 400, let img = NSImage(data: data), img.isValid {
                DispatchQueue.main.async {
                    guard let self, !self.faviconLocked else { return }
                    self.faviconImage = img
                    self.faviconLocked = true
                    (self.contentView as? BubbleContentView)?.needsDisplay = true
                }
            } else if let host = fallbackHost {
                let fallback = URL(string: "https://\(host)/favicon.ico")
                guard let fallback, fallback != url else { return }
                URLSession.shared.dataTask(with: fallback) { data, _, _ in
                    guard let data, let img = NSImage(data: data), img.isValid else { return }
                    DispatchQueue.main.async {
                        guard let self, !self.faviconLocked else { return }
                        self.faviconImage = img
                        self.faviconLocked = true
                        (self.contentView as? BubbleContentView)?.needsDisplay = true
                    }
                }.resume()
            }
        }.resume()
    }

    // MARK: - Edge Snapping

    private func snapToEdge() {
        guard let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame
        let targetX: CGFloat
        if frame.midX > vis.midX {
            targetX = vis.maxX - Self.windowSize - 8
        } else {
            targetX = vis.minX + 8
        }
        let clampedY = max(vis.minY + 8,
                           min(frame.origin.y, vis.maxY - Self.windowSize - 8))
        let target = NSRect(x: targetX, y: clampedY,
                            width: Self.windowSize, height: Self.windowSize)
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

        let soundItem = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
        let soundMenu = NSMenu()
        for mode in ContainerWindow.SoundMode.allCases {
            let item = NSMenuItem(title: mode.label, action: #selector(setSoundMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = container?.soundMode == mode ? .on : .off
            soundMenu.addItem(item)
        }
        soundItem.submenu = soundMenu
        menu.addItem(soundItem)

        menu.addItem(.separator())
        if let profile = container?.profile {
            let p = NSMenuItem(title: "\(profile.emoji) \(profile.name)", action: nil, keyEquivalent: "")
            p.isEnabled = false
            menu.addItem(p)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: contentView!)
    }

    @objc private func restoreAction() {
        (NSApp.delegate as? AppDelegate)?.restoreFromBubble(self)
    }
    @objc private func closeAction() {
        (NSApp.delegate as? AppDelegate)?.closeBubble(self)
    }
    @objc private func setSoundMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ContainerWindow.SoundMode(rawValue: raw) else { return }
        container?.soundMode = mode
    }
}

// MARK: - Bubble Drawing

private class BubbleContentView: NSView {
    weak var owner: BubbleWindow?

    init(owner: BubbleWindow) {
        self.owner = owner
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: BubbleWindow.windowSize,
                                 height: BubbleWindow.windowSize))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let owner, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let cs = BubbleWindow.circleSize
        let rw = BubbleWindow.ringWidth
        let pad = BubbleWindow.padding
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let profileColor = owner.container?.profile.color ?? .controlAccentColor

        // Backing scale for pixel alignment
        let scale = window?.backingScaleFactor ?? 2.0
        func align(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }

        // Perfectly square circle rect, padded from edges so shadow isn't clipped
        let origin = align(pad)
        let circleRect = NSRect(x: origin, y: origin, width: cs, height: cs)
        let center = NSPoint(x: circleRect.midX, y: circleRect.midY)

        ctx.setShouldAntialias(true)

        // Drop shadow on background fill
        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()

        // Background fill for shadow (filled circle behind everything)
        let bgColor: NSColor = isDark
            ? NSColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1)
            : .white
        bgColor.setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        NSShadow().set()

        // Inner background (same color, drawn inside the ring area)
        let innerRect = circleRect.insetBy(dx: rw, dy: rw)
        let innerPath = NSBezierPath(ovalIn: innerRect)
        bgColor.setFill()
        innerPath.fill()

        // Ring: stroke a circle inset by half the line width for even thickness
        let ringInset = rw / 2
        let ringRect = circleRect.insetBy(dx: ringInset, dy: ringInset)
        let ringPath = NSBezierPath(ovalIn: ringRect)
        ringPath.lineWidth = rw
        profileColor.setStroke()
        ringPath.stroke()

        // Favicon clipped to inner circle
        ctx.saveGState()
        innerPath.addClip()

        let iconDiameter = innerRect.width * 0.55
        if let favicon = owner.faviconImage {
            let aspect = favicon.size.width / max(favicon.size.height, 1)
            var drawW = iconDiameter
            var drawH = iconDiameter
            if aspect > 1 { drawH = drawW / aspect }
            else { drawW = drawH * aspect }
            let iconRect = NSRect(
                x: align(center.x - drawW / 2),
                y: align(center.y - drawH / 2),
                width: align(drawW), height: align(drawH)
            )
            ctx.interpolationQuality = .high
            favicon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        } else {
            let letter = String(owner.container?.pageTitle.prefix(1) ?? "?")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: iconDiameter * 0.7, weight: .bold),
                .foregroundColor: isDark ? NSColor.white : profileColor,
            ]
            let attrStr = NSAttributedString(string: letter, attributes: attrs)
            let strSize = attrStr.size()
            attrStr.draw(at: NSPoint(
                x: align(center.x - strSize.width / 2),
                y: align(center.y - strSize.height / 2)
            ))
        }

        ctx.restoreGState()

        // Badge at top-right of circle
        if owner.badgeCount > 0 || owner.badgeDot {
            let badgeCenter = NSPoint(
                x: circleRect.maxX - cs * 0.08,
                y: circleRect.maxY - cs * 0.08
            )
            drawBadge(at: badgeCenter, isDark: isDark)
        }
    }

    private func drawBadge(at center: NSPoint, isDark: Bool) {
        guard let owner else { return }
        let red = NSColor(red: 1, green: 0.231, blue: 0.188, alpha: 1)
        let outlineBg: NSColor = isDark
            ? NSColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1) : .white

        if owner.badgeDot {
            let dotSize: CGFloat = 12
            let dotRect = NSRect(x: center.x - dotSize / 2, y: center.y - dotSize / 2,
                                 width: dotSize, height: dotSize)
            let shadow = NSShadow()
            shadow.shadowColor = .black.withAlphaComponent(0.3)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            outlineBg.setFill()
            NSBezierPath(ovalIn: dotRect.insetBy(dx: -2, dy: -2)).fill()
            NSShadow().set()
            red.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return
        }

        let text = owner.badgeCount > 99 ? "99+" : "\(owner.badgeCount)"
        let font = NSFont.systemFont(ofSize: 13, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.size()

        let badgeH: CGFloat = 22
        let badgeW = max(badgeH, textSize.width + 10)
        let badgeRect = NSRect(x: center.x - badgeW / 2, y: center.y - badgeH / 2,
                               width: badgeW, height: badgeH)

        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()

        let outlineRect = badgeRect.insetBy(dx: -2, dy: -2)
        outlineBg.setFill()
        NSBezierPath(roundedRect: outlineRect, xRadius: outlineRect.height / 2,
                     yRadius: outlineRect.height / 2).fill()
        NSShadow().set()

        red.setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: badgeH / 2, yRadius: badgeH / 2).fill()
        attrStr.draw(at: NSPoint(x: badgeRect.midX - textSize.width / 2,
                                 y: badgeRect.midY - textSize.height / 2))
    }
}

// MARK: - Notification Sound

final class NotificationSound {
    static let shared = NotificationSound()
    private var lastSoundTime: Date = .distantPast
    private let cooldown: TimeInterval = 3.0

    static let availableSounds = ["Glass", "Ping", "Pop", "Purr", "Sosumi", "Tink"]
    private static let selectedSoundKey = "notificationSound"

    var selectedSoundName: String {
        get { UserDefaults.standard.string(forKey: Self.selectedSoundKey) ?? "Glass" }
        set { UserDefaults.standard.set(newValue, forKey: Self.selectedSoundKey) }
    }

    func markNativeNotificationPosted() {
        lastSoundTime = Date()
    }

    func playUnlessRecentlyPosted() {
        let now = Date()
        guard now.timeIntervalSince(lastSoundTime) > cooldown else { return }
        lastSoundTime = now
        if let sound = NSSound(named: NSSound.Name(selectedSoundName)) {
            sound.play()
        }
    }

    func playIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastSoundTime) > cooldown else { return }
        lastSoundTime = now
        if let sound = NSSound(named: NSSound.Name(selectedSoundName)) {
            sound.play()
        }
    }
}
