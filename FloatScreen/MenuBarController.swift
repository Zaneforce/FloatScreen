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

        // New Container submenu per profile
        let newItem = NSMenuItem(title: "New Container", action: nil, keyEquivalent: "")
        let newSubmenu = NSMenu()
        for p in ProfileManager.shared.profiles {
            let item = NSMenuItem(
                title: "\(p.emoji) \(p.name)",
                action: #selector(newContainerWithProfile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = p.id.uuidString
            newSubmenu.addItem(item)
        }
        newItem.submenu = newSubmenu
        menu.addItem(newItem)

        menu.addItem(.separator())

        // Open containers (grouped by profile)
        if let containers = appDelegate?.containers, !containers.isEmpty {
            for container in containers {
                let badge = container.profile.emoji
                let title = "\(badge) \(container.pageTitle)"
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

        // Profiles management submenu
        let profilesItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        let profilesSubmenu = NSMenu()
        for p in ProfileManager.shared.profiles {
            let item = NSMenuItem(title: "\(p.emoji) \(p.name)", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let renameItem = NSMenuItem(title: "Rename\u{2026}", action: #selector(renameProfile(_:)), keyEquivalent: "")
            renameItem.target = self
            renameItem.representedObject = p.id.uuidString
            sub.addItem(renameItem)

            let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteProfile(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = p.id.uuidString
            sub.addItem(deleteItem)

            item.submenu = sub
            profilesSubmenu.addItem(item)
        }
        profilesSubmenu.addItem(.separator())
        let addProfileItem = NSMenuItem(title: "Add Profile\u{2026}", action: #selector(addProfile), keyEquivalent: "")
        addProfileItem.target = self
        profilesSubmenu.addItem(addProfileItem)
        profilesItem.submenu = profilesSubmenu
        menu.addItem(profilesItem)

        // Favorites submenu
        let favItem = NSMenuItem(title: "Favorites", action: nil, keyEquivalent: "")
        let favSubmenu = NSMenu()
        favSubmenu.delegate = self
        favSubmenu.identifier = Self.favoritesMenuID
        favItem.submenu = favSubmenu
        menu.addItem(favItem)

        menu.addItem(.separator())

        // Ad blocking
        let adBlockItem = NSMenuItem(
            title: "Block Ads",
            action: #selector(toggleAdBlock(_:)),
            keyEquivalent: ""
        )
        adBlockItem.target = self
        adBlockItem.state = ContentBlocker.shared.isEnabled ? .on : .off
        menu.addItem(adBlockItem)

        let disableOnSiteItem = NSMenuItem(
            title: "Disable Blocking on This Site",
            action: #selector(disableBlockingOnSite),
            keyEquivalent: ""
        )
        disableOnSiteItem.target = self
        if let host = activeContainer?.currentURL?.host {
            disableOnSiteItem.title = ContentBlocker.shared.disabledDomains.contains(host)
                ? "Re-enable Blocking on \(host)"
                : "Disable Blocking on \(host)"
        }
        menu.addItem(disableOnSiteItem)

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

        let fsItem = NSMenuItem(
            title: "Fullscreen Fills Container",
            action: #selector(toggleFullscreenFills(_:)),
            keyEquivalent: ""
        )
        fsItem.target = self
        if let active = activeContainer {
            fsItem.state = active.fullscreenFillsContainer ? .on : .off
        }
        menu.addItem(fsItem)

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

    private var activeContainer: ContainerWindow? {
        NSApp.keyWindow as? ContainerWindow
            ?? appDelegate?.containers.last(where: { $0.isVisible })
    }

    // MARK: - Actions

    @objc private func newContainerWithProfile(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let id = UUID(uuidString: idStr) else { return }
        let profile = ProfileManager.shared.profile(for: id)
        _ = appDelegate?.newContainer(profile: profile)
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

    @objc private func toggleAdBlock(_ sender: NSMenuItem) {
        ContentBlocker.shared.isEnabled.toggle()
        rebuildMenu()
    }

    @objc private func disableBlockingOnSite() {
        guard let host = activeContainer?.currentURL?.host else { return }
        var domains = ContentBlocker.shared.disabledDomains
        if domains.contains(host) {
            domains.remove(host)
        } else {
            domains.insert(host)
        }
        ContentBlocker.shared.disabledDomains = domains
        rebuildMenu()
    }

    @objc private func toggleFullscreenFills(_ sender: NSMenuItem) {
        guard let container = activeContainer else { return }
        container.fullscreenFillsContainer.toggle()
        container.syncFullscreenFlag()
        rebuildMenu()
    }

    @objc private func addProfile() {
        let alert = NSAlert()
        alert.messageText = "New Profile"
        alert.informativeText = "Enter a name for the new profile:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.placeholderString = "Profile name"
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.isEmpty ? "Profile" : input.stringValue
        let colors = ["#5E9CFF", "#FF6B6B", "#4ECB71", "#FFB347", "#C77DFF"]
        let color = colors.randomElement()!
        _ = ProfileManager.shared.add(name: name, colorHex: color, emoji: "🌐")
        rebuildMenu()
    }

    @objc private func renameProfile(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let id = UUID(uuidString: idStr) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename Profile"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = ProfileManager.shared.profile(for: id).name
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ProfileManager.shared.rename(id, to: input.stringValue)
        rebuildMenu()
    }

    @objc private func deleteProfile(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let id = UUID(uuidString: idStr) else { return }
        let profile = ProfileManager.shared.profile(for: id)
        let alert = NSAlert()
        alert.messageText = "Delete \"\(profile.name)\"?"
        alert.informativeText = "This will close all containers using this profile and delete its browsing data."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Close containers using this profile
        let toClose = appDelegate?.containers.filter { $0.profile.id == id } ?? []
        for c in toClose { c.close() }

        Task { await ProfileManager.shared.delete(id) }
        rebuildMenu()
    }

    @objc private func toggleAllContainers() {
        appDelegate?.toggleAllContainers()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
