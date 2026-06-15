# multiview_desktop

[![pub version][pub-image]][pub-url]

[pub-image]: https://img.shields.io/pub/v/multiview_desktop.svg
[pub-url]: https://pub.dev/packages/multiview_desktop

Flutter desktop library for managing multiple OS windows from a single Flutter engine and a single Dart isolate.

Unlike libraries that spawn a new Flutter engine per window, multiview_desktop uses Flutter's multi-view API: all windows share one engine, one isolate, and one memory space. Opening a second window is as cheap as adding a new widget to the tree, and communication between windows is plain Dart with no isolate ports, no serialization, and no native bridge for passing data.

---

- [Platform Support](#platform-support)
- [Architecture overview](#architecture-overview)
- [Setup](#setup)
  - [Linux](#linux-setup)
  - [Windows](#windows-setup)
  - [macOS](#macos-setup)
- [Usage](#usage)
  - [Entry point](#entry-point)
  - [Open a window](#open-a-window)
  - [Window options](#window-options)
  - [Window events](#window-events)
  - [Communication between windows](#communication-between-windows)
  - [Confirm before closing](#confirm-before-closing)
  - [Close mode](#close-mode)
  - [Frameless windows](#frameless-windows)
  - [Watching the window list](#watching-the-window-list)
  - [Window observers](#window-observers)
  - [Application config](#application-config)
- [API](#api)
  - [MultiViewDesktop](#multiviewdesktop-1)
  - [WindowListener](#windowlistener-1)
  - [WindowObserver](#windowobserver-1)
  - [WindowCommunicator](#windowcommunicator-1)
  - [WindowOptions](#windowoptions-1)
  - [MultiAppConfig](#multiappconfig-1)
  - [CloseMode](#closemode-1)
  - [Widgets](#widgets-1)

---

## Platform Support

| Linux | macOS | Windows |
|:-----:|:-----:|:-------:|
|   +   |   +   |    +    |

> **Linux note.** The multi-view Flutter API on Linux currently requires a Wayland compositor. Running under an X11 session is not supported. Individual window control calls that depend on compositor positioning (such as `setPosition`, `setAlignment`, `center`) may return silently when the compositor ignores client-side placement requests.

---

## Architecture overview

`runMultiApp` starts a single Flutter engine with multi-view mode enabled. Every OS window is a separate `FlutterView` attached to that engine. The Dart code for all windows runs in the same isolate, so widgets and state objects can be passed around like any other Dart value.

This is the key difference from multi-engine approaches:

- Opening a window does not allocate a new VM, engine, or isolate.
- Widgets, streams, `ChangeNotifier` instances, and any Dart object can be shared directly across windows. No serialization or IPC channel is needed.
- `WindowCommunicator` is provided as a lightweight routing helper, but sharing a `ValueNotifier` or calling a method on a shared object is equally valid and often simpler.

---

## Setup

### Linux setup

Edit `linux/runner/my_application.cc`.

1. Add the runner header alongside the other includes:

```diff
 #include <flutter_linux/flutter_linux.h>
 #ifdef GDK_WINDOWING_X11
 #include <gdk/gdkx.h>
 #endif

+#include <multiview_desktop/multiview_desktop_runner.h>

 #include "flutter/generated_plugin_registrant.h"
```

2. Add a `first-frame` callback before `my_application_activate`. The primary window must stay hidden until Flutter paints its first frame; otherwise users see a blank window. Secondary windows opened by the runner follow the same pattern automatically.

```diff
 G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

+// Called when first Flutter frame received.
+static void first_frame_cb(MyApplication* self, FlView* view) {
+  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
+}
+
 // Implements GApplication::activate.
 static void my_application_activate(GApplication* application) {
```

3. In `my_application_activate`, call `multiview_desktop_linux_runner_install` before creating any window, call `multiview_desktop_linux_runner_prepare_dart_project` right after `fl_dart_project_new`, and call `multiview_desktop_linux_runner_register_primary` after `fl_register_plugins`. Connect `first_frame_cb` to the view's `first-frame` signal and do **not** call `gtk_widget_show` on the window itself; the callback shows the top-level widget once rendering starts.

```diff
 static void my_application_activate(GApplication* application) {
   MyApplication* self = MY_APPLICATION(application);
+  multiview_desktop_linux_runner_install(GTK_APPLICATION(application));

   GtkWindow* window =
       GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

   // ... (header bar setup, gtk_window_set_default_size - unchanged)
-  gtk_window_set_default_size(window, 1280, 720);
+  gtk_window_set_default_size(window, 800, 600);

   g_autoptr(FlDartProject) project = fl_dart_project_new();
+  multiview_desktop_linux_runner_prepare_dart_project(project);
   fl_dart_project_set_dart_entrypoint_arguments(
       project, self->dart_entrypoint_arguments);

   FlView* view = fl_view_new(project);
   GdkRGBA background_color;
   gdk_rgba_parse(&background_color, "#000000");
   fl_view_set_background_color(view, &background_color);
   gtk_widget_show(GTK_WIDGET(view));
   gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

   g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                            self);
   gtk_widget_realize(GTK_WIDGET(view));

   fl_register_plugins(FL_PLUGIN_REGISTRY(view));

+  multiview_desktop_linux_runner_register_primary(window, view);

   gtk_widget_grab_focus(GTK_WIDGET(view));
-  gtk_widget_show(GTK_WIDGET(window));
 }
```

What each call does:

- `first_frame_cb`: shows the top-level `GtkWindow` after Flutter renders the first frame. Connect it with `g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self)` and call `gtk_widget_realize` on the view before registering plugins.
- `multiview_desktop_linux_runner_install`: hooks the `GtkApplication` so that new GTK windows can be created when Dart calls `openWindow`. Must be the very first call in `activate`.
- `multiview_desktop_linux_runner_prepare_dart_project`: fixes asset, ICU, and AOT paths when launching from the build directory. Required so that secondary views can locate the bundle.
- `multiview_desktop_linux_runner_register_primary`: registers the primary window and view with the plugin so that per-window APIs work on the main window.

You can also set the default title for secondary windows before they appear:

```c
multiview_desktop_linux_runner_set_default_title("My App");
```

#### Linux platform limitations

- **Multi-view requires Wayland.** The Flutter multi-view API on Linux currently works under Wayland compositors only. Running under a pure X11 session is not supported and the application will not open secondary windows.
- **Window positioning on Wayland.** `setPosition`, `setAlignment`, and `center` use `gtk_window_move` under the hood. On Wayland the compositor controls window placement and the call is silently ignored.
- **`setAlwaysOnTop`.** Uses `gtk_window_set_keep_above`. Whether the compositor respects this hint depends on the desktop environment.
- **`setHasShadow`.** No-op on Linux. The native shadow is always drawn by the compositor.
- **`setMovable`.** Maps to `setResizable` on Linux (there is no separate movability flag in GTK).
- **`setBadgeLabel`, `setVisibleOnAllWorkspaces`, `hideFromCollection`.** macOS-only. Not available on Linux.

---

### Windows setup

The example `windows/runner/flutter_window.cpp` and `flutter_window.h` are replaced entirely. Copy the versions from the example app included in this package, or apply the following changes manually.

**`windows/runner/flutter_window.h`**: remove the `FlutterViewController` include and the `flutter_controller_` field; keep only `project_`:

```diff
 #include <flutter/dart_project.h>
-#include <flutter/flutter_view_controller.h>
 #include <memory>
 #include "win32_window.h"

 class FlutterWindow : public Win32Window {
  public:
   explicit FlutterWindow(const flutter::DartProject& project);
   virtual ~FlutterWindow();

  protected:
   bool OnCreate() override;
   void OnDestroy() override;
   LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                          LPARAM const lparam) noexcept override;

  private:
   flutter::DartProject project_;
-  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
 };
```

`flutter_controller_` is replaced entirely by the plugin. Leaving the field in the header will cause a compile error because `flutter::FlutterViewController` is no longer included.

**`windows/runner/flutter_window.cpp`**: replace the standard Flutter engine initialization with the multiview_desktop API:

```diff
 #include "flutter_window.h"
 #include <optional>
-#include "flutter/generated_plugin_registrant.h"
+#include <multiview_desktop/multi_view_desktop_plugin.h>

 FlutterWindow::FlutterWindow(const flutter::DartProject& project)
     : project_(project) {}

 bool FlutterWindow::OnCreate() {
   if (!Win32Window::OnCreate()) {
     return false;
   }

   RECT frame = GetClientArea();
+  const int width  = frame.right - frame.left;
+  const int height = frame.bottom - frame.top;

-  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
-      frame.right - frame.left, frame.bottom - frame.top, project_);
-  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
-    return false;
-  }
-  RegisterPlugins(flutter_controller_->engine());
-  SetChildContent(flutter_controller_->view()->GetNativeWindow());
-
-  flutter_controller_->engine()->SetNextFrameCallback([&]() {
-    this->Show();
-  });
-
-  flutter_controller_->ForceRedraw();
+  MultiViewDesktopPrepareEngine(project_, GetHandle());
+  MultiViewDesktopCreateMainView(GetHandle(), width, height);
+  const HWND flutter_hwnd =
+      MultiViewDesktopGetFlutterHwnd(MultiViewDesktopGetMainViewId());
+  if (flutter_hwnd != nullptr) {
+    SetChildContent(flutter_hwnd);
+  }
+  CenterOnScreen();
   return true;
 }
 
 void FlutterWindow::OnDestroy() {
-    if (flutter_controller_) {
-        flutter_controller_ = nullptr;
-    }
-
    Win32Window::OnDestroy();
 }

 LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                       WPARAM const wparam,
                                       LPARAM const lparam) noexcept {

-   if (flutter_controller_) {
-     std::optional<LRESULT> result =
-        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
-                lparam);
-     if (result) {
-        return *result;
-      }
-    }
-
-  switch (message) {
-  case WM_FONTCHANGE:
-  flutter_controller_->engine()->ReloadSystemFonts();
-  break;
-  }

+  LRESULT result = 0;
+
+  if (message == WM_FONTCHANGE) {
+    FlutterDesktopEngineReloadSystemFonts(MultiViewDesktopGetEngineRef());
+  }
+  if (MultiViewDesktopHandleWindowProc(hwnd, message, wparam, lparam, &result)) {
+    return result;
+  }

   return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
 }
```

**`windows/runner/main.cpp`**: disable quit-on-close for the primary window:

```diff
 FlutterWindow window(project);
- Win32Window::Point origin(10, 10);
- Win32Window::Size size(1280, 720);
+ Win32Window::Point origin(0, 0);
+ Win32Window::Size size(800, 600);
 if (!window.Create(L"my_app", origin, size)) {
   return EXIT_FAILURE;
 }
-window.SetQuitOnClose(true);
+window.SetQuitOnClose(false);
```

Setting `SetQuitOnClose(false)` prevents the process from terminating when the main OS window is closed. The library takes over shutdown control via `CloseMode`.

#### Optional: CenterOnScreen helper

The example `flutter_window.cpp` calls `CenterOnScreen()` right after the main view is created. This positions the window at the center of the monitor immediately at the native level, before Dart has a chance to apply `WindowOptions.alignment`. Without it the window appears at the origin coordinates passed to `Create` and is only repositioned later when the Dart side runs. If you prefer to let Dart handle positioning exclusively you can skip this step and remove the `CenterOnScreen()` call from `flutter_window.cpp`.

If you want the native pre-center, add the method to the standard Flutter template files:

**`windows/runner/win32_window.h`**: add the declaration inside the `public:` section:

```diff
   bool Create(const std::wstring& title, const Point& origin, const Size& size);

+  // Centers the window on the nearest monitor before the first frame.
+  void CenterOnScreen();

   bool Show();
```

**`windows/runner/win32_window.cpp`**: add the implementation after the `Create` definition:

```cpp
void Win32Window::CenterOnScreen() {
  if (!window_handle_) {
    return;
  }
  RECT rect{};
  GetWindowRect(window_handle_, &rect);
  const int width  = rect.right  - rect.left;
  const int height = rect.bottom - rect.top;
  const HMONITOR monitor =
      MonitorFromWindow(window_handle_, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFO);
  GetMonitorInfo(monitor, &monitor_info);
  const int x = monitor_info.rcWork.left +
                (monitor_info.rcWork.right - monitor_info.rcWork.left - width) / 2;
  const int y = monitor_info.rcWork.top +
                (monitor_info.rcWork.bottom - monitor_info.rcWork.top - height) / 2;
  SetWindowPos(window_handle_, nullptr, x, y, width, height,
               SWP_NOZORDER | SWP_NOACTIVATE);
}
```

`SWP_NOZORDER | SWP_NOACTIVATE` keeps the z-order unchanged and avoids stealing focus during initialization.

#### Windows platform limitations

- **`setBadgeLabel`, `setVisibleOnAllWorkspaces`, `hideFromCollection`.** macOS-only. Not available on Windows.
- **`setProgressBar`.** Supported on Windows via taskbar progress API.

---

### macOS setup

**`macos/Runner/MainFlutterWindow.swift`**: create the engine explicitly, call `MultiviewDesktopPlugin.prepareEngine`, and attach it to a `FlutterViewController`:

```diff
 import Cocoa
 import FlutterMacOS
+import multiview_desktop

 class MainFlutterWindow: NSWindow {
   override func awakeFromNib() {
+    let engine = FlutterEngine(
+        name: "main_flutter_engine",
+        project: nil,
+        allowHeadlessExecution: true
+    )
+    MultiviewDesktopPlugin.prepareEngine(engine, window: self)
+
+    let flutterViewController = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
-    let flutterViewController = FlutterViewController()
     let windowFrame = self.frame
     self.contentViewController = flutterViewController
     self.setFrame(windowFrame, display: false)

     RegisterGeneratedPlugins(registry: flutterViewController)
     super.awakeFromNib()
   }
 }
```

`MultiviewDesktopPlugin.prepareEngine` enables multi-view mode on the engine, hides the window before the first frame, and stores a reference to the main `NSWindow`. This must be called before `FlutterViewController` is created.

**`macos/Runner/AppDelegate.swift`**: forward the two lifecycle callbacks to the plugin:

```diff
 import Cocoa
 import FlutterMacOS
+import multiview_desktop

 @main
 class AppDelegate: FlutterAppDelegate {
   override func applicationShouldTerminateAfterLastWindowClosed(
       _ sender: NSApplication
   ) -> Bool {
-    return true
+    return MultiviewDesktopPlugin.applicationShouldTerminateAfterLastWindowClosed()
   }

+  override func applicationShouldHandleReopen(
+      _ sender: NSApplication,
+      hasVisibleWindows flag: Bool
+  ) -> Bool {
+    if MultiviewDesktopPlugin.applicationShouldHandleReopen(sender, hasVisibleWindows: flag) {
+      return true
+    }
+    return super.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
+  }

   override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
 }
```

`applicationShouldTerminateAfterLastWindowClosed` is driven by `CloseMode` set from Dart, so the plugin controls whether the app stays alive after all windows close.

`applicationShouldHandleReopen` allows the library to restore the last window when the user clicks the dock icon after all windows have been hidden (relevant when using `MacosPlatformParams.saveLastWindowToReopen`).

---

## Usage

### Entry point

Replace `runApp` with `runMultiApp`. The `home` widget is rendered in the main OS window:

```dart
import 'package:flutter/material.dart';
import 'package:multiview_desktop/multiview_desktop.dart';

void main() {
  runMultiApp(home: const MyApp());
}
```

`runMultiApp` calls `WidgetsFlutterBinding.ensureInitialized` internally, so you do not need to call it yourself.

#### globalScope

`globalScope` is an optional builder that wraps every OS window, including the main window and all secondary windows opened via `openWindow`. Use it to inject shared `InheritedWidget` providers, theme wrappers, or dependency-injection roots that every window needs access to:

```dart
void main() {
  runMultiApp(
    home: const MyApp(),
    globalScope: (child) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => SettingsService()),
      ],
      child: child,
    ),
  );
}
```

The `child` argument passed to the builder is the window content. The builder is called once per window, so each window gets its own scope instance but can still share the same underlying Dart objects if those objects are allocated outside the builder.

Without `globalScope`, providers or inherited widgets placed in the `home` widget tree are not visible to secondary windows, because each window has its own separate widget subtree.

Optional: pass a `MultiAppConfig` to tune startup behavior:

```dart
void main() {
  runMultiApp(
    home: const MyApp(),
    config: MultiAppConfig(
      generalParams: MultiPlatformParams(
        closeMode: CloseMode.cascade,
        enableDynamicAnchor: true,
      ),
      macosParams: MacosPlatformParams(
        saveLastWindowToReopen: true,
        closeAppAfterLastWindowClosed: false,
      ),
      globalWindowOptions: WindowOptions(
        size: const Size(1280, 720),
        minimumSize: const Size(800, 600),
        alignment: Alignment.center,
        titleBarStyle: TitleBarStyle.normal,
        title: 'My App',
      ),
    ),
  );
}
```

`globalWindowOptions` are merged into every new window. Per-window options passed to `openWindow` take priority.

---

### Open a window

Call `openWindow` from anywhere; you do not need a `BuildContext`:

```dart
// Open a window showing SettingsPage.
await openWindow(const SettingsPage());

// Open a window with custom options.
await openWindow(
  const DashboardPage(),
  options: WindowOptions(
    size: const Size(1024, 768),
    title: 'Dashboard',
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: false,
  ),
);
```

`openWindow` returns the integer view ID of the new window.

If you need the new window to know which window opened it, pass `parentContext`:

```dart
await openWindow(
  const DetailsPage(),
  parentContext: context,
);
```

Inside `DetailsPage`, retrieve the parent context:

```dart
final parentScope = ParentWindowScope.of(context);
final parentContext = parentScope.parentContext;
if (parentContext != null && parentContext.mounted) {
  final parentId = MultiViewDesktop.getIdByContext(parentContext);
}
```

---

### Window options

`WindowOptions` describes the initial state applied when a window is created. All fields are optional; omitted fields fall back to `globalWindowOptions` from `MultiAppConfig` or built-in defaults.

| Field | Type | Description |
|---|---|---|
| `size` | `Size?` | Initial content size in logical pixels. Default: 800x600. |
| `minimumSize` | `Size?` | Minimum size the user can resize to. |
| `maximumSize` | `Size?` | Maximum size the user can resize to. |
| `alignment` | `Alignment?` | Where to place the window on the display (default: `Alignment.center`). |
| `backgroundColor` | `Color?` | Native background color behind Flutter content. |
| `titleBarStyle` | `TitleBarStyle?` | `normal` or `hidden`. |
| `windowButtonVisibility` | `bool?` | Show or hide traffic-light / caption buttons when the bar is hidden. |
| `title` | `String?` | Native window title. |
| `fullScreen` | `bool?` | Start in full-screen mode. |
| `alwaysOnTop` | `bool?` | Float above other windows. |
| `hideAppFromTaskbar` | `bool?` | Hide the entire application from the dock / taskbar. |

---

### Window events

Mix `WindowListener` into a `State` to receive lifecycle events for the window that owns the widget. Registration and cleanup are automatic; no `addListener` or `removeListener` calls are needed:

```dart
class _MyPageState extends State<MyPage> with WindowListener {
  @override
  void onWindowFocus() {
    // The window gained keyboard focus.
    setState(() {});
  }

  @override
  void onWindowClose() {
    // The user pressed the close button or closeWindow was called.
    // If setPreventClose is true this fires instead of actually closing.
  }

  @override
  void onWindowMaximize() {}

  @override
  void onWindowUnmaximize() {}

  @override
  void onWindowMinimize() {}

  @override
  void onWindowRestore() {}

  @override
  void onWindowResize() {}

  @override
  void onWindowResized() {}   // macOS / Windows only, fires once when resize ends

  @override
  void onWindowMove() {}

  @override
  void onWindowMoved() {}     // macOS / Windows only, fires once when move ends

  @override
  void onWindowEnterFullScreen() {}

  @override
  void onWindowLeaveFullScreen() {}

  @override
  void onWindowEvent(String eventName) {
    // Every event by name; useful for logging or catching unlisted events.
  }
}
```

The mixin registers for the window resolved from `context` during `didChangeDependencies` and unregisters in `dispose`. The `currentId` getter provides the view ID if you need it:

```dart
print('This window id: $currentId');
```

To subscribe to events for a specific window by ID (without using the mixin):

```dart
MultiViewDesktop.addListenerForView(viewId, myCallbacks);
MultiViewDesktop.removeListenerForView(viewId, myCallbacks);
```

---

### Communication between windows

Because all windows share a single Dart isolate, you can pass any Dart object directly. The built-in `WindowCommunicator` provides a simple routing layer when you need to decouple senders from receivers.

Access it from anywhere:

```dart
final comm = MultiViewDesktop.communicator;
```

#### Direct messages

Send a message to a specific window by its view ID:

```dart
// Send from any window to window with id 2.
MultiViewDesktop.communicator.send(2, {'action': 'reload', 'tab': 'settings'});
```

Listen inside window 2:

```dart
// Subscribes to messages addressed to the window that owns context.
final sub = MultiViewDesktop.communicator.onDirect(context).listen((msg) {
  if (msg is Map && msg['action'] == 'reload') {
    setState(() { /* ... */ });
  }
});
// Cancel in dispose:
sub.cancel();
```

You can also listen for messages addressed to a different window by passing `viewId`:

```dart
// In window 1, listen for messages sent to window 3.
MultiViewDesktop.communicator.onDirect(context, viewId: 3).listen((msg) { /* ... */ });
```

#### Broadcast messages

Send a message to every subscribed view at once:

```dart
// In any window: announce a theme change to all views.
MultiViewDesktop.communicator.broadcast({'type': 'themeMode', 'value': 'dark'});
```

Subscribe in any view:

```dart
final sub = MultiViewDesktop.communicator.onBroadcast.listen((msg) {
  if (msg is Map && msg['type'] == 'themeMode') {
    applyTheme(msg['value']);
  }
});
sub.cancel(); // in dispose
```

#### Sharing state directly

For tightly coupled windows, sharing a `ChangeNotifier` or `ValueNotifier` directly is simpler than using the communicator:

```dart
// Defined once at the top level, accessible from every window.
final sharedTheme = ValueNotifier<ThemeMode>(ThemeMode.light);

// In any window:
sharedTheme.value = ThemeMode.dark;

// In any other window:
ValueListenableBuilder<ThemeMode>(
  valueListenable: sharedTheme,
  builder: (context, mode, _) => Text('Theme: $mode'),
);
```

---

### Confirm before closing

Enable close interception on the window and respond in `onWindowClose`:

```dart
class _MyPageState extends State<MyPage> with WindowListener {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MultiViewDesktop.of(context).setPreventClose(true);
    });
  }

  @override
  void onWindowClose() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Close window?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final win = MultiViewDesktop.of(context);
      await win.setPreventClose(false);
      await win.closeWindow();
    }
  }
}
```

---

### Close mode

`CloseMode` controls what happens to other open windows when the main window is closed.

Set it in `MultiAppConfig.generalParams.closeMode` at startup, or change it at runtime:

```dart
await MultiViewDesktop.setCloseMode(CloseMode.cascade);
```

| Mode | Behavior |
|---|---|
| `CloseMode.cascade` | Soft-close secondary windows one by one from newest to oldest, then soft-close the main window. Each window runs the full close cycle; use `cancelCascadeClose` inside `onWindowClose` to let the user abort. |
| `CloseMode.none` | Close only the main window. Secondary windows stay open. |
| `CloseMode.forceSecondary` | Force-close all secondary windows immediately, then soft-close the main window. |
| `CloseMode.destroy` | Force-close every window without running any close cycle. |

`CloseMode.cascade` is the default. It is the safest mode for apps that show unsaved-data dialogs, because each window gets a chance to respond before it is closed.

To abort a cascade close from inside a secondary window (for example after a user presses Cancel in a dialog):

```dart
@override
void onWindowClose() async {
  final confirmed = await showUnsavedChangesDialog();
  if (!confirmed) {
    await MultiViewDesktop.of(context).cancelCascadeClose();
  }
}
```

---

### Frameless windows

Pass `TitleBarStyle.hidden` to remove the native title bar. Then use `WindowCaption` or `DragToMoveArea` to let the user still drag the window.

#### Using WindowCaption

`WindowCaption` renders a 32 dp tall drag bar with an optional title widget. On Windows and Linux it also draws the minimize, maximize, and close buttons. On macOS the traffic-light buttons remain in their standard position.

```dart
@override
Widget build(BuildContext context) {
  return Column(
    children: [
      const WindowCaption(
        title: Text('My App'),
        backgroundColor: Color(0xFF1E1E1E),
        brightness: Brightness.dark,
      ),
      const Expanded(child: MyContent()),
    ],
  );
}
```

Set up the style when opening the window:

```dart
await openWindow(
  const MyPage(),
  options: WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    backgroundColor: Colors.transparent,
  ),
);
```

#### Using DragToMoveArea

For a fully custom layout, wrap any region with `DragToMoveArea` to make it draggable:

```dart
DragToMoveArea(
  child: Container(
    height: 48,
    color: Colors.blue,
    child: const Center(child: Text('Drag here to move')),
  ),
)
```

#### Resizable edges

Add `DragToResizeArea` widgets at each edge or corner to restore user resizing when the native frame has been removed:

```dart
Stack(
  children: [
    // Main content
    MyContent(),
    // Bottom-right resize handle
    Positioned(
      right: 0,
      bottom: 0,
      child: DragToResizeArea(
        resizeEdge: ResizeEdge.bottomRight,
        child: const SizedBox(width: 12, height: 12),
      ),
    ),
  ],
)
```

All eight edges and corners are available: `top`, `bottom`, `left`, `right`, `topLeft`, `topRight`, `bottomLeft`, `bottomRight`.

---

### Watching the window list

`MultiViewDesktop.allViewsIds` returns a snapshot list of all secondary view IDs currently open. `allViewsIdsNotifier` is a `ValueNotifier` updated every time a window opens or closes:

```dart
ValueListenableBuilder<List<int>>(
  valueListenable: MultiViewDesktop.allViewsIdsNotifier,
  builder: (context, ids, _) {
    return Text('Open secondary windows: ${ids.length}');
  },
)
```

---

### Window observers

`WindowObserver` lets you monitor window lifecycle events from one central place, without adding a `WindowListener` mixin to every widget. The design mirrors `NavigatorObserver` in Flutter: extend the class, override only the methods you need, and register the instance in `MultiAppConfig`.

```dart
class AppWindowObserver extends WindowObserver {
  @override
  void onWindowOpened(int viewId, {int? parentViewId}) {
    print('window $viewId opened (parent: $parentViewId)');
  }

  @override
  void onWindowClosed(int viewId) {
    print('window $viewId closed');
  }

  @override
  void onAnchorChanged(int? previousViewId, int? newViewId) {
    print('anchor changed: $previousViewId -> $newViewId');
  }

  @override
  void onWindowEvent(int viewId, String eventName) {
    // Receives every native event: focus, blur, maximize, resize, move, close, etc.
    // Useful for analytics or structured logging across all windows.
  }
}

void main() {
  runMultiApp(
    home: ...,
    config: MultiAppConfig(
      observers: [AppWindowObserver()],
    ),
  );
}
```

Multiple observers can be registered at once. All view IDs passed to the callbacks are the same public IDs as those returned by `MultiViewDesktop.getIdByContext` and `MultiViewDesktop.allViewsIds`.

`WindowObserver` and `WindowListener` serve different purposes:

- `WindowListener` is a mixin on `State` that reacts to events in a single widget's window, typically to update UI.
- `WindowObserver` is a global sink registered once, covering all windows. Use it for logging, analytics, or infrastructure concerns that span the entire application.

---

### Application config

`MultiAppConfig` is passed to `runMultiApp` once:

```dart
runMultiApp(
  home: const MyApp(),
  config: MultiAppConfig(
    generalParams: MultiPlatformParams(
      closeMode: CloseMode.cascade,
      enableDynamicAnchor: true,
    ),
    macosParams: MacosPlatformParams(
      saveLastWindowToReopen: true,
      closeAppAfterLastWindowClosed: false,
    ),
    globalWindowOptions: WindowOptions(
      size: const Size(1280, 720),
      title: 'My App',
    ),
    observers: [AppWindowObserver()],
  ),
);
```

`enableDynamicAnchor`: when `true`, the library automatically tracks which window becomes the "anchor" (the last window visible). The anchor ID is accessible via `MultiViewDesktop.getAnchorId()`.

`saveLastWindowToReopen` (macOS): when the user closes all windows and the app stays in the dock, re-opening from the dock icon restores the last window.

`closeAppAfterLastWindowClosed` (macOS): when `false` (the default), the process stays alive after the last window closes. The app icon remains in the dock. When `true`, the process terminates as soon as the last window closes.

---

## API

<!-- README_DOC_GEN -->

### MultiViewDesktop

Per-window methods are accessed through an instance obtained from a factory constructor:

```dart
final win = MultiViewDesktop.of(context);
await win.setTitle('My Window');
await win.closeWindow();

// Or by view ID:
await MultiViewDesktop.fromId(viewId).setAlwaysOnTop(true);
```

App-wide operations (not targeting a specific window) are static:

```dart
await MultiViewDesktop.closeApp();
MultiViewDesktop.addListenerForView(viewId, listener);
```

#### Identity (static)

##### getIdByContext(BuildContext context) -> int

Returns the shifted view ID of the window that owns `context`.

##### allViewsIds -> List\<int\>

Snapshot of all secondary view IDs currently registered.

##### allViewsIdsNotifier -> ValueNotifier\<List\<int\>\>

Live-updating notifier. Fires whenever a window opens or closes. Use with `ValueListenableBuilder`.

#### Identity (instance)

##### id -> int

The shifted (public) view ID for this instance.

#### App-wide lifecycle (static)

##### openWindow(Widget child, {WindowOptions? options, BuildContext? parentContext}) -> Future\<int\>

Opens a new OS window showing `child`. Returns the view ID. Available as a top-level function; can be called without `BuildContext`.

##### closeApp({CloseMode? closeMode}) -> Future\<void\>

Closes all windows using `closeMode` (or the mode configured in `MultiAppConfig`).

##### setCloseMode(CloseMode closeMode) -> Future\<void\>

Changes the strategy used when the main window close button is pressed.

##### getCloseMode() -> CloseMode

Returns the currently active close mode.

##### setAnchorId(int viewId) -> Future\<bool\>

Sets the anchor view ID manually. Only valid for root views (views without a parent).

##### getAnchorId() -> int?

Returns the current anchor view ID, or `null` if none is set.

#### Per-window lifecycle (instance)

##### closeWindow() -> Future\<void\>

Soft-closes this window. If `setPreventClose` is `true`, emits `onWindowClose` instead of destroying the window.

##### isPreventClose() -> Future\<bool\>

Returns whether close is currently blocked for this window.

##### setPreventClose(bool isPreventClose) -> Future\<void\>

When `true`, any close attempt (native button or `closeWindow`) is blocked and `onWindowClose` fires instead. Set back to `false` to re-enable.

##### cancelCascadeClose() -> Future\<void\>

Aborts an in-progress `CloseMode.cascade` sequence that is waiting on this window.

#### Title and appearance (instance)

##### getTitle() -> Future\<String\>

Returns the native window title.

##### setTitle(String title) -> Future\<void\>

Changes the native window title shown in the title bar and dock tooltip.

##### setTitleBarStyle(TitleBarStyle style, {bool windowButtonVisibility = true}) -> Future\<void\>

Changes the title-bar style. Pass `TitleBarStyle.hidden` for a frameless window. `windowButtonVisibility` controls whether the traffic-light / caption buttons are still drawn when the bar is hidden.

##### getTitleBarStyle() -> Future\<({TitleBarStyle? style, bool? buttonVisibility})\>

Returns the current title-bar style and button visibility.

##### setAsFrameless() -> Future\<void\>

Removes the native title bar and border entirely.

##### setBackgroundColor(Color color) -> Future\<void\>

Sets the native window background color behind the Flutter view. Use `Colors.transparent` for a transparent window.

##### setBrightness(Brightness brightness) -> Future\<void\>

Sets the preferred appearance of native chrome (light or dark).

##### setOpacity(double opacity) -> Future\<void\>

Sets window opacity in the range `0.0` (fully transparent) to `1.0` (fully opaque).

##### getOpacity() -> Future\<double\>

Returns the current window opacity.

##### hasShadow() -> Future\<bool\>

Returns whether the window draws a native drop shadow.

##### setHasShadow(bool value) -> Future\<void\>

Enables or disables the native drop shadow. No-op on Linux.

#### Size and position (instance)

##### getBounds() -> Future\<Rect\>

Returns the window frame in Flutter logical coordinates (position and size combined).

##### getSize() -> Future\<Size\>

Returns the content size in logical pixels.

##### getPosition() -> Future\<Offset\>

Returns the top-left position of the window.

##### setSize(Size size) -> Future\<void\>

Resizes the window to `size` in logical pixels.

##### setPosition(Offset position) -> Future\<void\>

Moves the window so its top-left corner is at `position`. Silent on Wayland (Linux).

##### center() -> Future\<void\>

Centers the window on the screen that contains the largest portion of it.

##### setAlignment(Alignment alignment) -> Future\<void\>

Positions the window using `alignment` on the display under the cursor. Silent on Wayland (Linux).

##### setMinimumSize(Size size) -> Future\<void\>

Sets the minimum size the user can resize the window to.

##### setMaximumSize(Size size) -> Future\<void\>

Sets the maximum size the user can resize the window to.

##### setAspectRatio(double ratio) -> Future\<void\>

Locks the content area to a fixed aspect ratio (`width / height`). Pass `0` to remove the constraint.

#### Visibility and focus (instance)

##### show() -> Future\<void\>

Shows the window if it was hidden.

##### hide() -> Future\<void\>

Hides the window without closing it.

##### isVisible() -> Future\<bool\>

Returns whether the window is currently visible.

##### focus() -> Future\<void\>

Brings the window to the front and gives it keyboard focus.

##### blur() -> Future\<void\>

Removes keyboard focus from the window.

##### isFocused() -> Future\<bool\>

Returns whether this window is the current focused window.

#### Maximize, minimize, full screen (instance)

##### isMaximized() -> Future\<bool\>

Returns whether the window is in the maximized state.

##### maximize({bool vertically = false}) -> Future\<void\>

Maximizes the window.

##### unmaximize() -> Future\<void\>

Restores the window from the maximized state.

##### isMinimized() -> Future\<bool\>

Returns whether the window is minimized to the dock or taskbar.

##### minimize() -> Future\<void\>

Minimizes the window.

##### restore() -> Future\<void\>

Restores the window from the minimized state.

##### isFullScreen() -> Future\<bool\>

Returns whether the window is in native full-screen mode.

##### setFullScreen(bool isFullScreen) -> Future\<void\>

Enters or exits native full-screen mode.

#### Resizability and movability (instance)

##### isResizable() -> Future\<bool\>

Returns whether the user can resize the window by dragging its edges.

##### setResizable(bool isResizable) -> Future\<void\>

Enables or disables user resizing.

##### isMovable() -> Future\<bool\>

Returns whether the window can be moved by dragging the title bar.

##### setMovable(bool isMovable) -> Future\<void\>

Enables or disables moving the window by dragging. On Linux this maps to `setResizable`.

##### isMinimizable() -> Future\<bool\>

Returns whether the minimize button is enabled.

##### setMinimizable(bool isMinimizable) -> Future\<void\>

Enables or disables the minimize button and action.

##### isMaximizable() -> Future\<bool\>

Returns whether the maximize / zoom button is enabled.

##### setMaximizable(bool isMaximizable) -> Future\<void\>

Enables or disables the maximize button and action.

##### isClosable() -> Future\<bool\>

Returns whether the close button is enabled.

##### setClosable(bool isClosable) -> Future\<void\>

Enables or disables the close button and native close action.

#### Always on top and taskbar

##### isAlwaysOnTop() -> Future\<bool\>  (instance)

Returns whether the window floats above normal application windows.

##### setAlwaysOnTop(bool isAlwaysOnTop) -> Future\<void\>  (instance)

Keeps the window above other windows. On Linux depends on compositor support.

##### isHideAppFromTaskbar() -> Future\<bool\>  (static)

Returns whether the application icon is hidden from the dock / taskbar (app-wide).

##### hideAppFromTaskbar(bool isHideAppFromTaskbar) -> Future\<void\>  (static)

Hides or shows the application icon in the dock / taskbar app-wide.

##### isHideAppTabFromTaskbar() -> Future\<bool\>  (instance)

Returns whether this specific window is hidden from the taskbar (Windows / Linux).

##### hideCurrentAppTabFromTaskbar(bool isHide) -> Future\<void\>  (instance)

Hides or shows this window in the taskbar (Windows / Linux).

#### Drag and resize (instance, used by widgets)

##### startDragging() -> Future\<void\>

Starts a native window-move drag session. Called automatically by `DragToMoveArea`.

##### startResizing(ResizeEdge edge) -> Future\<void\>

Starts a native window-resize drag session from `edge`. Called automatically by `DragToResizeArea`.

#### Mouse events (instance)

##### setIgnoreMouseEvents(bool ignore, {bool mouseMoveEvents = false}) -> Future\<void\>

When `ignore` is `true`, all mouse events pass through the window. If `mouseMoveEvents` is `true`, mouse move events still arrive despite `ignore` being set.

##### isIgnoreMouseEvents() -> Future\<({bool mouseMoveEvents, bool ignore})\>

Returns the current mouse pass-through state.

##### popUpWindowMenu() -> Future\<void\>

Shows the native window context menu at the current cursor position (macOS).

#### macOS-specific (instance)

##### isHideFromCollection() -> Future\<bool\>

Returns whether the window is excluded from Mission Control (macOS).

##### hideFromCollection(bool isHideFromCollection) -> Future\<void\>

Hides or shows the window in Mission Control and Expose (macOS).

##### isVisibleOnAllWorkspaces() -> Future\<bool\>

Returns whether the window is pinned to all Spaces (macOS).

##### setVisibleOnAllWorkspaces(bool visible, {bool visibleOnFullScreen = false}) -> Future\<void\>

Pins or unpins the window across all Spaces (macOS).

##### setBadgeLabel({String? label}) -> Future\<void\>

Sets the dock icon badge text for this window (macOS). Pass `null` to clear the badge.

#### Progress bar

##### setProgressBar(double progress) -> Future\<void\>

Sets the taskbar / dock progress indicator from `0.0` to `1.0`. App-wide on Windows. macOS shows progress in the dock.

---

### WindowListener

Mixin for `State`. Automatically registers for events of the window that owns the widget, and unregisters on `dispose`. Override only the callbacks you need; all have empty default implementations.

##### onWindowClose() -> void

Fires when the window is going to close (or when close is blocked by `setPreventClose`).

##### onWindowFocus() -> void

Fires when the window gains keyboard focus.

##### onWindowBlur() -> void

Fires when the window loses focus.

##### onWindowMaximize() -> void

Fires when the window is maximized.

##### onWindowUnmaximize() -> void

Fires when the window exits the maximized state.

##### onWindowMinimize() -> void

Fires when the window is minimized.

##### onWindowRestore() -> void

Fires when the window is restored from a minimized state.

##### onWindowResize() -> void

Fires continuously while the user drags the window edge.

##### onWindowResized() -> void

Fires once when the user finishes resizing. macOS and Windows only.

##### onWindowMove() -> void

Fires continuously while the user drags the window.

##### onWindowMoved() -> void

Fires once when the user finishes moving the window. macOS and Windows only.

##### onWindowEnterFullScreen() -> void

Fires when the window enters full-screen mode.

##### onWindowLeaveFullScreen() -> void

Fires when the window exits full-screen mode.

##### onWindowEvent(String eventName) -> void

Fires for every window event by name. Useful for logging or handling events not covered by the named callbacks.

##### currentId -> int?

The view ID that this listener is currently registered for.

---

### WindowObserver

Global observer for window lifecycle events across the entire application. Extend this class and override the callbacks you need. Register instances via `MultiAppConfig.observers`.

All view ID parameters are public (shifted) IDs, matching `MultiViewDesktop.getIdByContext` and `MultiViewDesktop.allViewsIds`.

##### onWindowOpened(int viewId, {int? parentViewId}) -> void

Called after a new OS window has been opened and its widget tree registered. `parentViewId` is the ID of the window that called `openWindow`, or `null` if no parent context was passed.

##### onWindowClosed(int viewId) -> void

Called after an OS window has been closed and its widget tree disposed.

##### onAnchorChanged(int? previousViewId, int? newViewId) -> void

Called when the anchor window changes. The anchor is the root window that receives app-level close events. Both arguments are `null` when no anchor exists (e.g. during shutdown).

##### onWindowEvent(int viewId, String eventName) -> void

Called for every native event delivered to the window. `eventName` values: `focus`, `blur`, `maximize`, `unmaximize`, `minimize`, `restore`, `resize`, `resized`, `move`, `moved`, `enter-full-screen`, `leave-full-screen`, `close`. Fires before individual `WindowListener` callbacks in the widget tree.

---

### WindowCommunicator

In-process message bus. Accessible via `MultiViewDesktop.communicator`.

Because all windows run in the same Dart isolate, messages are never serialized. `WindowCommunicator` is a thin routing layer that decouples senders from receivers. For simple shared state a shared `ValueNotifier` or `ChangeNotifier` is often more direct.

##### send(int viewId, dynamic message) -> void

Delivers `message` to every active listener registered for `viewId` via `onDirect`. If no one is listening the message is dropped silently.

##### broadcast(dynamic message) -> void

Delivers `message` to every active `onBroadcast` subscriber in every view simultaneously.

##### onDirect(BuildContext context, {int? viewId}) -> Stream\<dynamic\>

Returns a broadcast `Stream` of messages sent to `viewId` via `send`. When `viewId` is omitted, listens on the window that owns `context`.

##### onBroadcast -> Stream\<dynamic\>

A broadcast `Stream` that receives every message sent via `broadcast`. Subscribe in any view.

---

### WindowOptions

Initial configuration for a window. Passed to `openWindow` or set as `globalWindowOptions` in `MultiAppConfig`.

| Field | Type | Default | Description |
|---|---|---|---|
| `size` | `Size?` | 800x600 | Content size in logical pixels. |
| `minimumSize` | `Size?` | none | Minimum resizable size. |
| `maximumSize` | `Size?` | none | Maximum resizable size. |
| `alignment` | `Alignment?` | `Alignment.center` | Placement on the display. |
| `backgroundColor` | `Color?` | platform | Native background color. |
| `titleBarStyle` | `TitleBarStyle?` | `normal` | `normal` or `hidden`. |
| `windowButtonVisibility` | `bool?` | `true` | Show caption buttons when bar is hidden. |
| `title` | `String?` | none | Native window title. |
| `fullScreen` | `bool?` | `false` | Start in full-screen mode. |
| `alwaysOnTop` | `bool?` | `false` | Float above other windows. |
| `hideAppFromTaskbar` | `bool?` | `false` | Hide app from dock / taskbar. |

---

### MultiAppConfig

Passed to `runMultiApp` once.

##### generalParams -> MultiPlatformParams

Cross-platform parameters.

`closeMode` - the `CloseMode` used when the main window closes. Default: `CloseMode.cascade`.

`enableDynamicAnchor` - when `true`, automatically tracks the last visible window as the anchor. Default: `true`.

##### macosParams -> MacosPlatformParams

macOS-specific parameters.

`saveLastWindowToReopen` - restore the last window when the dock icon is clicked after all windows close. Default: `true`.

`closeAppAfterLastWindowClosed` - quit the process when the last window closes. Default: `false`.

##### globalWindowOptions -> WindowOptions

Default `WindowOptions` merged into every new window. Per-window options override these.

##### observers -> List\<WindowObserver\>

List of observers notified on window lifecycle events. See [WindowObserver](#windowobserver-1).

---

### CloseMode

Controls what happens to other windows when the main window close button is pressed.

##### cascade

Default. Soft-closes secondary windows one by one from newest to oldest, then soft-closes the main window. Each window runs through the full close cycle (prevent-close check, `onWindowClose`). Use `cancelCascadeClose` inside a confirmation dialog to let the user abort without losing unsaved work.

##### none

Closes only the main window. Secondary windows stay open.

##### forceSecondary

Force-closes all secondary windows immediately, then soft-closes the main window.

##### destroy

Force-closes every window without running any close cycle.

---

### Widgets

#### WindowCaption

A ready-made 32 dp tall custom title bar for frameless windows. Renders a `DragToMoveArea` and, on Windows and Linux, minimize / maximize / close buttons. On macOS the traffic-light buttons stay in their standard position; `WindowCaption` adds left padding so the title does not overlap them.

```dart
const WindowCaption(
  title: Text('My App'),
  backgroundColor: Color(0xFF2C2C2C),
  brightness: Brightness.dark,
)
```

| Field | Type | Description |
|---|---|---|
| `title` | `Widget?` | Widget shown in the title bar. |
| `backgroundColor` | `Color?` | Fill color for the bar area. |
| `brightness` | `Brightness?` | Foreground color for text and icons (`light` = dark icons, `dark` = white icons). Default: `Brightness.light`. |

#### DragToMoveArea

Wraps any widget and starts a native window-move session when the user drags on it.

```dart
DragToMoveArea(
  child: Container(height: 48, color: Colors.blueGrey),
)
```

Double-tap on the area is absorbed so it does not accidentally trigger maximize.

#### DragToResizeArea

Starts a native resize session from a specific edge or corner when the user drags on it. Place one instance per edge or corner you want to be resizable.

```dart
DragToResizeArea(
  resizeEdge: ResizeEdge.bottomRight,
  enableResizeEdge: true,   // optional: disable dynamically
  child: const SizedBox(width: 8, height: 8),
)
```

| `ResizeEdge` | Description |
|---|---|
| `top` | Top edge |
| `bottom` | Bottom edge |
| `left` | Left edge |
| `right` | Right edge |
| `topLeft` | Top-left corner |
| `topRight` | Top-right corner |
| `bottomLeft` | Bottom-left corner |
| `bottomRight` | Bottom-right corner |

<!-- README_DOC_GEN -->

---

## License

[MIT](./LICENSE)
