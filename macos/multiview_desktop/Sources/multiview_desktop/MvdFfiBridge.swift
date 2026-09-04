import Cocoa
import FlutterMacOS

// MVD FFI bridge: C ABI called from Dart `FfiBridge`.
// Dart UI isolate == AppKit main thread; no dispatch hop.

private let kStrCap = 8192

private let _rectBuf: UnsafeMutablePointer<Double> = {
    let p = UnsafeMutablePointer<Double>.allocate(capacity: 4)
    p.initialize(repeating: 0, count: 4)
    return p
}()

private let _strBuf: UnsafeMutablePointer<CChar> = {
    let p = UnsafeMutablePointer<CChar>.allocate(capacity: kStrCap)
    p.initialize(repeating: 0, count: kStrCap)
    return p
}()

private let _strBuf2: UnsafeMutablePointer<CChar> = {
    let p = UnsafeMutablePointer<CChar>.allocate(capacity: kStrCap)
    p.initialize(repeating: 0, count: kStrCap)
    return p
}()

private let _i32Buf: UnsafeMutablePointer<Int32> = {
    let p = UnsafeMutablePointer<Int32>.allocate(capacity: 8)
    p.initialize(repeating: 0, count: 8)
    return p
}()

private var _pendingMenu: [[String: Any]] = []

public typealias MvdEventCallback = @convention(c) (
    UnsafePointer<CChar>?, Int64, Int64
) -> Void

private var _eventCb: MvdEventCallback?
/// True after Dart has installed an FFI event sink at least once.
/// Used so teardown (`cb == nil`) does not fall back to MethodChannel.
private var _eventCbInstalled = false
private var _eventCbGeneration: UInt64 = 0

@_cdecl("mvd_set_event_callback")
public func mvdSetEventCallback(_ cb: MvdEventCallback?) {
    _eventCb = cb
    _eventCbGeneration += 1
    if cb != nil {
        _eventCbInstalled = true
    }
}

@_cdecl("mvd_event_callback_generation")
public func mvdEventCallbackGeneration() -> Int64 {
    Int64(_eventCbGeneration)
}

@_cdecl("mvd_detach_isolate_callbacks")
public func mvdDetachIsolateCallbacks(_ token: UnsafeMutableRawPointer?) {
    guard let token else { return }
    let gen = UInt64(UInt(bitPattern: OpaquePointer(token)))
    guard gen == _eventCbGeneration else { return }
    _eventCb = nil
    mvdSetScreenEventCallback(nil)
}

func mvdFfiEventsAttached() -> Bool {
    _eventCbInstalled
}

func mvdFfiTryEmit(_ name: String, viewId: Int64, arg: Int64) -> Bool {
    guard let cb = _eventCb else { return false }
    name.withCString { cstr in
        cb(cstr, viewId, arg)
    }
    return true
}

private func impl() -> MultiviewDesktopImpl { MultiviewDesktopImpl.shared }

private func win(_ id: Int64) -> NSWindow? { impl().windows[id] }

private func state(_ id: Int64) -> WindowState {
    if let s = impl().windowStates[id] { return s }
    let s = WindowState()
    impl().windowStates[id] = s
    return s
}

private func str1() -> String { String(cString: _strBuf) }
private func str2() -> String { String(cString: _strBuf2) }

private func writeStr(_ s: String) {
    let chars = Array(s.utf8CString)
    let n = min(chars.count, kStrCap)
    _strBuf.update(from: chars, count: n)
    _strBuf[kStrCap - 1] = 0
}

private func noop(_: Any?) {}

// MARK: - Buffers

@_cdecl("mvd_rect_buf_ptr")
public func mvdRectBufPtr() -> UnsafeMutablePointer<Double> { _rectBuf }

@_cdecl("mvd_str_buf_ptr")
public func mvdStrBufPtr() -> UnsafeMutablePointer<CChar> { _strBuf }

@_cdecl("mvd_str_buf2_ptr")
public func mvdStrBuf2Ptr() -> UnsafeMutablePointer<CChar> { _strBuf2 }

@_cdecl("mvd_i32_buf_ptr")
public func mvdI32BufPtr() -> UnsafeMutablePointer<Int32> { _i32Buf }

// MARK: - Create

