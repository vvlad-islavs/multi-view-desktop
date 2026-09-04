## 2.0.0

- Breaking. Native window calls go through FFI instead of MethodChannel. Many
  `MultiViewDesktop` methods are now synchronous (no `await`): title, chrome,
  min/max, visibility, focus, alwaysOnTop, and similar. Keep `await` for
  `openWindow` / `openDialog` / `close*` / `setSize` / `setPosition` /
  `setAlignment` / `center` / `setAspectRatio` and popup open-close
- [Check README] `PopupView` on macOS, Windows, and Linux (X11). Disabled on
  Wayland: popup needs client-side positioning (`GDK_BACKEND=x11`)
- [Check README] Window and popup animations (`ViewAnimationConfig`,
  `AnimationSettings`, `setForceAnimation`)
- [Check README] `MultiViewDesktop.screen` for connected displays. Physical
  window bounds (`getPhysicalBounds` / `setPhysicalBounds`) for mixed-DPI layouts

## 1.2.2

- [Check README] Windows. Fixed other plugins registration and using. Minor native setting update

## 1.2.1

- MacOS. Returned `closeAppAfterLastWindowClosed` param for more custom ways
- MacOS. Add taskbar icon tap handler.
- MacOS. Specific functions moved to `macos` part

## 1.2.0

- [Check README] Linux. x11 support (setAlignment, alwaysOnTop, setPosition, center). Use
  GDK_BACKEND=x11 env arg to enable
- [Check README] Taskbar custom menu items on all platforms
- [Check README] MacOS. OnTerminate handler (CMD+Q/terminate the app from taskbar)
- MacOS. Removed `closeAppAfterLastWindowClosed` param. App automatically defines when need to stay
  in memory
- MacOS. saveLastWindowToReopen now ignored by one of causes: use `closeApp`/ onTerminate/ close
  mode is `destroy`

## 1.1.2

- Up view create timeout to 10 sec
- Fix: Orphan was sending data to observers

## 1.1.1

- Hot restart windowOptions fix

## 1.1.0

- View builder got context & id.
- [Check README] Added observers to runMultiApp->config
- [Check README] Added native openDialog
- [Check README] Updated EntryApp requirements, now needs only in home builder.

## 1.0.2

- Linux min/max size fix. Repository link fix.

## 1.0.1

- Linux setup doc update

## 1.0.0

- Windows, macOS and linux (without X11) support