import AppKit

final class FloatingPanel: NSPanel, NSWindowDelegate {
    static let stripHeight: CGFloat = 28

    let dragStrip: DragStripView
    private var displayAspectRatio: CGFloat

    var onAddApp: ((NSView) -> Void)? {
        didSet { dragStrip.onAddApp = onAddApp }
    }

    init(streamView: StreamView, displaySize: NSSize) {
        self.displayAspectRatio = displaySize.width / displaySize.height
        self.dragStrip = DragStripView()

        let initialStreamWidth: CGFloat = displaySize.width / 2
        let initialStreamHeight: CGFloat = displaySize.height / 2
        let contentRect = NSRect(
            x: 200, y: 200,
            width: initialStreamWidth,
            height: initialStreamHeight + Self.stripHeight
        )

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView,
                        .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.delegate = self

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        self.title = "FloatScreen"

        level = .floating
        isOpaque = false
        backgroundColor = .black
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)

        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let minStreamWidth: CGFloat = 480
        let minStreamHeight = minStreamWidth / displayAspectRatio
        contentMinSize = NSSize(
            width: minStreamWidth,
            height: minStreamHeight + Self.stripHeight
        )

        titlebarAppearsTransparent = true
        titleVisibility = .hidden

        let container = NSView()
        container.wantsLayer = true
        self.contentView = container

        dragStrip.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(dragStrip)

        streamView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(streamView)

        NSLayoutConstraint.activate([
            dragStrip.topAnchor.constraint(equalTo: container.topAnchor),
            dragStrip.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            dragStrip.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            dragStrip.heightAnchor.constraint(equalToConstant: Self.stripHeight),

            streamView.topAnchor.constraint(equalTo: dragStrip.bottomAnchor),
            streamView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            streamView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            streamView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        dragStrip.onClose = { [weak self] in self?.orderOut(nil) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func updateAlwaysOnTop(_ enabled: Bool) {
        level = enabled ? .floating : .normal
    }

    func updateOpacity(_ value: CGFloat) {
        alphaValue = value
    }

    func updateForResolution(_ size: NSSize) {
        displayAspectRatio = size.width / size.height
        let minStreamWidth: CGFloat = 480
        let minStreamHeight = minStreamWidth / displayAspectRatio
        contentMinSize = NSSize(
            width: minStreamWidth,
            height: minStreamHeight + Self.stripHeight
        )
    }

    // MARK: - NSWindowDelegate

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let streamWidth = frameSize.width
        let streamHeight = streamWidth / displayAspectRatio
        return NSSize(width: frameSize.width, height: streamHeight + Self.stripHeight)
    }
}
