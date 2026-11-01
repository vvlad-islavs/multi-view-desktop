## 2.0.2+focale.2

- Linux. Let `FlView` own engine-view removal during deferred GTK teardown. This removes duplicate `View #… doesn't exist` errors and unregisters the renderable before disposal, while preserving render-child retention and serialized native-window destruction.

## 2.0.2+focale.1

Focale fork of 2.0.2. Upstream structure, plus:

- `MainAppShellCapture` no longer walks the whole main view after every frame. It keeps the element of the entry widget it found and walks again only once that element is unmounted.
- Linux. Activating a window blocked by a modal dialog hands keyboard focus back to that dialog, so typing never reaches the blocked window.
- Linux. Window close paths never quit the application. The host keeps the GApplication alive until the shared engine has stopped.
- Linux. Render descendants of a view whose engine is already finalized are no longer released. Their EGL display is gone, and releasing them aborted the application while it exited.
- `setPreventClose` and `isPreventClose` apply to dialogs. A dialog can refuse the close requests of the operating system, which `setClosable(false)` does not stop on Wayland.

## 2.0.2

- Fix: MacOS init window show fix.
- Fix: animation override take fix.

## 2.0.1

- Added param `maximize` on init `WindowOptions` and `DialogOptions`
- Added `mainWindowOptions` only for init window.
- Fix: `showOnInit: false` on the startup window. The initial window stays hidden until `completeShow()`, same as windows opened later
- Breaking. `closeAppAfterLastWindowClosed` moved from `MacosPlatformParams` to `MultiPlatformParams` (`generalParams`).
- [Check README] Linux runner update

## 2.0.0

- Breaking. Native window calls go through FFI instead of MethodChannel. Many
  `MultiViewDesktop` methods are now synchronous (no `await`): title, chrome,
  min/max, visibility, focus, alwaysOnTop, and similar. Keep `await` for
  `openWindow` / `openDialog` / `close*` / `setSize` / `setPosition` /
  `setAlignment` / `center` / `setAspectRatio` and popup open-close
- `PopupView` on macOS, Windows, and Linux (X11). Disabled on Wayland: popup
  needs client-side positioning (`GDK_BACKEND=x11`)
- Window and popup animations (`ViewAnimationConfig`, `AnimationSettings`,
  `setForceAnimation`)
- Deferred show via `showOnInit: false` + `completeShow()`
- Optional file logger (`MultiAppConfig.fileLogParams` / `LogParams`)
- `MultiViewDesktop.screen` for connected displays. Physical window bounds
  (`getPhysicalBounds` / `setPhysicalBounds`) for mixed-DPI layouts
- `EnableDynamicAnchor` now is false by default.

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
