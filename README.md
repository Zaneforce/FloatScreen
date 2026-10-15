# FloatScreen

A floating web container for macOS. Each container is an always-on-top window with a full WKWebView inside — like Picture-in-Picture, but for any website.

Keep YouTube, Slack, Claude, or any web app visible while you work in other apps. Multiple containers can run simultaneously, each with independent URL, position, size, and opacity.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+ / Swift 5.9+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

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

## Features

### Floating Web Containers
- Always-on-top windows that float above other apps
- Full WKWebView with persistent cookies — log into sites and stay logged in
- Safari user agent so sites like Google allow normal login
- Fullscreen video and Picture-in-Picture support where sites allow it
- Links that open new windows (target=_blank) stay in the same container
- Downloads save to your Downloads folder

### Toolbar (28px top bar)
- **Close** (×) — close the container
- **Back / Forward / Reload** — standard web navigation
- **URL / Search field** — type a URL or search term, press Enter
- **Pin toggle** (📌) — toggle always-on-top per container
- Drag the toolbar background to move the window
- Auto-hide option: toolbar hides until you hover near the top

### Multiple Containers
- Open as many containers as you need, each with its own URL
- All open containers are listed in the menu bar
- State is saved on quit and restored on launch (URL, position, size, opacity)

### Menu Bar
Click the window icon in the menu bar for:
- **New Container** — open a blank container
- **Open containers** — click to focus any container
- **Favorites** — quick-launch presets (YouTube, Claude, GitHub, Notion, Slack) plus "Add Current Page"
- **Opacity** — set window transparency from 30% to 100%
- **Toggle Click-Through** — make containers transparent to mouse clicks (toggle from menu since the window can't be clicked)
- **Show/Hide All** — toggle visibility of all containers
- **Quit** — save state and exit

### Keyboard Shortcuts
| Shortcut | Action |
|----------|--------|
| **⌥ Space** | Show/hide all containers (global, works from any app) |
| **⌘ N** | New container |
| **⌘ W** | Close current container |
| **⌘ L** | Focus URL field |
| **⌘ R** | Reload page |
| **⌘ [** | Go back |
| **⌘ ]** | Go forward |

## How It Works

FloatScreen is a sandboxed macOS app (no private APIs) that creates floating `NSPanel` windows containing `WKWebView` instances. Each panel uses:
- `.floating` window level to stay above other apps
- `.canJoinAllSpaces` to appear on all virtual desktops
- `WKWebsiteDataStore.default()` for persistent cookies across restarts
- Auto Layout for responsive toolbar + webview layout

## Known Limitations

- **DRM content**: Some streaming sites (Netflix, Disney+) use Widevine DRM which may not work in WKWebView. YouTube works fine.
- **Browser extensions**: No support for browser extensions or plugins.
- **DevTools**: No built-in developer tools. Use Safari's Web Inspector (Develop > [app name]) if you enable the Develop menu in Safari preferences.
- **File uploads**: Basic file uploads work; drag-and-drop uploads may be limited.
- **Global shortcut**: Option+Space requires the app to be running. It uses Carbon's RegisterEventHotKey API.

## Project Structure

```
FloatScreen/
├── main.swift              — App entry point
├── AppDelegate.swift       — Lifecycle, container management, state restore, hidden menu
├── ContainerWindow.swift   — NSPanel + WKWebView + toolbar layout
├── ToolbarView.swift       — Navigation bar (close, back, forward, reload, URL, pin)
├── WebViewConfig.swift     — WKWebView configuration, delegates, download handling
├── ContainerState.swift    — Codable state model, UserDefaults persistence
├── Favorites.swift         — Favorites CRUD with preset defaults
├── MenuBarController.swift — NSStatusItem menu
├── GlobalShortcut.swift    — Carbon hotkey (Option+Space)
└── Info.plist / .entitlements
```

## License

MIT
