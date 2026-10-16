import AppKit

final class BubbleWindow: NSPanel {
    static let circleSize: CGFloat = 52
    static let badgeOverhang: CGFloat = 12
    static let windowSize: CGFloat = 76
    static let visualCenter: CGFloat = (windowSize - badgeOverhang) / 2
    static let spacing: CGFloat = 8

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
            // Sound is handled by NotificationForwarder for web notifications.
            // For title-based badge increases (no web notification), play here
            // only if floatScreenSound mode AND no native notification was just posted.
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
                saveBubblePosition()
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
            let x = vis.maxX - Self.windowSize - Self.spacing
            let y = vis.maxY - Self.windowSize - Self.spacing
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        avoidCollisions()
    }

    func avoidCollisions() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let others = appDelegate.bubbles.filter { $0 !== self && $0.isVisible }
        var myFrame = frame

        for other in others {
            var attempts = 0
            while myFrame.intersects(other.frame) && attempts < 10 {
                myFrame.origin.y -= (Self.circleSize + Self.spacing)
                attempts += 1
            }
        }

        if let vis = NSScreen.main?.visibleFrame {
            myFrame.origin.x = max(vis.minX, min(myFrame.origin.x, vis.maxX - Self.windowSize))
            myFrame.origin.y = max(vis.minY, min(myFrame.origin.y, vis.maxY - Self.windowSize))
        }

        setFrameOrigin(myFrame.origin)
    }

    private func saveBubblePosition() {
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

    private func fetchFavicon() {
        guard !faviconLocked, let webView = container?.webView else { return }
        let js = """
        (function(){
            var link = document.querySelector('link[rel*="icon"]');
            return link ? link.href : (location.origin + '/favicon.ico');
        })()
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self, !self.faviconLocked else { return }
            guard let urlStr = result as? String, let url = URL(string: urlStr) else { return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let img = NSImage(data: data), img.isValid else { return }
                DispatchQueue.main.async {
                    guard !self.faviconLocked else { return }
                    self.faviconImage = img
                    self.faviconLocked = true
                    (self.contentView as? BubbleContentView)?.needsDisplay = true
                }
            }.resume()
        }
    }

    // MARK: - Edge Snapping

    private func snapToEdge() {
        guard let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame
        let targetX: CGFloat
        if frame.midX > vis.midX {
            targetX = vis.maxX - Self.windowSize - Self.spacing
        } else {
            targetX = vis.minX + Self.spacing
        }
        let clampedY = max(vis.minY + Self.spacing,
                           min(frame.origin.y, vis.maxY - Self.windowSize - Self.spacing))
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
        guard let owner else { return }
        let cs = BubbleWindow.circleSize

        let profileColor = owner.container?.profile.color ?? .controlAccentColor

        // Circle is positioned at bottom-left with room for badge overflow at top-right
        let circleOrigin = NSPoint(x: 0, y: 0)
        let ringRect = NSRect(x: circleOrigin.x, y: circleOrigin.y, width: cs, height: cs)
        let ringPath = NSBezierPath(ovalIn: ringRect.insetBy(dx: 0.5, dy: 0.5))
        profileColor.setStroke()
        ringPath.lineWidth = 2.5
        ringPath.stroke()

        let innerRect = ringRect.insetBy(dx: 3, dy: 3)
        let innerPath = NSBezierPath(ovalIn: innerRect)

        NSGraphicsContext.current?.cgContext.saveGState()
        innerPath.addClip()

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (isDark ? NSColor(white: 0.18, alpha: 1) : NSColor.white).setFill()
        innerPath.fill()

        if let favicon = owner.faviconImage {
            let iconSize: CGFloat = cs * 0.52
            let iconRect = NSRect(
                x: innerRect.midX - iconSize / 2,
                y: innerRect.midY - iconSize / 2,
                width: iconSize, height: iconSize
            )
            favicon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        } else {
            let letter = String(owner.container?.pageTitle.prefix(1) ?? "?")
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: cs * 0.35, weight: .bold),
                .foregroundColor: isDark ? NSColor.white : profileColor,
            ]
            let attrStr = NSAttributedString(string: letter, attributes: attrs)
            let strSize = attrStr.size()
            attrStr.draw(at: NSPoint(
                x: innerRect.midX - strSize.width / 2,
                y: innerRect.midY - strSize.height / 2
            ))
        }

        NSGraphicsContext.current?.cgContext.restoreGState()

        // Badge centered on circle's top-right edge
        if owner.badgeCount > 0 || owner.badgeDot {
            let badgeCenter = NSPoint(
                x: ringRect.maxX - 4,
                y: ringRect.maxY - 4
            )
            drawBadge(at: badgeCenter, isDark: isDark)
        }
    }

    private func drawBadge(at center: NSPoint, isDark: Bool) {
        guard let owner else { return }
        let red = NSColor(red: 1, green: 0.231, blue: 0.188, alpha: 1)
        let outlineBg: NSColor = isDark ? NSColor(white: 0.1, alpha: 1) : .white

        if owner.badgeDot {
            let dotSize: CGFloat = 12
            let dotRect = NSRect(x: center.x - dotSize / 2, y: center.y - dotSize / 2,
                                 width: dotSize, height: dotSize)
            // Shadow
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
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.size()

        let padH: CGFloat = 5
        let badgeH: CGFloat = 22
        let badgeW = max(badgeH, textSize.width + padH * 2)

        let badgeRect = NSRect(
            x: center.x - badgeW / 2,
            y: center.y - badgeH / 2,
            width: badgeW, height: badgeH
        )

        // Shadow
        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()

        // Outline
        let outlineRect = badgeRect.insetBy(dx: -2, dy: -2)
        outlineBg.setFill()
        NSBezierPath(roundedRect: outlineRect, xRadius: outlineRect.height / 2,
                     yRadius: outlineRect.height / 2).fill()

        // Clear shadow for the red fill
        NSShadow().set()

        red.setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: badgeH / 2,
                     yRadius: badgeH / 2).fill()

        attrStr.draw(at: NSPoint(
            x: badgeRect.midX - textSize.width / 2,
            y: badgeRect.midY - textSize.height / 2
        ))
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
