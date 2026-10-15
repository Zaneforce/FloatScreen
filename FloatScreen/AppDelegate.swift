import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var containers: [ContainerWindow] = []
    private var menuBarController: MenuBarController?
    private var globalShortcut: GlobalShortcut?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(appDelegate: self)

        setupHiddenMenu()
        globalShortcut = GlobalShortcut { [weak self] in self?.toggleAllContainers() }

        let savedStates = StatePersistence.load()
        if savedStates.isEmpty {
            let container = ContainerWindow(url: URL(string: "https://www.google.com"))
            containers.append(container)
            container.orderFront(nil)
        } else {
            for state in savedStates {
                let url = URL(string: state.urlString)
                let container = ContainerWindow(id: state.id, url: url, state: state)
                containers.append(container)
                container.orderFront(nil)
            }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidClose(_:)),
            name: NSWindow.willCloseNotification, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        let states = containers.map { $0.captureState() }
        StatePersistence.save(states)
    }

    @discardableResult
    func newContainer(url: URL? = nil) -> ContainerWindow {
        let container = ContainerWindow(url: url)
        containers.append(container)
        container.orderFront(nil)
        menuBarController?.rebuildMenu()
        return container
    }

    func toggleAllContainers() {
        let anyVisible = containers.contains { $0.isVisible }
        for c in containers {
            if anyVisible { c.orderOut(nil) } else { c.orderFront(nil) }
        }
    }

    @objc private func windowDidClose(_ notification: Notification) {
        guard let window = notification.object as? ContainerWindow else { return }
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
        newContainer()
    }

    @objc private func handleCloseContainer() {
        activeContainer?.close()
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