@_cdecl("mvd_create_window")
public func mvdCreateWindow(
    _ token: Int64, _ w: Double, _ h: Double,
    _ buttons: Int32, _ hasPos: Int32, _ x: Double, _ y: Double,
    _ parentId: Int64
) -> Int64 {
    var args: [String: Any] = [
        "token": Int(token),
        "width": w,
        "height": h,
        "title": str1(),
        "titleBarStyle": str2(),
        "windowButtonVisibility": buttons != 0,
    ]
    if hasPos != 0 { args["position"] = ["x": x, "y": y] }
    if parentId >= 0 { args["parentId"] = parentId }
    return impl().createSecondaryWindow(args: args, result: noop)
}

@_cdecl("mvd_create_modal_dialog")
public func mvdCreateModalDialog(
    _ token: Int64, _ parentId: Int64, _ w: Double, _ h: Double,
    _ modal: Int32, _ buttons: Int32, _ hasPos: Int32, _ x: Double, _ y: Double
) -> Int64 {
    var args: [String: Any] = [
        "token": Int(token),
        "parentId": parentId,
        "width": w,
        "height": h,
        "modal": modal != 0,
        "title": str1(),
        "titleBarStyle": str2(),
        "windowButtonVisibility": buttons != 0,
    ]
    if hasPos != 0 { args["position"] = ["x": x, "y": y] }
    return impl().createModalDialogWindow(args: args, result: noop)
}

@_cdecl("mvd_complete_modal_dialog")
public func mvdCompleteModalDialog(_ viewId: Int64) {
    impl().completeModalDialogCreate(args: ["viewId": viewId], result: noop)
}

@_cdecl("mvd_create_popup")
public func mvdCreatePopup(_ token: Int64, _ parentId: Int64, _ w: Double, _ h: Double) -> Int64 {
    return impl().createPopupWindow(args: [
        "token": Int(token),
        "parentId": parentId,
        "width": w,
        "height": h,
    ], result: noop)
}

// MARK: - App

@_cdecl("mvd_check_exist")
public func mvdCheckExist(_ viewId: Int64) -> Int32 { win(viewId) != nil ? 1 : 0 }

@_cdecl("mvd_set_anchor_view_id")
public func mvdSetAnchorViewId(_ viewId: Int64) { impl().setAnchorViewId(viewId) }

@_cdecl("mvd_set_terminate_after_last")
public func mvdSetTerminateAfterLast(_ terminate: Int32) {
    impl().setTerminateAfterLastWindowClosed(terminate != 0)
}

@_cdecl("mvd_reply_terminate")
public func mvdReplyTerminate(_ terminate: Int32) {
    impl().replyToApplicationShouldTerminate(terminate: terminate != 0)
}

@_cdecl("mvd_set_has_taskbar_callback")
public func mvdSetHasTaskbarCallback(_ v: Int32) { impl().setHasTaskbarCallback(v != 0) }

@_cdecl("mvd_is_hide_app_from_taskbar")
public func mvdIsHideAppFromTaskbar() -> Int32 {
    NSApplication.shared.activationPolicy() == .accessory ? 1 : 0
}

@_cdecl("mvd_set_progress_bar")
public func mvdSetProgressBar(_ progress: Double) { impl().setProgressBar(progress) }

@_cdecl("mvd_taskbar_menu_clear")
public func mvdTaskbarMenuClear() { _pendingMenu.removeAll() }

@_cdecl("mvd_taskbar_menu_add")
public func mvdTaskbarMenuAdd(_ id: Int32) {
    var item: [String: Any] = ["id": Int(id), "title": str1()]
    let icon = str2()
    if !icon.isEmpty { item["icon"] = icon }
    _pendingMenu.append(item)
}

@_cdecl("mvd_taskbar_menu_commit")
public func mvdTaskbarMenuCommit() {
    impl().setTaskbarMenu(items: _pendingMenu)
    _pendingMenu.removeAll()
}

// MARK: - Frame / display

@_cdecl("mvd_get_frame")
public func mvdGetFrame(_ viewId: Int64) {
    guard let window = win(viewId) else {
        _rectBuf[0] = 0; _rectBuf[1] = 0; _rectBuf[2] = 0; _rectBuf[3] = 0
        return
    }
    let tl = window.frame.topLeft
    _rectBuf[0] = Double(tl.x)
    _rectBuf[1] = Double(tl.y)
    _rectBuf[2] = Double(window.frame.width)
    _rectBuf[3] = Double(window.frame.height)
}

