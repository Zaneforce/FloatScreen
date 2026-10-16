import AppKit

protocol ToolbarViewDelegate: AnyObject {
    func toolbarDidRequestClose()
    func toolbarDidRequestMinimize()
    func toolbarDidRequestBack()
    func toolbarDidRequestForward()
    func toolbarDidRequestReload()
    func toolbarDidNavigate(to urlString: String)
    func toolbarDidTogglePin(_ pinned: Bool)
    func toolbarDidToggleMobileMode()
    func toolbarDidRequestFillVideo()
    func toolbarDidRequestSwitchProfile(relativeTo view: NSView)
}

final class ToolbarView: NSView {
    static let height: CGFloat = 28

    weak var delegate: ToolbarViewDelegate?

    let urlField: NSTextField
    private let closeButton: BarButton
    private let minimizeButton: BarButton
    private let backButton: BarButton
    private let forwardButton: BarButton
    private let reloadButton: BarButton
    private let pinButton: BarButton
    private let mobileButton: BarButton
    private let fillVideoButton: BarButton
    private let profileBadge: BarButton
    private var isPinned = true

    override init(frame frameRect: NSRect) {
        urlField = NSTextField()
        closeButton = BarButton()
        minimizeButton = BarButton()
        backButton = BarButton()
        forwardButton = BarButton()
        reloadButton = BarButton()
        pinButton = BarButton()
        mobileButton = BarButton()
        fillVideoButton = BarButton()
        profileBadge = BarButton()
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { true }

    func updateURL(_ urlString: String) {
        // Don't overwrite while the user is editing
        guard urlField.currentEditor() == nil else { return }
        urlField.stringValue = urlString
    }

    func updateNavigation(canGoBack: Bool, canGoForward: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
    }

    func focusURLField() {
        urlField.selectText(nil)
    }

    func updateMobileMode(_ isMobile: Bool, disabled: Bool = false) {
        mobileButton.isEnabled = !disabled
        if disabled {
            mobileButton.contentTintColor = .tertiaryLabelColor
            mobileButton.image = NSImage(systemSymbolName: "iphone.slash",
                                          accessibilityDescription: "Always desktop site")
            mobileButton.toolTip = "This site is in the always-desktop list"
        } else {
            mobileButton.contentTintColor = isMobile ? .controlAccentColor : .secondaryLabelColor
            mobileButton.image = NSImage(
                systemSymbolName: isMobile ? "iphone" : "iphone.slash",
                accessibilityDescription: isMobile ? "Mobile mode on" : "Mobile mode off"
            )
            mobileButton.toolTip = nil
        }
    }

    private var zoomLabel: NSTextField?

    func showZoomLevel(_ level: CGFloat) {
        zoomLabel?.removeFromSuperview()

        let pct = Int(round(level * 100))
        let label = NSTextField(labelWithString: "\(pct)%")
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.backgroundColor = NSColor(white: 0.18, alpha: 0.95)
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = true
        label.alignment = .center
        label.sizeToFit()
        label.frame.size.width += 10
        label.frame.size.height += 2
        label.wantsLayer = true
        label.layer?.cornerRadius = 4
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: urlField.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        label.alphaValue = 1
        zoomLabel = label

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak label] in
            guard let label, label === self?.zoomLabel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                label.animator().alphaValue = 0
            }, completionHandler: {
                label.removeFromSuperview()
                if self?.zoomLabel === label { self?.zoomLabel = nil }
            })
        }
    }

    func setProfile(_ profile: Profile) {
        profileBadge.title = String(profile.name.prefix(1))
        profileBadge.contentTintColor = profile.color
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1.0).cgColor

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1.0).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        configureButton(closeButton, symbol: "xmark.circle.fill", action: #selector(closeTapped))
        configureButton(minimizeButton, symbol: "minus.circle.fill", action: #selector(minimizeTapped))
        configureButton(backButton, symbol: "chevron.left", action: #selector(backTapped))
        configureButton(forwardButton, symbol: "chevron.right", action: #selector(forwardTapped))
        configureButton(reloadButton, symbol: "arrow.clockwise", action: #selector(reloadTapped))
        configureButton(pinButton, symbol: "pin.fill", action: #selector(pinTapped))
        pinButton.contentTintColor = .controlAccentColor

        configureButton(mobileButton, symbol: "iphone.slash", action: #selector(mobileTapped))
        mobileButton.contentTintColor = .secondaryLabelColor

        configureButton(fillVideoButton, symbol: "arrow.up.left.and.arrow.down.right", action: #selector(fillVideoTapped))
        fillVideoButton.toolTip = "Fill video (Cmd+Shift+F)"

        profileBadge.title = "P"
        profileBadge.font = .systemFont(ofSize: 10, weight: .bold)
        profileBadge.bezelStyle = .inline
        profileBadge.isBordered = false
        profileBadge.contentTintColor = .controlAccentColor
        profileBadge.target = self
        profileBadge.action = #selector(profileBadgeTapped)
        addSubview(profileBadge)

        urlField.placeholderString = "Search or enter URL"
        urlField.font = .systemFont(ofSize: 11)
        urlField.isBordered = true
        urlField.bezelStyle = .roundedBezel
        urlField.cell?.isScrollable = true
        urlField.cell?.usesSingleLineMode = true
        urlField.focusRingType = .none
        urlField.target = self
        urlField.action = #selector(urlFieldAction)
        urlField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(urlField)

        let views = [closeButton, minimizeButton, backButton, forwardButton, reloadButton,
                     profileBadge, urlField, fillVideoButton, mobileButton, pinButton] as [NSView]
        for v in views { v.translatesAutoresizingMaskIntoConstraints = false }

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),

            minimizeButton.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 4),
            minimizeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            minimizeButton.widthAnchor.constraint(equalToConstant: 16),
            minimizeButton.heightAnchor.constraint(equalToConstant: 16),

            backButton.leadingAnchor.constraint(equalTo: minimizeButton.trailingAnchor, constant: 4),
            backButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 20),
            backButton.heightAnchor.constraint(equalToConstant: 16),

            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),
            forwardButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 20),
            forwardButton.heightAnchor.constraint(equalToConstant: 16),

            reloadButton.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 2),
            reloadButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 20),
            reloadButton.heightAnchor.constraint(equalToConstant: 16),

            profileBadge.leadingAnchor.constraint(equalTo: reloadButton.trailingAnchor, constant: 4),
            profileBadge.centerYAnchor.constraint(equalTo: centerYAnchor),
            profileBadge.widthAnchor.constraint(equalToConstant: 18),
            profileBadge.heightAnchor.constraint(equalToConstant: 16),

            urlField.leadingAnchor.constraint(equalTo: profileBadge.trailingAnchor, constant: 4),
            urlField.trailingAnchor.constraint(equalTo: fillVideoButton.leadingAnchor, constant: -4),
            urlField.centerYAnchor.constraint(equalTo: centerYAnchor),
            urlField.heightAnchor.constraint(equalToConstant: 20),

            fillVideoButton.trailingAnchor.constraint(equalTo: mobileButton.leadingAnchor, constant: -2),
            fillVideoButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            fillVideoButton.widthAnchor.constraint(equalToConstant: 20),
            fillVideoButton.heightAnchor.constraint(equalToConstant: 16),

            mobileButton.trailingAnchor.constraint(equalTo: pinButton.leadingAnchor, constant: -2),
            mobileButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            mobileButton.widthAnchor.constraint(equalToConstant: 20),
            mobileButton.heightAnchor.constraint(equalToConstant: 16),

            pinButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            pinButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: 20),
            pinButton.heightAnchor.constraint(equalToConstant: 16),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func configureButton(_ button: BarButton, symbol: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.bezelStyle = .inline
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        addSubview(button)
    }

    @objc private func closeTapped() { delegate?.toolbarDidRequestClose() }
    @objc private func minimizeTapped() { delegate?.toolbarDidRequestMinimize() }
    @objc private func backTapped() { delegate?.toolbarDidRequestBack() }
    @objc private func forwardTapped() { delegate?.toolbarDidRequestForward() }
    @objc private func reloadTapped() { delegate?.toolbarDidRequestReload() }

    @objc private func pinTapped() {
        isPinned.toggle()
        pinButton.contentTintColor = isPinned ? .controlAccentColor : .secondaryLabelColor
        pinButton.image = NSImage(
            systemSymbolName: isPinned ? "pin.fill" : "pin.slash",
            accessibilityDescription: nil
        )
        delegate?.toolbarDidTogglePin(isPinned)
    }

    @objc private func mobileTapped() {
        delegate?.toolbarDidToggleMobileMode()
    }

    @objc private func fillVideoTapped() {
        delegate?.toolbarDidRequestFillVideo()
    }

    @objc private func profileBadgeTapped() {
        delegate?.toolbarDidRequestSwitchProfile(relativeTo: profileBadge)
    }

    @objc private func urlFieldAction() {
        delegate?.toolbarDidNavigate(to: urlField.stringValue)
    }
}

private class BarButton: NSButton {
    override var mouseDownCanMoveWindow: Bool { false }
}
