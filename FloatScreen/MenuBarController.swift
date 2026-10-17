import AppKit
import WebKit

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

        let copyUAItem = NSMenuItem(
            title: "Copy User Agent",
            action: #selector(copyUserAgent),
            keyEquivalent: ""
        )
        copyUAItem.target = self
        menu.addItem(copyUAItem)

        let clearDataItem = NSMenuItem(
            title: "Clear Data for This Site",
            action: #selector(clearSiteData),
            keyEquivalent: ""
        )
        clearDataItem.target = self
        if let host = activeContainer?.currentURL?.host {
            clearDataItem.title = "Clear Data for \(host)"
        }
        menu.addItem(clearDataItem)

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

        // Sound mode for active container
        let soundItem = NSMenuItem(title: "Notification Sound", action: nil, keyEquivalent: "")
        let soundMenu = NSMenu()
        for mode in ContainerWindow.SoundMode.allCases {
            let item = NSMenuItem(title: mode.label, action: #selector(setSoundMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = activeContainer?.soundMode == mode ? .on : .off
            soundMenu.addItem(item)
        }
        soundMenu.addItem(.separator())
        let soundSelItem = NSMenuItem(title: "Sound: \(NotificationSound.shared.selectedSoundName)", action: nil, keyEquivalent: "")
        let soundSelMenu = NSMenu()
        for name in NotificationSound.availableSounds {
            let item = NSMenuItem(title: name, action: #selector(selectSound(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = name == NotificationSound.shared.selectedSoundName ? .on : .off
            soundSelMenu.addItem(item)
        }
        soundSelItem.submenu = soundSelMenu
        soundMenu.addItem(soundSelItem)
        soundItem.submenu = soundMenu
        menu.addItem(soundItem)

        // Zoom submenu
        let zoomItem = NSMenuItem(title: "Zoom", action: nil, keyEquivalent: "")
        let zoomMenu = NSMenu()
        let zoomInItem = NSMenuItem(title: "Zoom In", action: #selector(zoomIn), keyEquivalent: "")
        zoomInItem.target = self
        zoomMenu.addItem(zoomInItem)
        let zoomOutItem = NSMenuItem(title: "Zoom Out", action: #selector(zoomOut), keyEquivalent: "")
        zoomOutItem.target = self
        zoomMenu.addItem(zoomOutItem)
        let zoomResetItem = NSMenuItem(title: "Actual Size (100%)", action: #selector(zoomReset), keyEquivalent: "")
        zoomResetItem.target = self
        zoomMenu.addItem(zoomResetItem)
        if let active = activeContainer {
            zoomMenu.addItem(.separator())
            let pct = Int(round(active.webView.pageZoom * 100))
            let label = NSMenuItem(title: "Current: \(pct)%", action: nil, keyEquivalent: "")
            label.isEnabled = false
            zoomMenu.addItem(label)
        }
        zoomItem.submenu = zoomMenu
        menu.addItem(zoomItem)

        // Mobile mode
        let mobileItem = NSMenuItem(
            title: "Mobile Mode",
            action: #selector(toggleMobileMode(_:)),
            keyEquivalent: ""
        )
        mobileItem.target = self
        if let active = activeContainer {
            mobileItem.state = active.isMobileMode ? .on : .off
        }
        menu.addItem(mobileItem)

        let autoMobileItem = NSMenuItem(
            title: "Auto Mobile (by width)",
            action: #selector(toggleAutoMobile(_:)),
            keyEquivalent: ""
        )
        autoMobileItem.target = self
        if let active = activeContainer {
            autoMobileItem.state = active.isAutoMobile ? .on : .off
        }
        menu.addItem(autoMobileItem)

        // Always-desktop sites
        let adSiteItem = NSMenuItem(title: "Always Desktop Sites", action: nil, keyEquivalent: "")
        let adSiteMenu = NSMenu()
        for site in WebViewConfig.alwaysDesktopSites {
            let item = NSMenuItem(title: site, action: #selector(removeAlwaysDesktopSite(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = site
            adSiteMenu.addItem(item)
        }
        adSiteMenu.addItem(.separator())
        let addSiteItem = NSMenuItem(title: "Add Current Site\u{2026}", action: #selector(addAlwaysDesktopSite), keyEquivalent: "")
        addSiteItem.target = self
        adSiteMenu.addItem(addSiteItem)
        adSiteItem.submenu = adSiteMenu
        menu.addItem(adSiteItem)

        // Size presets
        let sizeItem = NSMenuItem(title: "Size Preset", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        let presets: [(String, CGFloat, CGFloat, Bool?)] = [
            ("Phone (390\u{00d7}844)", 390, 844, true),
            ("Tablet (820\u{00d7}1180)", 820, 1180, nil),
            ("Desktop (1280\u{00d7}800)", 1280, 800, false),
        ]
        for (idx, preset) in presets.enumerated() {
            let item = NSMenuItem(title: preset.0, action: #selector(applySizePreset(_:)), keyEquivalent: "")
            item.target = self
            item.tag = idx
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        menu.addItem(.separator())

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

        let showAllItem = NSMenuItem(
            title: "Show All Containers",
            action: #selector(showAllContainers),
            keyEquivalent: ""
        )
        showAllItem.target = self
        menu.addItem(showAllItem)

        menu.addItem(.separator())

        let hideShareItem = NSMenuItem(
            title: "Hide from Screen Sharing",
            action: #selector(toggleScreenSharing(_:)),
            keyEquivalent: ""
        )
        hideShareItem.target = self
        if let active = activeContainer {
            hideShareItem.state = active.isHiddenFromScreenSharing ? .on : .off
        }
        menu.addItem(hideShareItem)

        let hideAllShareItem = NSMenuItem(
            title: "Hide All from Screen Sharing",
            action: #selector(hideAllFromScreenSharing),
            keyEquivalent: ""
        )
        hideAllShareItem.target = self
        menu.addItem(hideAllShareItem)

        let showAllShareItem = NSMenuItem(
            title: "Show All in Screen Sharing",
            action: #selector(showAllInScreenSharing),
            keyEquivalent: ""
        )
        showAllShareItem.target = self
        menu.addItem(showAllShareItem)

        // Bubble settings submenu
        let bubbleItem = NSMenuItem(title: "Bubbles", action: nil, keyEquivalent: "")
        let bubbleMenu = NSMenu()
        let fadeItem = NSMenuItem(title: "Fade When Idle", action: #selector(toggleBubbleFade(_:)), keyEquivalent: "")
        fadeItem.target = self
        fadeItem.state = BubbleSettings.shared.fadeEnabled ? .on : .off
        bubbleMenu.addItem(fadeItem)

        let delayItem = NSMenuItem(title: "Idle Delay", action: nil, keyEquivalent: "")
        let delayMenu = NSMenu()
        for (label, val) in BubbleSettings.delayOptions {
            let item = NSMenuItem(title: label, action: #selector(setBubbleDelay(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(val)
            item.state = BubbleSettings.shared.idleDelay == val ? .on : .off
            delayMenu.addItem(item)
        }
        delayItem.submenu = delayMenu
        bubbleMenu.addItem(delayItem)

        let opItem = NSMenuItem(title: "Idle Opacity", action: nil, keyEquivalent: "")
        let opMenu = NSMenu()
        for (label, val) in BubbleSettings.opacityOptions {
            let item = NSMenuItem(title: label, action: #selector(setBubbleOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = val
            item.state = abs(BubbleSettings.shared.idleOpacity - val) < 0.01 ? .on : .off
            opMenu.addItem(item)
        }
        opItem.submenu = opMenu
        bubbleMenu.addItem(opItem)
        bubbleItem.submenu = bubbleMenu
        menu.addItem(bubbleItem)

        menu.addItem(.separator())

        let reopenItem = NSMenuItem(
            title: "Reopen Closed Container",
            action: #selector(reopenClosed),
            keyEquivalent: ""
        )
        reopenItem.target = self
        reopenItem.isEnabled = !(appDelegate?.recentlyClosed.isEmpty ?? true)
        menu.addItem(reopenItem)

        if let recent = appDelegate?.recentlyClosed, !recent.isEmpty {
            let recentItem = NSMenuItem(title: "Recently Closed", action: nil, keyEquivalent: "")
            let recentSubmenu = NSMenu()
            for state in recent.reversed().prefix(10) {
                let title = state.urlString.isEmpty ? "New Tab" : state.urlString
                let item = NSMenuItem(
                    title: String(title.prefix(60)),
                    action: #selector(reopenSpecific(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = Box(state)
                recentSubmenu.addItem(item)
            }
            recentItem.submenu = recentSubmenu
            menu.addItem(recentItem)
        }

        menu.addItem(.separator())

        let updateItem = NSMenuItem(
            title: "Check for Updates\u{2026}",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        let autoUpdateItem = NSMenuItem(
            title: "Automatic Updates",
            action: #selector(toggleAutoUpdates(_:)),
            keyEquivalent: ""
        )
        autoUpdateItem.target = self
        autoUpdateItem.state = (appDelegate?.updaterController.updater.automaticallyChecksForUpdates ?? true) ? .on : .off
        menu.addItem(autoUpdateItem)

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

    @objc private func copyUserAgent() {
        guard let container = activeContainer else { return }
        container.webView.evaluateJavaScript("navigator.userAgent") { result, _ in
            if let ua = result as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ua, forType: .string)
                print("[FloatScreen] Copied UA: \(ua)")
            }
        }
    }

    @objc private func clearSiteData() {
        guard let container = activeContainer,
              let host = container.currentURL?.host else { return }
        let dataStore = container.webView.configuration.websiteDataStore
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.fetchDataRecords(ofTypes: types) { records in
            let matching = records.filter { record in
                record.displayName == host || host.hasSuffix(".\(record.displayName)")
            }
            guard !matching.isEmpty else {
                print("[FloatScreen] No data records found for \(host)")
                return
            }
            dataStore.removeData(ofTypes: types, for: matching) {
                print("[FloatScreen] Cleared \(matching.count) data records for \(host)")
                DispatchQueue.main.async { container.webView.reload() }
            }
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

    @objc private func setSoundMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ContainerWindow.SoundMode(rawValue: raw) else { return }
        activeContainer?.soundMode = mode
        rebuildMenu()
    }

    @objc private func selectSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        NotificationSound.shared.selectedSoundName = name
        NotificationSound.shared.playIfNeeded()
        rebuildMenu()
    }

    @objc private func zoomIn() { activeContainer?.zoomIn() }
    @objc private func zoomOut() { activeContainer?.zoomOut() }
    @objc private func zoomReset() { activeContainer?.zoomReset() }

    @objc private func addAlwaysDesktopSite() {
        guard let host = activeContainer?.currentURL?.host else { return }
        var sites = WebViewConfig.alwaysDesktopSites
        guard !sites.contains(host) else { return }
        sites.append(host)
        WebViewConfig.alwaysDesktopSites = sites
        activeContainer?.toolbarView.updateMobileMode(
            activeContainer?.isMobileMode ?? false,
            disabled: true
        )
        rebuildMenu()
    }

    @objc private func removeAlwaysDesktopSite(_ sender: NSMenuItem) {
        guard let site = sender.representedObject as? String else { return }
        var sites = WebViewConfig.alwaysDesktopSites
        sites.removeAll { $0 == site }
        WebViewConfig.alwaysDesktopSites = sites
        rebuildMenu()
    }

    @objc private func toggleMobileMode(_ sender: NSMenuItem) {
        guard let container = activeContainer else { return }
        container.setMobileMode(!container.isMobileMode)
        rebuildMenu()
    }

    @objc private func toggleAutoMobile(_ sender: NSMenuItem) {
        guard let container = activeContainer else { return }
        container.isAutoMobile.toggle()
        rebuildMenu()
    }

    @objc private func applySizePreset(_ sender: NSMenuItem) {
        guard let container = activeContainer else { return }
        let presets: [(CGFloat, CGFloat, Bool?)] = [
            (390, 844, true),
            (820, 1180, nil),
            (1280, 800, false),
        ]
        let (w, h, mobile) = presets[sender.tag]
        container.applySizePreset(width: w, height: h, enableMobile: mobile)
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

    @objc private func reopenClosed() {
        appDelegate?.reopenLastClosed()
        rebuildMenu()
    }

    @objc private func reopenSpecific(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? Box<ContainerState> else { return }
        appDelegate?.recentlyClosed.removeAll { $0.id == box.value.id }
        appDelegate?.reopenContainer(from: box.value)
        rebuildMenu()
    }

    @objc private func toggleAllContainers() {
        appDelegate?.toggleAllContainers()
    }

    @objc private func showAllContainers() {
        appDelegate?.showAllContainers()
    }

    @objc private func toggleScreenSharing(_ sender: NSMenuItem) {
        guard let container = activeContainer else { return }
        container.setHiddenFromScreenSharing(!container.isHiddenFromScreenSharing)
        rebuildMenu()
    }

    @objc private func hideAllFromScreenSharing() {
        appDelegate?.containers.forEach { $0.setHiddenFromScreenSharing(true) }
        rebuildMenu()
    }

    @objc private func toggleBubbleFade(_ sender: NSMenuItem) {
        BubbleSettings.shared.fadeEnabled.toggle()
        appDelegate?.bubbles.forEach { $0.resetIdleTimer() }
        rebuildMenu()
    }

    @objc private func setBubbleDelay(_ sender: NSMenuItem) {
        BubbleSettings.shared.idleDelay = TimeInterval(sender.tag)
        appDelegate?.bubbles.forEach { $0.resetIdleTimer() }
        rebuildMenu()
    }

    @objc private func setBubbleOpacity(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? CGFloat else { return }
        BubbleSettings.shared.idleOpacity = val
        rebuildMenu()
    }

    @objc private func showAllInScreenSharing() {
        appDelegate?.containers.forEach { $0.setHiddenFromScreenSharing(false) }
        rebuildMenu()
    }

    @objc private func checkForUpdates() {
        appDelegate?.updaterController.checkForUpdates(nil)
    }

    @objc private func toggleAutoUpdates(_ sender: NSMenuItem) {
        guard let updater = appDelegate?.updaterController.updater else { return }
        updater.automaticallyChecksForUpdates.toggle()
        rebuildMenu()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
