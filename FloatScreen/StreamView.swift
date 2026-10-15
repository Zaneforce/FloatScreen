import AppKit
import QuartzCore

protocol StreamViewInputDelegate: AnyObject {
    func handleMouseEvent(_ event: NSEvent, in view: NSView)
    func handleScrollEvent(_ event: NSEvent, in view: NSView)
}

final class StreamView: NSView, DisplayStreamerDelegate {
    weak var inputDelegate: StreamViewInputDelegate?

    private var displayLayer: CALayer!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layerContentsRedrawPolicy = .never

        displayLayer = CALayer()
        displayLayer.contentsGravity = .resizeAspect
        displayLayer.frame = bounds
        displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(displayLayer)
    }

    func streamer(_ streamer: DisplayStreamer, didOutputSurface surface: IOSurfaceRef) {
        displayLayer.contents = surface
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        inputDelegate?.handleMouseEvent(event, in: self)
        window?.orderFront(nil)
    }

    override func mouseUp(with event: NSEvent) {
        inputDelegate?.handleMouseEvent(event, in: self)
        window?.orderFront(nil)
    }

    override func mouseDragged(with event: NSEvent) {
        inputDelegate?.handleMouseEvent(event, in: self)
    }

    override func rightMouseDown(with event: NSEvent) {
        inputDelegate?.handleMouseEvent(event, in: self)
        window?.orderFront(nil)
    }

    override func rightMouseUp(with event: NSEvent) {
        inputDelegate?.handleMouseEvent(event, in: self)
        window?.orderFront(nil)
    }

    override func scrollWheel(with event: NSEvent) {
        inputDelegate?.handleScrollEvent(event, in: self)
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        displayLayer?.frame = bounds
    }
}
