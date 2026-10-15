import AppKit

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let panel: FloatingPanel
    private let windowMover: WindowMoverManager
    private let onResolutionChange: (Int, Int) -> Void

    private var isAlwaysOnTop = true
    private var currentOpacity: CGFloat = 1.0
    private var currentResolutionIndex = 1

    private let resolutions: [(String, Int, Int)] = [
        ("1280 \u{00d7} 720", 1280, 720),
        ("1920 \u{00d7} 1080", 1920, 1080),
        ("2560 \u{00d7} 1440", 2560, 1440),
    ]

    private static let addAppMenuID = NSUserInterfaceItemIdentifier("addApp")
    private static let sendBackMenuID = NSUserInterfaceItemIdentifier("sendBack")

    init(panel: FloatingPanel,
         windowMover: WindowMoverManager,
         onResolutionChange: @escaping (Int, Int) -> Void) {
        self.panel = panel
        self.windowMover = windowMover
        self.onResolutionChange = onResolutionChange
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        setupMenu()
    }

    private func setupMenu() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "display",
                accessibilityDescription: "FloatScreen"
            )
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: panel.isVisible ? "Hide Window" : "Show Window",
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // Add App submenu
        let addAppItem = NSMenuItem(title: "Add App", action: nil, keyEquivalent: "")
        let addAppSubmenu = NSMenu()
        addAppSubmenu.delegate = self
        addAppSubmenu.identifier = Self.addAppMenuID
        addAppItem.submenu = addAppSubmenu
        menu.addItem(addAppItem)

        // Send Back submenu
        let sendBackItem = NSMenuItem(title: "Send Back", action: nil, keyEquivalent: "")
        let sendBackSubmenu = NSMenu()
        sendBackSubmenu.delegate = self
        sendBackSubmenu.identifier = Self.sendBackMenuID
        sendBackItem.submenu = sendBackSubmenu
        menu.addItem(sendBackItem)

        menu.addItem(.separator())

        let alwaysOnTopItem = NSMenuItem(
            title: "Always on Top",
            action: #selector(toggleAlwaysOnTop(_:)),
            keyEquivalent: ""
        )
        alwaysOnTopItem.target = self
        alwaysOnTopItem.state = isAlwaysOnTop ? .on : .off
        menu.addItem(alwaysOnTopItem)

        menu.addItem(.separator())

        let resolutionItem = NSMenuItem(title: "Resolution", action: nil, keyEquivalent: "")
        let resolutionMenu = NSMenu()
        for (index, res) in resolutions.enumerated() {
            let item = NSMenuItem(
                title: res.0,
                action: #selector(changeResolution(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = index == currentResolutionIndex ? .on : .off
            resolutionMenu.addItem(item)
        }
        resolutionItem.submenu = resolutionMenu
        menu.addItem(resolutionItem)

        let opacityItem = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        let opacityMenu = NSMenu()
        for pct in stride(from: 100, through: 50, by: -10) {
            let item = NSMenuItem(
                title: "\(pct)%",
                action: #selector(changeOpacity(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = pct
            item.state = CGFloat(pct) / 100.0 == currentOpacity ? .on : .off
            opacityMenu.addItem(item)
        }
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

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

    // MARK: - NSMenuDelegate (dynamic submenus)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        guard WindowMoverManager.ensureAccessibility() else {
            let item = NSMenuItem(
                title: "Grant Accessibility access\u{2026}",
                action: nil, keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
            return
        }

        let isAddApp = menu.identifier == Self.addAppMenuID
        let windows = isAddApp
            ? windowMover.availableWindows()
            : windowMover.windowsOnVirtualDisplay()

        if windows.isEmpty {
            let label = isAddApp ? "No windows available" : "No windows on display"
            let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }

        let action: Selector = isAddApp
            ? #selector(moveToVirtualDisplay(_:))
            : #selector(moveToMainDisplay(_:))

        for entry in windows {
            let label = entry.title.isEmpty
                ? entry.appName
                : "\(entry.appName) \u{2014} \(entry.title)"
            let item = NSMenuItem(title: label, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = Box(entry)
            if let icon = entry.appIcon {
                item.image = icon.resizedForMenu()
            }
            menu.addItem(item)
        }
    }

    // MARK: - Actions

    @objc private func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFront(nil)
        }
        rebuildMenu()
    }

    @objc private func toggleAlwaysOnTop(_ sender: NSMenuItem) {
        isAlwaysOnTop.toggle()
        panel.updateAlwaysOnTop(isAlwaysOnTop)
        rebuildMenu()
    }

    @objc private func changeResolution(_ sender: NSMenuItem) {
        let index = sender.tag
        let (_, width, height) = resolutions[index]
        currentResolutionIndex = index
        onResolutionChange(width, height)
        rebuildMenu()
    }

    @objc private func changeOpacity(_ sender: NSMenuItem) {
        currentOpacity = CGFloat(sender.tag) / 100.0
        panel.updateOpacity(currentOpacity)
        rebuildMenu()
    }

    @objc private func moveToVirtualDisplay(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? Box<WindowEntry> else { return }
        windowMover.moveToVirtualDisplay(box.value)
    }

    @objc private func moveToMainDisplay(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? Box<WindowEntry> else { return }
        windowMover.moveToMainDisplay(box.value)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
