import AppKit
import CoreGraphics

final class InputMapper: StreamViewInputDelegate {
    private var displayID: CGDirectDisplayID
    private var displaySize: NSSize

    init(displayID: CGDirectDisplayID, displaySize: NSSize) {
        self.displayID = displayID
        self.displaySize = displaySize
    }

    func updateDisplayID(_ newID: CGDirectDisplayID) {
        self.displayID = newID
    }

    func updateDisplaySize(_ size: NSSize) {
        self.displaySize = size
    }

    func handleMouseEvent(_ event: NSEvent, in view: NSView) {
        guard displayID != 0 else { return }

        let pointInView = view.convert(event.locationInWindow, from: nil)
        let viewSize = view.bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        let savedPosition = currentCursorCGPosition()

        let displayPoint = mapToDisplay(pointInView: pointInView, viewSize: viewSize)
        let globalPoint = toGlobalCoordinates(displayPoint)

        CGWarpMouseCursorPosition(globalPoint)
        postMouseEvent(for: event, at: globalPoint)

        // Warp cursor back so it stays visible in the floating window
        CGWarpMouseCursorPosition(savedPosition)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    func handleScrollEvent(_ event: NSEvent, in view: NSView) {
        guard displayID != 0 else { return }

        let pointInView = view.convert(event.locationInWindow, from: nil)
        let viewSize = view.bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else { return }

        let savedPosition = currentCursorCGPosition()

        let displayPoint = mapToDisplay(pointInView: pointInView, viewSize: viewSize)
        let globalPoint = toGlobalCoordinates(displayPoint)

        CGWarpMouseCursorPosition(globalPoint)

        if let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(event.scrollingDeltaY),
            wheel2: Int32(event.scrollingDeltaX),
            wheel3: 0
        ) {
            scrollEvent.location = globalPoint
            scrollEvent.post(tap: CGEventTapLocation.cghidEventTap)
        }

        CGWarpMouseCursorPosition(savedPosition)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: - Coordinate Mapping

    private func currentCursorCGPosition() -> CGPoint {
        // NSEvent.mouseLocation uses AppKit coords (bottom-left origin).
        // CGWarpMouseCursorPosition uses CG coords (top-left origin).
        let appKitPos = NSEvent.mouseLocation
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: appKitPos.x, y: primaryScreenHeight - appKitPos.y)
    }

    private func mapToDisplay(pointInView: NSPoint, viewSize: NSSize) -> NSPoint {
        NSPoint(
            x: pointInView.x / viewSize.width * displaySize.width,
            y: (viewSize.height - pointInView.y) / viewSize.height * displaySize.height
        )
    }

    private func toGlobalCoordinates(_ displayPoint: NSPoint) -> CGPoint {
        let displayBounds = CGDisplayBounds(displayID)
        return CGPoint(
            x: displayBounds.origin.x + displayPoint.x,
            y: displayBounds.origin.y + displayPoint.y
        )
    }

    private func postMouseEvent(for nsEvent: NSEvent, at point: CGPoint) {
        let eventType: CGEventType
        let mouseButton: CGMouseButton

        switch nsEvent.type {
        case .leftMouseDown:
            eventType = .leftMouseDown
            mouseButton = .left
        case .leftMouseUp:
            eventType = .leftMouseUp
            mouseButton = .left
        case .leftMouseDragged:
            eventType = .leftMouseDragged
            mouseButton = .left
        case .rightMouseDown:
            eventType = .rightMouseDown
            mouseButton = .right
        case .rightMouseUp:
            eventType = .rightMouseUp
            mouseButton = .right
        default:
            return
        }

        guard let cgEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: point,
            mouseButton: mouseButton
        ) else { return }

        cgEvent.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
