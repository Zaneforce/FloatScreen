import AppKit
import ApplicationServices

struct WindowEntry {
    let pid: pid_t
    let title: String
    let appName: String
    let appIcon: NSImage?
    let bounds: CGRect
}

final class WindowMoverManager {
    private var displayID: CGDirectDisplayID

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    func updateDisplayID(_ newID: CGDirectDisplayID) {
        self.displayID = newID
    }

    static func ensureAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Window Listing

    func availableWindows() -> [WindowEntry] {
        let virtualBounds = CGDisplayBounds(displayID)
        return allWindows().filter { entry in
            !virtualBounds.contains(CGPoint(x: entry.bounds.midX, y: entry.bounds.midY))
        }
    }

    func windowsOnVirtualDisplay() -> [WindowEntry] {
        let virtualBounds = CGDisplayBounds(displayID)
        return allWindows().filter { entry in
            virtualBounds.contains(CGPoint(x: entry.bounds.midX, y: entry.bounds.midY))
        }
    }

    private func allWindows() -> [WindowEntry] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let myPID = ProcessInfo.processInfo.processIdentifier
        var result: [WindowEntry] = []

        for entry in windowList {
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  pid != myPID,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let ownerName = entry[kCGWindowOwnerName as String] as? String
            else { continue }

            let w = boundsDict["Width"] ?? 0
            let h = boundsDict["Height"] ?? 0
            guard w > 100, h > 50 else { continue }

            let title = entry[kCGWindowName as String] as? String ?? ""
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: w, height: h
            )

            let app = NSRunningApplication(processIdentifier: pid)
            let icon = app?.icon

            result.append(WindowEntry(
                pid: pid,
                title: title,
                appName: ownerName,
                appIcon: icon,
                bounds: bounds
            ))
        }

        return result
    }

    // MARK: - Window Moving

    func moveToVirtualDisplay(_ entry: WindowEntry) {
        let displayBounds = CGDisplayBounds(displayID)
        guard let axWindow = findAXWindow(for: entry) else {
            print("[FloatScreen] Could not find AX window for \(entry.appName)")
            return
        }

        var position = displayBounds.origin
        setAXPosition(axWindow, point: &position)

        var size = displayBounds.size
        setAXSize(axWindow, size: &size)
    }

    func moveToMainDisplay(_ entry: WindowEntry) {
        guard let mainScreen = NSScreen.main else { return }
        guard let axWindow = findAXWindow(for: entry) else {
            print("[FloatScreen] Could not find AX window for \(entry.appName)")
            return
        }

        // CG coords: origin at top-left of primary display
        let mainBounds = mainScreen.frame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? mainBounds.height
        let cgOriginY = primaryHeight - mainBounds.maxY

        var position = CGPoint(
            x: mainBounds.origin.x + (mainBounds.width - entry.bounds.width) / 2,
            y: cgOriginY + (mainBounds.height - entry.bounds.height) / 2
        )
        setAXPosition(axWindow, point: &position)
    }

    // MARK: - AX Helpers

    private func findAXWindow(for entry: WindowEntry) -> AXUIElement? {
        let app = AXUIElementCreateApplication(entry.pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return nil }

        // Match by title first
        for window in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            if let axTitle = titleRef as? String, axTitle == entry.title, !axTitle.isEmpty {
                return window
            }
        }

        // Fallback: match by position
        for window in windows {
            var posRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window, kAXPositionAttribute as CFString, &posRef
            ) == .success else { continue }

            var pos = CGPoint.zero
            AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)

            if abs(pos.x - entry.bounds.origin.x) < 5
                && abs(pos.y - entry.bounds.origin.y) < 5 {
                return window
            }
        }

        // Last resort: first window
        return windows.first
    }

    private func setAXPosition(_ element: AXUIElement, point: inout CGPoint) {
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    private func setAXSize(_ element: AXUIElement, size: inout CGSize) {
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }
}

extension NSImage {
    func resizedForMenu() -> NSImage {
        let targetSize = NSSize(width: 16, height: 16)
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        draw(in: NSRect(origin: .zero, size: targetSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        return resized
    }
}
