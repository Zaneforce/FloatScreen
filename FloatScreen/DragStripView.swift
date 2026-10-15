import AppKit

final class DragStripView: NSView {
    var onClose: (() -> Void)?
    var onAddApp: ((NSView) -> Void)?

    private let closeButton: StripButton
    private let addAppButton: StripButton

    override init(frame frameRect: NSRect) {
        closeButton = StripButton(frame: .zero)
        addAppButton = StripButton(frame: .zero)
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { true }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1.0).cgColor

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1.0).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        closeButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Close"
        )
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        addAppButton.image = NSImage(
            systemSymbolName: "plus.rectangle.on.rectangle",
            accessibilityDescription: "Add App"
        )
        addAppButton.title = " Add App"
        addAppButton.imagePosition = .imageLeading
        addAppButton.bezelStyle = .inline
        addAppButton.isBordered = false
        addAppButton.contentTintColor = .secondaryLabelColor
        addAppButton.font = .systemFont(ofSize: 11, weight: .medium)
        addAppButton.target = self
        addAppButton.action = #selector(addAppTapped)
        addAppButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(addAppButton)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 14),
            closeButton.heightAnchor.constraint(equalToConstant: 14),

            addAppButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            addAppButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func addAppTapped() { onAddApp?(addAppButton) }
}

private class StripButton: NSButton {
    override var mouseDownCanMoveWindow: Bool { false }
}