@_cdecl("mvd_set_frame")
public func mvdSetFrame(_ viewId: Int64, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
    guard let window = win(viewId) else { return }
    let tolerance: CGFloat = 0.5
    let sizeChanged =
        abs(window.frame.width - CGFloat(w)) > tolerance ||
        abs(window.frame.height - CGFloat(h)) > tolerance
    var f = window.frame
    if sizeChanged {
        f.size = NSSize(width: CGFloat(w), height: CGFloat(h))
        f.topLeft = CGPoint(x: CGFloat(x), y: CGFloat(y))
        window.setFrame(f, display: false)
    } else {
        f.topLeft = CGPoint(x: CGFloat(x), y: CGFloat(y))
        window.setFrameOrigin(f.origin)
    }
}

@_cdecl("mvd_get_physical_frame")
public func mvdGetPhysicalFrame(_ viewId: Int64) {
    guard let window = win(viewId) else {
        _rectBuf[0] = 0; _rectBuf[1] = 0; _rectBuf[2] = 0; _rectBuf[3] = 0
        return
    }
    let scale = Double(window.backingScaleFactor)
    let tl = window.frame.topLeft
    _rectBuf[0] = Double(tl.x) * scale
    _rectBuf[1] = Double(tl.y) * scale
    _rectBuf[2] = Double(window.frame.width) * scale
    _rectBuf[3] = Double(window.frame.height) * scale
}

@_cdecl("mvd_set_physical_frame")
public func mvdSetPhysicalFrame(_ viewId: Int64, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
    guard let window = win(viewId) else { return }
    let scale = Double(window.screen?.backingScaleFactor ?? window.backingScaleFactor)
    if scale <= 0 { return }
    mvdSetFrame(viewId, x / scale, y / scale, w / scale, h / scale)
}

@_cdecl("mvd_get_display_rect")
public func mvdGetDisplayRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
    let screens = NSScreen.screens
    guard let primary = screens.first else {
        _rectBuf[0] = 0; _rectBuf[1] = 0; _rectBuf[2] = 2560; _rectBuf[3] = 1440
        return
    }
    let ph = primary.frame.height
    let nsY = ph - CGFloat(y) - CGFloat(h)
    let query = NSRect(x: CGFloat(x), y: nsY, width: CGFloat(w), height: CGFloat(h))
    var best: NSScreen = NSScreen.main ?? screens[0]
    var bestArea: CGFloat = -1
    for screen in screens {
        let overlap = screen.frame.intersection(query)
        if !overlap.isNull {
            let area = overlap.width * overlap.height
            if area > bestArea { bestArea = area; best = screen }
        }
    }
    let vf = best.visibleFrame
    _rectBuf[0] = Double(vf.minX)
    _rectBuf[1] = Double(ph - vf.maxY)
    _rectBuf[2] = Double(vf.width)
    _rectBuf[3] = Double(vf.height)
}

@_cdecl("mvd_set_size")
public func mvdSetSize(_ viewId: Int64, _ w: Double, _ h: Double) {
    guard let window = win(viewId) else { return }
    var f = window.frame
    let topLeft = f.topLeft
    f.size = NSSize(width: CGFloat(w), height: CGFloat(h))
    f.topLeft = topLeft
    window.setFrame(f, display: true)
}

@_cdecl("mvd_set_position")
public func mvdSetPosition(_ viewId: Int64, _ x: Double, _ y: Double) {
    guard let window = win(viewId) else { return }
    var f = window.frame
    f.topLeft = CGPoint(x: CGFloat(x), y: CGFloat(y))
    window.setFrameOrigin(f.origin)
}

@_cdecl("mvd_set_min_size")
public func mvdSetMinSize(_ viewId: Int64, _ w: Double, _ h: Double) {
    win(viewId)?.minSize = NSSize(width: w, height: h)
}

