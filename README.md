# FloatScreen

A native macOS app that creates a virtual second monitor and displays it in a floating, always-on-top window. Like Picture-in-Picture, but for an entire screen.

Drag any app window onto the virtual display, then view and interact with it through the floating window — without needing a physical second monitor.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+ / Swift 5.9+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- **Screen Recording permission** (prompted on first launch)

## Build & Run

```bash
# Generate the Xcode project
xcodegen generate

# Build
xcodebuild -project FloatScreen.xcodeproj -scheme FloatScreen -configuration Debug build

# Run
open ~/Library/Developer/Xcode/DerivedData/FloatScreen-*/Build/Products/Debug/FloatScreen.app
```

Or open `FloatScreen.xcodeproj` in Xcode and press Cmd+R.

## Setup

1. **Grant Screen Recording permission** — on first launch, a dialog will appear asking you to grant permission in System Settings. Follow the instructions, then relaunch the app.

2. **Arrange the virtual display** — open System Settings > Displays and drag the "FloatScreen" display to a convenient position relative to your main display (e.g., to the right).

3. **Move windows to the virtual display** — drag any app window to the edge of your screen where the virtual display is positioned. It will appear in the floating window.

4. **Interact** — click inside the floating window to interact with apps on the virtual display. The cursor warps to the correct position on the virtual display.

## Menu Bar

FloatScreen runs as a menu bar app (no Dock icon). Click the display icon in the menu bar for:

- **Show/Hide Window** — toggle the floating window
- **Always on Top** — keep the window above all other windows (on by default)
- **Resolution** — switch between 1280×720, 1920×1080, 2560×1440
- **Opacity** — adjust window transparency from 50% to 100%
- **Quit** — exit the app and remove the virtual display

## How It Works

1. **Virtual Display** — uses the private `CGVirtualDisplay` API (CoreGraphics) to create a virtual monitor that macOS treats as a real external display.

2. **Screen Capture** — uses ScreenCaptureKit (`SCStream`) to capture the virtual display's contents at 60fps, delivering frames as IOSurfaces.

3. **Rendering** — IOSurfaces are set directly as a CALayer's contents (zero-copy GPU path) for efficient rendering.

4. **Input Mapping** — mouse clicks in the floating window are mapped proportionally to the virtual display's coordinate space, then forwarded via `CGWarpMouseCursorPosition` and synthetic `CGEvent` posting.

## Known Limitations

- **Private API**: `CGVirtualDisplay` is an undocumented Apple API. It may break in future macOS updates without notice. The app cannot be submitted to the Mac App Store.

- **No sandbox**: The app must run without the macOS sandbox because the private display APIs don't work inside a sandboxed process.

- **Screen Recording indicator**: macOS will show the screen recording indicator in the menu bar while the app is running. This is expected behavior.

- **Click-through**: Currently, clicking in the floating window will interact with the virtual display. There is no "click-through" mode yet where clicks pass to windows underneath.

- **Resolution change**: Changing resolution destroys and recreates the virtual display. Any windows on the virtual display may be moved to your main display during this process.

- **Keyboard input**: Keyboard events are not currently forwarded to the virtual display. Use the virtual display's native keyboard focus (click on an app there first, then type normally — your keyboard input will go to the focused app on the virtual display).

## Project Structure

```
FloatScreen/
├── main.swift                      — App entry point
├── AppDelegate.swift               — Lifecycle, permission check, component wiring
├── VirtualDisplayManager.swift     — CGVirtualDisplay creation and lifecycle
├── DisplayStreamer.swift            — SCStream capture pipeline
├── FloatingPanel.swift             — NSPanel (floating, aspect-locked)
├── StreamView.swift                — CALayer rendering + mouse event forwarding
├── InputMapper.swift               — Window-to-display coordinate mapping
├── MenuBarController.swift         — NSStatusItem menu
└── FloatScreen-Bridging-Header.h   — Private CGVirtualDisplay API declarations
```

## License

MIT
