import AppKit

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private weak var appDelegate: AppDelegate?
    private let favorites = FavoritesManager()

    private static let favoritesMenuID = NSUserInterfaceItemIdentifier("favorites")

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "macwindow.on.rectangle",
                accessibilityDescription: "FloatScreen"
            )
        }

        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let newItem = NSMenuItem(
            title: "New Container",
            action: #selector(newContainer),
            keyEquivalent: "n"
        )
        newItem.target = self
        menu.addItem(newItem)

        menu.addItem(.separator())

        // Open containers
        if let containers = appDelegate?.containers, !containers.isEmpty {
            for container in containers {
                let title = container.pageTitle
                let item = NSMenuItem(
                    title: title,
                    action: #selector(focusContainer(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = container
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        // Favorites submenu
        let favItem = NSMenuItem(title: "Favorites", action: nil, keyEquivalent: "")
        let favSubmenu = NSMenu()
        favSubmenu.delegate = self
        favSubmenu.identifier = Self.favoritesMenuID
        favItem.submenu = favSubmenu
        menu.addItem(favItem)

        menu.addItem(.separator())

        // Opacity submenu
        let opacityItem = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for pct in stride(from: 100, through: 30, by: -10) {
            let item = NSMenuItem(
                title: "\(pct)%",
                action: #selector(setOpacity(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = pct
            opacityMenu.addItem(item)
        }
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        let clickThroughItem = NSMenuItem(
            title: "Toggle Click-Through",
            action: #selector(toggleClickThrough),
            keyEquivalent: ""
        )
        clickThroughItem.target = self
        menu.addItem(clickThroughItem)

        let showHideItem = NSMenuItem(
            title: "Show/Hide All",
            action: #selector(toggleAllContainers),
            keyEquivalent: ""
        )
        showHideItem.target = self
        menu.addItem(showHideItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit FloatScreen",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate (favorites submenu)

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.identifier == Self.favoritesMenuID else { return }
        menu.removeAllItems()

        for fav in favorites.items {
            let item = NSMenuItem(
                title: fav.name,
                action: #selector(openFavorite(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = fav.urlString
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let addItem = NSMenuItem(
            title: "Add Current Page\u{2026}",
            action: #selector(addCurrentToFavorites),
            keyEquivalent: ""
        )
        addItem.target = self
        menu.addItem(addItem)
    }

    // MARK: - Actions

    @objc private func newContainer() {
        _ = appDelegate?.newContainer()
        rebuildMenu()
    }

    @objc private func focusContainer(_ sender: NSMenuItem) {
        guard let container = sender.representedObject as? ContainerWindow else { return }
        container.makeKeyAndOrderFront(nil)
    }

    @objc private func openFavorite(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else { return }
        _ = appDelegate?.newContainer(url: url)
        rebuildMenu()
    }

    @objc private func addCurrentToFavorites() {
        guard let container = appDelegate?.containers.last,
              let url = container.currentURL else { return }
        let name = container.pageTitle
        favorites.add(name: name, urlString: url.absoluteString)
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        let value = CGFloat(sender.tag) / 100.0
        // Apply to the frontmost container
        if let container = NSApp.keyWindow as? ContainerWindow {
            container.setOpacity(value)
        } else {
            appDelegate?.containers.last?.setOpacity(value)
        }
    }

    @objc private func toggleClickThrough() {
        guard let containers = appDelegate?.containers else { return }
        let anyClickThrough = containers.contains { $0.ignoresMouseEvents }
        for c in containers {
            c.setClickThrough(!anyClickThrough)
        }
    }

    @objc private func toggleAllContainers() {
        appDelegate?.toggleAllContainers()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