@_cdecl("mvd_get_min_size")
public func mvdGetMinSize(_ viewId: Int64) {
    guard let window = win(viewId) else {
        _rectBuf[0] = 0; _rectBuf[1] = 0; _rectBuf[2] = 0; _rectBuf[3] = 0
        return
    }
    _rectBuf[0] = Double(window.minSize.width)
    _rectBuf[1] = Double(window.minSize.height)
    _rectBuf[2] = 0
    _rectBuf[3] = 0
}

@_cdecl("mvd_set_max_size")
public func mvdSetMaxSize(_ viewId: Int64, _ w: Double, _ h: Double) {
    win(viewId)?.maxSize = NSSize(width: w, height: h)
}

@_cdecl("mvd_get_max_size")
public func mvdGetMaxSize(_ viewId: Int64) {
    guard let window = win(viewId) else {
        _rectBuf[0] = 0; _rectBuf[1] = 0; _rectBuf[2] = 0; _rectBuf[3] = 0
        return
    }
    _rectBuf[0] = Double(window.maxSize.width)
    _rectBuf[1] = Double(window.maxSize.height)
    _rectBuf[2] = 0
    _rectBuf[3] = 0
}

// MARK: - Appearance / chrome

@_cdecl("mvd_set_background_color")
public func mvdSetBackgroundColor(_ viewId: Int64, _ a: Int32, _ r: Int32, _ g: Int32, _ b: Int32) {
    guard let window = win(viewId) else { return }
    let color = NSColor(
        calibratedRed: CGFloat(r) / 255,
        green: CGFloat(g) / 255,
        blue: CGFloat(b) / 255,
        alpha: CGFloat(a) / 255
    )
    window.backgroundColor = color
    if a < 255 { window.isOpaque = false }
    if let flutterVC = window.contentViewController as? FlutterViewController {
        flutterVC.backgroundColor = color
    }
}

@_cdecl("mvd_set_title")
public func mvdSetTitle(_ viewId: Int64) { win(viewId)?.title = str1() }

@_cdecl("mvd_get_title")
public func mvdGetTitle(_ viewId: Int64) -> Int32 {
    guard let window = win(viewId) else { return 0 }
    writeStr(window.title)
    return 1
}

@_cdecl("mvd_set_title_bar_style")
public func mvdSetTitleBarStyle(_ viewId: Int64, _ closeV: Int32, _ maxV: Int32, _ minV: Int32) {
    guard let window = win(viewId) else { return }
    if str1() == "hidden" {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
    } else {
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.styleMask.remove(.fullSizeContentView)
    }
    window.isOpaque = false
    window.hasShadow = true
    if let titleBarView = window.standardWindowButton(.closeButton)?.superview?.superview {
        titleBarView.isHidden = false
    }
    window.standardWindowButton(.closeButton)?.isHidden = closeV == 0
    window.standardWindowButton(.miniaturizeButton)?.isHidden = minV == 0
    window.standardWindowButton(.zoomButton)?.isHidden = maxV == 0
}

@_cdecl("mvd_get_title_bar_style")
public func mvdGetTitleBarStyle(_ viewId: Int64) -> Int32 {
    guard let window = win(viewId) else { return 0 }
    writeStr(window.titleVisibility == .hidden ? "hidden" : "normal")
    _i32Buf[0] = (window.standardWindowButton(.closeButton)?.isHidden ?? true) ? 0 : 1
    _i32Buf[2] = (window.standardWindowButton(.miniaturizeButton)?.isHidden ?? true) ? 0 : 1
    _i32Buf[1] = (window.standardWindowButton(.zoomButton)?.isHidden ?? true) ? 0 : 1
    return 1
}

@_cdecl("mvd_set_as_frameless")
public func mvdSetAsFrameless(_ viewId: Int64) {
    guard let window = win(viewId) else { return }
    window.styleMask.insert(.fullSizeContentView)
    window.titleVisibility = .hidden
    window.isOpaque = true
    window.hasShadow = false
    window.backgroundColor = NSColor.clear
    if window.styleMask.contains(.titled),
       let titleBarView = window.standardWindowButton(.closeButton)?.superview?.superview {
        titleBarView.isHidden = true
    }
    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
}

@_cdecl("mvd_set_brightness")
public func mvdSetBrightness(_ viewId: Int64) {
    win(viewId)?.appearance = NSAppearance(named: str1() == "dark" ? .darkAqua : .aqua)
}

