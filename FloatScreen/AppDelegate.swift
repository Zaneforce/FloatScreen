import AppKit
import ScreenCaptureKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var virtualDisplayManager: VirtualDisplayManager?
    private var displayStreamer: DisplayStreamer?
    private var floatingPanel: FloatingPanel?
    private var streamView: StreamView?
    private var inputMapper: InputMapper?
    private var menuBarController: MenuBarController?
    private var windowMoverManager: WindowMoverManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        checkScreenRecordingPermission { [weak self] granted in
            guard granted else { return }
            self?.startApp()
        }
    }

    private func startApp() {
        let displayManager = VirtualDisplayManager()
        displayManager.createDisplay(width: 1920, height: 1080)
        self.virtualDisplayManager = displayManager

        let windowMover = WindowMoverManager(displayID: displayManager.displayID)
        self.windowMoverManager = windowMover

        let streamView = StreamView(frame: .zero)
        self.streamView = streamView

        let panel = FloatingPanel(
            streamView: streamView,
            displaySize: NSSize(width: 1920, height: 1080)
        )
        self.floatingPanel = panel

        panel.onAddApp = { [weak self] sender in
            self?.showAddAppMenu(relativeTo: sender)
        }

        let mapper = InputMapper(
            displayID: displayManager.displayID,
            displaySize: NSSize(width: 1920, height: 1080)
        )
        streamView.inputDelegate = mapper
        self.inputMapper = mapper

        let streamer = DisplayStreamer(displayID: displayManager.displayID)
        streamer.delegate = streamView
        self.displayStreamer = streamer

        menuBarController = MenuBarController(
            panel: panel,
            windowMover: windowMover,
            onResolutionChange: { [weak self] width, height in
                self?.rebuildPipeline(width: width, height: height)
            }
        )

        panel.orderFront(nil)

        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await streamer.startCapture(width: 1920, height: 1080)
        }
    }

    // MARK: - Add App Menu

    private func showAddAppMenu(relativeTo view: NSView) {
        guard WindowMoverManager.ensureAccessibility() else { return }
        guard let manager = windowMoverManager else { return }

        let windows = manager.availableWindows()
        let menu = NSMenu()

        if windows.isEmpty {
            let item = NSMenuItem(title: "No windows available", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for entry in windows {
                let label = entry.title.isEmpty
                    ? entry.appName
                    : "\(entry.appName) \u{2014} \(entry.title)"
                let item = NSMenuItem(
                    title: label,
                    action: #selector(addAppSelected(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = Box(entry)
                if let icon = entry.appIcon {
                    item.image = icon.resizedForMenu()
                }
                menu.addItem(item)
            }
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: view)
    }

    @objc private func addAppSelected(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? Box<WindowEntry> else { return }
        windowMoverManager?.moveToVirtualDisplay(box.value)
    }

    // MARK: - Permission Checks

    private func checkScreenRecordingPermission(completion: @escaping (Bool) -> Void) {
        Task {
            do {
                _ = try await SCShareableContent.current
                await MainActor.run { completion(true) }
            } catch {
                await MainActor.run {
                    self.showPermissionAlert()
                    completion(false)
                }
            }
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "FloatScreen needs Screen Recording permission to capture the virtual display. Please grant access in System Settings > Privacy & Security > Screen Recording, then relaunch the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Pipeline Rebuild

    func rebuildPipeline(width: Int, height: Int) {
        Task {
            await displayStreamer?.stopCapture()

            virtualDisplayManager?.changeResolution(width: width, height: height)
            guard let displayManager = virtualDisplayManager else { return }

            await MainActor.run {
                floatingPanel?.updateForResolution(NSSize(width: width, height: height))
                inputMapper?.updateDisplaySize(NSSize(width: width, height: height))
                inputMapper?.updateDisplayID(displayManager.displayID)
                windowMoverManager?.updateDisplayID(displayManager.displayID)
            }

            let streamer = DisplayStreamer(displayID: displayManager.displayID)
            streamer.delegate = streamView
            self.displayStreamer = streamer

            try? await Task.sleep(for: .milliseconds(500))
            await streamer.startCapture(width: width, height: height)
        }
    }
}

// Type-erased box so structs can be stored in representedObject
final class Box<T> {
    let value: T
    init(_ value: T) { self.value = value }
}
