import Carbon
import AppKit

final class GlobalShortcut {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        register()
    }

    deinit {
        unregister()
    }

    private func register() {
        let hotKeyID = EventHotKeyID(signature: fourCharCode("FLSC"), id: 1)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { shortcut.action() }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1, &eventType,
            selfPtr, &eventHandler
        )

        // Option + Space: optionKey = 0x0800, Space = 49
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let handler = eventHandler { RemoveEventHandler(handler) }
    }

    private func fourCharCode(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for char in string.utf8.prefix(4) {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }
}