@_cdecl("mvd_set_opacity")
public func mvdSetOpacity(_ viewId: Int64, _ opacity: Double) {
    guard let window = win(viewId) else { return }
    let v = CGFloat(opacity)
    state(viewId).opacity = v
    window.alphaValue = v
}

@_cdecl("mvd_get_opacity")
public func mvdGetOpacity(_ viewId: Int64) -> Double {
    guard let window = win(viewId) else { return 1.0 }
    return Double(impl().windowStates[viewId]?.opacity ?? window.alphaValue)
}

@_cdecl("mvd_has_shadow")
public func mvdHasShadow(_ viewId: Int64) -> Int32 { (win(viewId)?.hasShadow ?? true) ? 1 : 0 }

@_cdecl("mvd_set_has_shadow")
public func mvdSetHasShadow(_ viewId: Int64, _ v: Int32) { win(viewId)?.hasShadow = v != 0 }

@_cdecl("mvd_set_aspect_ratio")
public func mvdSetAspectRatio(_ viewId: Int64, _ ratio: Double) {
    guard let window = win(viewId) else { return }
    if ratio > 0 {
        window.resizeIncrements = NSSize(width: ratio, height: 1.0)
//        window.aspectRatio = NSSize(width: ratio, height: 1)
    } else {
        window.resizeIncrements = NSSize(width: 1, height: 1)
    }
}

@_cdecl("mvd_set_badge_label")
public func mvdSetBadgeLabel(_ viewId: Int64) {
    NSApp.dockTile.badgeLabel = str1()
}

// MARK: - Lifecycle

@_cdecl("mvd_close_window")
public func mvdCloseWindow(_ viewId: Int64) {
    guard let window = win(viewId) else { return }
    if impl().windowStates[viewId]?.isPopup == true {
        impl().closePopupWindow(window, viewId: viewId)
    } else {
        impl().requestSoftClose(viewId: viewId, window: window)
    }
}

@_cdecl("mvd_destroy_window")
public func mvdDestroyWindow(_ viewId: Int64) {
    guard let window = win(viewId) else { return }
    if impl().windowStates[viewId]?.isPopup == true {
        impl().closePopupWindow(window, viewId: viewId)
    } else {
        impl().closeSheetWindow(window, viewId: viewId)
    }
}

@_cdecl("mvd_show")
public func mvdShow(_ viewId: Int64) {
    guard let window = win(viewId) else { return }
    if impl().windowStates[viewId]?.isPopup == true {
        impl().showPopupWindow(window, viewId: viewId)
    } else {
        impl().focusWindow(window)
    }
}

@_cdecl("mvd_hide")
public func mvdHide(_ viewId: Int64) {
    guard let window = win(viewId) else { return }
    if impl().windowStates[viewId]?.isPopup == true {
        impl().hidePopupWindow(window, viewId: viewId)
    } else {
        window.orderOut(nil)
    }
}

@_cdecl("mvd_is_visible")
public func mvdIsVisible(_ viewId: Int64) -> Int32 { (win(viewId)?.isVisible ?? true) ? 1 : 0 }

@_cdecl("mvd_focus")
public func mvdFocus(_ viewId: Int64) {
    guard let window = win(viewId) else { return }
    impl().focusWindow(window)
}

@_cdecl("mvd_blur")
public func mvdBlur(_ viewId: Int64) { win(viewId)?.resignKey() }

@_cdecl("mvd_is_focused")
public func mvdIsFocused(_ viewId: Int64) -> Int32 {
    guard let window = win(viewId) else { return 0 }
    return impl().isWindowFocused(window) ? 1 : 0
}

@_cdecl("mvd_is_on_active_space")
public func mvdIsOnActiveSpace(_ viewId: Int64) -> Int32 {
    (win(viewId)?.isOnActiveSpace ?? true) ? 1 : 0
}

@_cdecl("mvd_set_pre_confirm")
public func mvdSetPreConfirm(_ viewId: Int64, _ v: Int32) { state(viewId).isPreConfirm = v != 0 }

@_cdecl("mvd_set_confirm")
public func mvdSetConfirm(_ viewId: Int64, _ v: Int32) { state(viewId).isConfirmClose = v != 0 }

