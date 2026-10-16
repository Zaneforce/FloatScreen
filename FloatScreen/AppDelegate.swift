import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var containers: [ContainerWindow] = []
    var bubbles: [BubbleWindow] = []
    var recentlyClosed: [ContainerState] = []
    private var menuBarController: MenuBarController?
    private var globalShortcut: GlobalShortcut?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(appDelegate: self)

        setupHiddenMenu()
        globalShortcut = GlobalShortcut { [weak self] in self?.toggleAllContainers() }
        ContentBlocker.shared.loadRulesIfNeeded()

        recentlyClosed = StatePersistence.loadRecentlyClosed()

        let savedStates = StatePersistence.load()
        if savedStates.isEmpty {
            let container = ContainerWindow(url: URL(string: "https://www.google.com"))
            containers.append(container)
            container.orderFront(nil)
        } else {
            for state in savedStates {
                let url = URL(string: state.urlString)
                let profileId = state.profileId.flatMap(UUID.init(uuidString:))
                let profile = profileId.map { ProfileManager.shared.profile(for: $0) }
                let container = ContainerWindow(id: state.id, url: url, state: state, profile: profile)
                containers.append(container)

                if state.isMinimized == true {
                    container.savedFrameBeforeMinimize = container.frame
                    let bubble = BubbleWindow(container: container)
                    if let bx = state.bubbleX, let by = state.bubbleY {
                        bubble.setFrameOrigin(NSPoint(x: bx, y: by))
                    }
                    bubbles.append(bubble)
                    bubble.orderFront(nil)
                } else {
                    container.orderFront(nil)
                }
            }
            restackBubbles()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        let states = containers.map { $0.captureState() }
        StatePersistence.save(states)
        StatePersistence.saveRecentlyClosed(recentlyClosed)
    }

    @discardableResult
    func newContainer(url: URL? = nil, profile: Profile? = nil) -> ContainerWindow {
        let container = ContainerWindow(url: url, profile: profile)
        containers.append(container)
        container.orderFront(nil)
        menuBarController?.rebuildMenu()
        return container
    }

    // MARK: - Toggle All

    func toggleAllContainers() {
        let anyContainerVisible = containers.contains { $0.isVisible }
        let anyBubbleVisible = bubbles.contains { $0.isVisible }
        let anyVisible = anyContainerVisible || anyBubbleVisible

        if anyVisible {
            for c in containers { c.orderOut(nil) }
            for b in bubbles { b.orderOut(nil) }
        } else {
            for b in bubbles { b.orderFront(nil) }
            let nonMinimized = containers.filter { c in
                !bubbles.contains { $0.container === c }
            }
            for c in nonMinimized { c.orderFront(nil) }
            NSApp.activate(ignoringOtherApps: true)
            nonMinimized.last?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Bubble Management

    func minimizeToBubble(_ container: ContainerWindow) {
        container.savedFrameBeforeMinimize = container.frame
        container.orderOut(nil)

        let bubble = BubbleWindow(container: container)
        if container.unreadCount > 0 {
            bubble.setBadge(count: container.unreadCount)
        } else if container.hasUnreadDot {
            bubble.setBadgeDot()
        }
        bubbles.append(bubble)
        restackBubbles()
        bubble.orderFront(nil)
        menuBarController?.rebuildMenu()
    }

    func restoreFromBubble(_ bubble: BubbleWindow) {
        guard let container = bubble.container else { return }

        bubbles.removeAll { $0 === bubble }
        bubble.orderOut(nil)

        let targetFrame = container.savedFrameBeforeMinimize ?? container.frame
        container.savedFrameBeforeMinimize = nil

        container.setFrame(bubble.frame, display: false)
        container.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            container.animator().setFrame(targetFrame, display: true)
        }

        NSApp.activate(ignoringOtherApps: true)
        container.makeKeyAndOrderFront(nil)

        restackBubbles()
        menuBarController?.rebuildMenu()
    }

    func closeBubble(_ bubble: BubbleWindow) {
        guard let container = bubble.container else { return }

        let state = container.captureState()
        addToRecentlyClosed(state)

        bubbles.removeAll { $0 === bubble }
        containers.removeAll { $0 === container }
        bubble.orderOut(nil)
        container.close()

        restackBubbles()
        menuBarController?.rebuildMenu()
    }

    private func restackBubbles() {
        for (index, bubble) in bubbles.enumerated() {
            bubble.updatePosition(index: index)
        }
    }

    // MARK: - Recently Closed

    private func addToRecentlyClosed(_ state: ContainerState) {
        var modified = state
        modified.isMinimized = nil
        modified.bubbleX = nil
        modified.bubbleY = nil
        recentlyClosed.append(modified)
        if recentlyClosed.count > 10 {
            recentlyClosed.removeFirst(recentlyClosed.count - 10)
        }
    }

    func reopenLastClosed() {
        guard let state = recentlyClosed.popLast() else { return }
        reopenContainer(from: state)
    }

    func reopenContainer(from state: ContainerState) {
        let url = URL(string: state.urlString)
        let profileId = state.profileId.flatMap(UUID.init(uuidString:))
        let profile = profileId.map { ProfileManager.shared.profile(for: $0) }
        let container = ContainerWindow(url: url, state: state, profile: profile)
        containers.append(container)
        container.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        container.makeKeyAndOrderFront(nil)
        menuBarController?.rebuildMenu()
    }

    // MARK: - Window Close

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? ContainerWindow else { return }
        let isMinimized = bubbles.contains { $0.container === window }
        if !isMinimized {
            let state = window.captureState()
            addToRecentlyClosed(state)
        }
        containers.removeAll { $0 === window }
        menuBarController?.rebuildMenu()
    }

    // MARK: - Hidden Menu for Keyboard Shortcuts

    private func setupHiddenMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit FloatScreen",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "New Container",
                                    action: #selector(handleNewContainer),
                                    keyEquivalent: "n"))
        fileMenu.addItem(NSMenuItem(title: "Close Container",
                                    action: #selector(handleCloseContainer),
                                    keyEquivalent: "w"))
        let reopenItem = NSMenuItem(title: "Reopen Closed",
                                    action: #selector(handleReopenClosed),
                                    keyEquivalent: "t")
        reopenItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(reopenItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let navMenuItem = NSMenuItem()
        let navMenu = NSMenu(title: "Navigation")
        navMenu.addItem(NSMenuItem(title: "Focus URL Field",
                                   action: #selector(handleFocusURL),
                                   keyEquivalent: "l"))
        navMenu.addItem(NSMenuItem(title: "Reload",
                                   action: #selector(handleReload),
                                   keyEquivalent: "r"))

        let backItem = NSMenuItem(title: "Back",
                                  action: #selector(handleBack),
                                  keyEquivalent: "[")
        navMenu.addItem(backItem)

        let forwardItem = NSMenuItem(title: "Forward",
                                     action: #selector(handleForward),
                                     keyEquivalent: "]")
        navMenu.addItem(forwardItem)

        navMenuItem.submenu = navMenu
        mainMenu.addItem(navMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private var activeContainer: ContainerWindow? {
        NSApp.keyWindow as? ContainerWindow
            ?? containers.last(where: { $0.isVisible })
    }

    @objc private func handleNewContainer() {
        newContainer(profile: ProfileManager.shared.defaultProfile)
    }

    @objc private func handleCloseContainer() {
        activeContainer?.close()
    }

    @objc private func handleReopenClosed() {
        reopenLastClosed()
        menuBarController?.rebuildMenu()
    }

    @objc private func handleFocusURL() {
        if let c = activeContainer {
            c.makeKeyAndOrderFront(nil)
            c.toolbarView.focusURLField()
        }
    }

    @objc private func handleReload() {
        activeContainer?.webView.reload()
    }

    @objc private func handleBack() {
        activeContainer?.webView.goBack()
    }

    @objc private func handleForward() {
        activeContainer?.webView.goForward()
    }
}

final class Box<T> {
    let value: T
    init(_ value: T) { self.value = value }
}