@_cdecl("mvd_set_prevent_close")
public func mvdSetPreventClose(_ viewId: Int64, _ v: Int32) { state(viewId).isPreventClose = v != 0 }

@_cdecl("mvd_is_prevent_close")
public func mvdIsPreventClose(_ viewId: Int64) -> Int32 {
    (impl().windowStates[viewId]?.isPreventClose ?? false) ? 1 : 0
}

// MARK: - Window state

@_cdecl("mvd_maximize")
public func mvdMaximize(_ viewId: Int64, _ vertically: Int32) {
    guard let window = win(viewId), !window.isZoomed else { return }
    window.zoom(nil)
}

@_cdecl("mvd_unmaximize")
public func mvdUnmaximize(_ viewId: Int64) {
    guard let window = win(viewId), window.isZoomed else { return }
    window.zoom(nil)
}

@_cdecl("mvd_is_maximized")
public func mvdIsMaximized(_ viewId: Int64) -> Int32 { (win(viewId)?.isZoomed ?? false) ? 1 : 0 }

@_cdecl("mvd_minimize")
public func mvdMinimize(_ viewId: Int64) { win(viewId)?.miniaturize(nil) }

@_cdecl("mvd_restore")
public func mvdRestore(_ viewId: Int64) { win(viewId)?.deminiaturize(nil) }

@_cdecl("mvd_is_minimized")
public func mvdIsMinimized(_ viewId: Int64) -> Int32 { (win(viewId)?.isMiniaturized ?? false) ? 1 : 0 }

@_cdecl("mvd_set_full_screen")
public func mvdSetFullScreen(_ viewId: Int64, _ v: Int32) {
    guard let window = win(viewId) else { return }
    if (v != 0) != window.styleMask.contains(.fullScreen) {
        window.toggleFullScreen(nil)
    }
}

@_cdecl("mvd_is_full_screen")
public func mvdIsFullScreen(_ viewId: Int64) -> Int32 {
    (win(viewId)?.styleMask.contains(.fullScreen) ?? false) ? 1 : 0
}

@_cdecl("mvd_is_resizable")
public func mvdIsResizable(_ viewId: Int64) -> Int32 {
    (win(viewId)?.styleMask.contains(.resizable) ?? true) ? 1 : 0
}

@_cdecl("mvd_set_resizable")
public func mvdSetResizable(_ viewId: Int64, _ v: Int32) {
    guard let window = win(viewId) else { return }
    if v != 0 { window.styleMask.insert(.resizable) } else { window.styleMask.remove(.resizable) }
}

@_cdecl("mvd_is_movable")
public func mvdIsMovable(_ viewId: Int64) -> Int32 { (win(viewId)?.isMovable ?? true) ? 1 : 0 }

@_cdecl("mvd_set_movable")
public func mvdSetMovable(_ viewId: Int64, _ v: Int32) { win(viewId)?.isMovable = v != 0 }

@_cdecl("mvd_is_minimizable")
public func mvdIsMinimizable(_ viewId: Int64) -> Int32 {
    (win(viewId)?.styleMask.contains(.miniaturizable) ?? true) ? 1 : 0
}

@_cdecl("mvd_set_minimizable")
public func mvdSetMinimizable(_ viewId: Int64, _ v: Int32) {
    guard let window = win(viewId) else { return }
    if v != 0 { window.styleMask.insert(.miniaturizable) } else { window.styleMask.remove(.miniaturizable) }
}

@_cdecl("mvd_is_maximizable")
public func mvdIsMaximizable(_ viewId: Int64) -> Int32 {
    (win(viewId)?.standardWindowButton(.zoomButton)?.isEnabled ?? true) ? 1 : 0
}

@_cdecl("mvd_set_maximizable")
public func mvdSetMaximizable(_ viewId: Int64, _ v: Int32) {
    win(viewId)?.standardWindowButton(.zoomButton)?.isEnabled = v != 0
}

@_cdecl("mvd_is_closable")
public func mvdIsClosable(_ viewId: Int64) -> Int32 {
    (win(viewId)?.styleMask.contains(.closable) ?? true) ? 1 : 0
}

@_cdecl("mvd_set_closable")
public func mvdSetClosable(_ viewId: Int64, _ v: Int32) {
    guard let window = win(viewId) else { return }
    if v != 0 { window.styleMask.insert(.closable) } else { window.styleMask.remove(.closable) }
}

@_cdecl("mvd_is_always_on_top")
public func mvdIsAlwaysOnTop(_ viewId: Int64) -> Int32 {
    (win(viewId)?.level == .floating) ? 1 : 0
}

@_cdecl("mvd_set_always_on_top")
public func mvdSetAlwaysOnTop(_ viewId: Int64, _ v: Int32) {
    win(viewId)?.level = v != 0 ? .floating : .normal
}

@_cdecl("mvd_hide_app_from_taskbar")
public func mvdHideAppFromTaskbar(_ viewId: Int64, _ v: Int32) {
    NSApplication.shared.setActivationPolicy(v != 0 ? .accessory : .regular)
}

@_cdecl("mvd_is_hide_app_tab_from_taskbar")
public func mvdIsHideAppTabFromTaskbar(_ viewId: Int64) -> Int32 { 0 }

@_cdecl("mvd_is_hide_from_collection")
public func mvdIsHideFromCollection(_ viewId: Int64) -> Int32 {
    (win(viewId)?.collectionBehavior.contains(.ignoresCycle) ?? false) ? 1 : 0
}

@_cdecl("mvd_hide_from_collection")
public func mvdHideFromCollection(_ viewId: Int64, _ v: Int32) {
    guard let window = win(viewId) else { return }
    if v != 0 {
        window.collectionBehavior.insert(.ignoresCycle)
        window.collectionBehavior.insert(.transient)
    } else {
        window.collectionBehavior.remove(.ignoresCycle)
        window.collectionBehavior.remove(.transient)
    }
}

@_cdecl("mvd_is_visible_on_all_workspaces")
public func mvdIsVisibleOnAllWorkspaces(_ viewId: Int64) -> Int32 {
    (win(viewId)?.collectionBehavior.contains(.canJoinAllSpaces) ?? false) ? 1 : 0
}

@_cdecl("mvd_set_visible_on_all_workspaces")
public func mvdSetVisibleOnAllWorkspaces(_ viewId: Int64, _ visible: Int32, _ onFs: Int32) {
    guard let window = win(viewId) else { return }
    if visible != 0 {
        window.collectionBehavior.insert(.canJoinAllSpaces)
        if onFs != 0 { window.collectionBehavior.insert(.fullScreenAuxiliary) }
    } else {
        window.collectionBehavior.remove(.canJoinAllSpaces)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
    }
}

@_cdecl("mvd_set_ignore_mouse_events")
public func mvdSetIgnoreMouseEvents(_ viewId: Int64, _ ignore: Int32, _ forward: Int32) {
    guard let window = win(viewId) else { return }
    window.ignoresMouseEvents = ignore != 0
    window.acceptsMouseMovedEvents = ignore != 0 && forward != 0
}

@_cdecl("mvd_is_ignore_mouse_events")
public func mvdIsIgnoreMouseEvents(_ viewId: Int64) -> Int32 {
    guard let window = win(viewId) else {
        _i32Buf[0] = 0
        return 0
    }
    let ignore = window.ignoresMouseEvents
    _i32Buf[0] = (window.acceptsMouseMovedEvents && ignore) ? 1 : 0
    return ignore ? 1 : 0
}

@_cdecl("mvd_start_dragging")
public func mvdStartDragging(_ viewId: Int64) {
    guard let window = win(viewId), let event = NSApp.currentEvent else { return }
    window.performDrag(with: event)
}

@_cdecl("mvd_start_resizing")
public func mvdStartResizing(_ viewId: Int64, _ t: Int32, _ b: Int32, _ l: Int32, _ r: Int32) {
    // Channel path is a TODO on macOS.
}

@_cdecl("mvd_pop_up_window_menu")
public func mvdPopUpWindowMenu(_ viewId: Int64) {
    guard let window = win(viewId),
          let contentView = window.contentView,
          let event = NSApp.currentEvent
    else { return }
    let menu = NSMenu()
    if window.styleMask.contains(.miniaturizable) {
        menu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: ""))
    }
    menu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
    if window.styleMask.contains(.closable) {
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: ""))
    }
    NSMenu.popUpContextMenu(menu, with: event, for: contentView)
}
