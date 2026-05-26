import Cocoa
import FlutterMacOS

// MARK: - NSRect coordinate helpers

/// Extends NSRect with a `topLeft` property that converts between Cocoa
/// (Y-up, origin at bottom-left of primary screen) and Flutter/logical
/// (Y-down, origin at top-left of primary screen) coordinate spaces.
///
/// The getter returns the Flutter top-left point for the rect.
/// The setter moves the rect so that its top-left corner is at the given
/// Flutter point, picking the best target screen by overlap area.
extension NSRect {
    var topLeft: CGPoint {
        get {
            func overlapArea(_ r: CGRect) -> CGFloat {
                if r.isNull || r.isEmpty { return 0 }
                return r.width * r.height
            }
            let screens = NSScreen.screens
            let targetScreen: NSScreen? = screens.max {
                overlapArea(self.intersection($0.frame)) < overlapArea(self.intersection($1.frame))
            } ?? NSScreen.main ?? screens.first
            let sf = targetScreen?.frame
                ?? NSScreen.main?.frame
                ?? NSScreen.screens.first?.frame
                ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
            return CGPoint(x: origin.x, y: sf.maxY - origin.y - size.height)
        }
        set {
            func overlapArea(_ r: CGRect) -> CGFloat {
                if r.isNull || r.isEmpty { return 0 }
                return r.width * r.height
            }
            let screens = NSScreen.screens
            // Pick the screen that would contain the most of the window after the move.
            let targetScreen: NSScreen? = screens.max {
                let o0 = CGPoint(x: newValue.x, y: $0.frame.maxY - newValue.y - size.height)
                let o1 = CGPoint(x: newValue.x, y: $1.frame.maxY - newValue.y - size.height)
                return overlapArea(CGRect(origin: o0, size: size).intersection($0.frame))
                     < overlapArea(CGRect(origin: o1, size: size).intersection($1.frame))
            } ?? NSScreen.main ?? screens.first
            let sf = targetScreen?.frame
                ?? NSScreen.main?.frame
                ?? NSScreen.screens.first?.frame
                ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
            origin.x = newValue.x
            origin.y = sf.maxY - newValue.y - size.height
        }
    }
}

// MARK: - Per-window state

private class WindowState {
    var isPreventClose: Bool = false
    var isConfirmClose: Bool = false
    var isMaximized: Bool = false
    var isMainPreConfirm: Bool = false
}

// MARK: - MultiviewDesktopImpl

/// Singleton that owns the shared Flutter engine, all OS windows, and the
/// single `multiview_desktop` method channel.
class MultiviewDesktopImpl: NSObject, NSWindowDelegate {

    static let shared = MultiviewDesktopImpl()

    weak var engine: FlutterEngine?

    // Temporary main NSWindow reference stored during prepareEngine(_:),
    // consumed in register(with:) once the viewIdentifier is available.
    var mainWindowRef: NSWindow?

    // All managed OS windows keyed by FlutterViewIdentifier.
    var windows: [Int64: NSWindow] = [:]

    private var windowStates: [Int64: WindowState] = [:]
    private var channel: FlutterMethodChannel?

    // MARK: - Channel setup

    func setup(messenger: FlutterBinaryMessenger) {
        let ch = FlutterMethodChannel(
            name: "multiview_desktop",
            binaryMessenger: messenger
        )
        ch.setMethodCallHandler { [weak self] call, result in
            self?.handle(call: call, result: result)
        }
        channel = ch
    }

    // MARK: - Window registration

    func registerWindow(_ window: NSWindow, viewId: Int64) {
        windows[viewId] = window
        windowStates[viewId] = WindowState()
        window.delegate = self
    }

    // MARK: - Channel handler

    private func handle(call: FlutterMethodCall, result: FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        case "createWindow":
            createSecondaryWindow(args: args, result: result)
        default:
            let viewId = int64(from: args, key: "viewId")
            if let window = windows[viewId] {
                handleViewMethod(call: call, result: result, window: window, viewId: viewId)
            } else {
                result(FlutterError(
                    code: "NO_WINDOW",
                    message: "No window for viewId \(viewId)",
                    details: nil
                ))
            }
        }
    }

    // MARK: - Secondary window creation

    private func createSecondaryWindow(args: [String: Any], result: FlutterResult) {
        guard let engine else {
            result(FlutterError(code: "NO_ENGINE", message: "Engine not available", details: nil))
            return
        }

        let token = args["token"] as? Int ?? 0
        let width = args["width"] as? CGFloat ?? 800
        let height = args["height"] as? CGFloat ?? 600
        let title = args["title"] as? String ?? ""
        let position = args["position"] as? [String: Any]
        let titleBarStyleName = args["titleBarStyle"] as? String ?? "normal"
        let windowButtonVisibility = args["windowButtonVisibility"] as? Bool ?? true

        let newController = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        let viewId = newController.viewIdentifier

        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        if titleBarStyleName == "hidden" {
            styleMask = windowButtonVisibility
                ? [.fullSizeContentView, .closable, .miniaturizable, .resizable]
                : [.fullSizeContentView, .resizable]
        }

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        newWindow.contentViewController = newController
        // contentViewController assignment resets the window size to the VC's
        // initial frame; restore the requested size.
        newWindow.setContentSize(NSSize(width: width, height: height))
        newWindow.title = title
        newWindow.isReleasedWhenClosed = false

        if titleBarStyleName == "hidden" {
            newWindow.titleVisibility = .hidden
            newWindow.titlebarAppearsTransparent = true
        }

        if let position,
           let x = cgFloat(from: position["x"]),
           let y = cgFloat(from: position["y"]) {
            var frameRect = newWindow.frame
            frameRect.topLeft = CGPoint(x: x, y: y)
            newWindow.setFrameOrigin(frameRect.origin)
        } else {
            newWindow.center()
        }

        registerWindow(newWindow, viewId: viewId)

        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)

        DispatchQueue.main.async { [weak self] in
            self?.channel?.invokeMethod(
                "onEvent",
                arguments: ["eventName": "viewCreated", "viewId": Int(viewId), "token": token]
            )
        }

        result(nil)
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let viewId = viewIdForWindow(sender) else {
            return true
        }
        let state = windowStates[viewId] ?? WindowState()

        if viewId == 1 && !state.isMainPreConfirm {
            emitEvent("main-preconfirm-close", viewId: viewId)
            return false
        }

        if state.isPreventClose {
            emitEvent("close", viewId: viewId)
            return false
        }

        if !state.isConfirmClose {
            emitEvent("confirm-close", viewId: viewId)
            return false
        }

        // emitEvent("close", viewId: viewId)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              let viewId = viewIdForWindow(closingWindow)
        else {
            return
        }

        windows.removeValue(forKey: viewId)
        windowStates.removeValue(forKey: viewId)
        closingWindow.delegate = nil
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        guard let viewId = viewIdForWindow(window) else {
            return true
        }
        emitEvent("maximize", viewId: viewId)
        return true
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window),
              let state = windowStates[viewId]
        else {
            return
        }

        emitEvent("resize", viewId: viewId)

        if !state.isMaximized && window.isZoomed {
            state.isMaximized = true
            emitEvent("maximize", viewId: viewId)
        }
        if state.isMaximized && !window.isZoomed {
            state.isMaximized = false
            emitEvent("unmaximize", viewId: viewId)
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("resized", viewId: viewId)
    }

    func windowWillMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("move", viewId: viewId)
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("moved", viewId: viewId)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("focus", viewId: viewId)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("blur", viewId: viewId)
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("minimize", viewId: viewId)
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("restore", viewId: viewId)
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("enter-full-screen", viewId: viewId)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let viewId = viewIdForWindow(window)
        else {
            return
        }
        emitEvent("leave-full-screen", viewId: viewId)
    }

    // MARK: - Per-view method handler

    private func handleViewMethod(
        call: FlutterMethodCall,
        result: FlutterResult,
        window: NSWindow,
        viewId: Int64
    ) {
        let args = call.arguments as? [String: Any]
        let state = windowStates[viewId] ?? WindowState()

        switch call.method {

        case "closeWindow":
            window.performClose(nil)
            result(nil)

        case "isPreventClose":
            result(state.isPreventClose)

        case "setPreventClose":
            state.isPreventClose = args?["isPreventClose"] as? Bool ?? false
            result(nil)

        case "confirmClose":
            state.isConfirmClose = args?["confirmClose"] as? Bool ?? true
            result(nil)

        case "mainPreConfirmClose":
            state.isMainPreConfirm = args?["mainPreConfirmClose"] as? Bool ?? true
            result(nil)

        case "setTitle":
            window.title = args?["title"] as? String ?? ""
            result(nil)

        case "setTitleBarStyle":
            let style = args?["titleBarStyle"] as? String ?? "normal"
            let buttonVisibility = args?["windowButtonVisibility"] as? Bool ?? true
            if style == "hidden" {
                window.styleMask.insert(.fullSizeContentView)
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                if !buttonVisibility {
                    window.standardWindowButton(.closeButton)?.isHidden = true
                    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                    window.standardWindowButton(.zoomButton)?.isHidden = true
                }
            } else {
                window.titleVisibility = .visible
                window.titlebarAppearsTransparent = false
                window.standardWindowButton(.closeButton)?.isHidden = false
                window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                window.standardWindowButton(.zoomButton)?.isHidden = false
            }
            result(nil)

        case "setAsFrameless":
            window.styleMask = [.fullSizeContentView, .resizable]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            result(nil)

        case "show":
            window.makeKeyAndOrderFront(nil)
            result(nil)

        case "hide":
            window.orderOut(nil)
            result(nil)

        case "isVisible":
            result(window.isVisible)

        case "focus":
            NSApp.activate(ignoringOtherApps: false)
            window.makeKeyAndOrderFront(nil)
            result(nil)

        case "blur":
            window.resignKey()
            result(nil)

        case "isFocused":
            result(window.isKeyWindow)

        case "maximize":
            if !window.isZoomed {
                window.zoom(nil)
            }
            result(nil)

        case "unmaximize":
            if window.isZoomed {
                window.zoom(nil)
            }
            result(nil)

        case "isMaximized":
            result(window.isZoomed)

        case "minimize":
            window.miniaturize(nil)
            result(nil)

        case "restore":
            window.deminiaturize(nil)
            result(nil)

        case "isMinimized":
            result(window.isMiniaturized)

        case "isFullScreen":
            result(window.styleMask.contains(.fullScreen))

        case "setFullScreen":
            let isFullScreen = args?["isFullScreen"] as? Bool ?? false
            if isFullScreen != window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            result(nil)

        case "getBounds":
            let frame = window.frame
            let tl = frame.topLeft
            result([
                       "x": tl.x,
                       "y": tl.y,
                       "width": frame.width,
                       "height": frame.height,
                   ])

        case "setSize":
            var f = window.frame
            f.size = NSSize(
                width: args?["width"] as? CGFloat ?? f.width,
                height: args?["height"] as? CGFloat ?? f.height
            )
            window.setFrame(f, display: true)
            result(nil)

        case "setPosition":
            var frameRect = window.frame
            if let x = args?["x"] as? CGFloat, let y = args?["y"] as? CGFloat {
                frameRect.topLeft = CGPoint(x: x, y: y)
                window.setFrameOrigin(frameRect.origin)
            }
            result(nil)

        case "center":
            window.center()
            result(nil)

        case "setMinimumSize":
            window.minSize = NSSize(
                width: args?["width"] as? CGFloat ?? 0,
                height: args?["height"] as? CGFloat ?? 0
            )
            result(nil)

        case "setMaximumSize":
            window.maxSize = NSSize(
                width: args?["width"] as? CGFloat ?? CGFloat.greatestFiniteMagnitude,
                height: args?["height"] as? CGFloat ?? CGFloat.greatestFiniteMagnitude
            )
            result(nil)

        case "setAspectRatio":
            let ratio = args?["aspectRatio"] as? Double ?? 0.0
            if ratio > 0 {
                window.contentAspectRatio = NSSize(width: ratio, height: 1.0)
            } else {
                window.resizeIncrements = NSSize(width: 1, height: 1)
            }
            result(nil)

        case "isResizable":
            result(window.styleMask.contains(.resizable))

        case "setResizable":
            let v = args?["isResizable"] as? Bool ?? true
            if v {
                window.styleMask.insert(.resizable)
            } else {
                window.styleMask.remove(.resizable)
            }
            result(nil)

        case "isMovable":
            result(window.isMovable)

        case "setMovable":
            window.isMovable = args?["isMovable"] as? Bool ?? true
            result(nil)

        case "isMinimizable":
            result(window.styleMask.contains(.miniaturizable))

        case "setMinimizable":
            let v = args?["isMinimizable"] as? Bool ?? true
            if v {
                window.styleMask.insert(.miniaturizable)
            } else {
                window.styleMask.remove(.miniaturizable)
            }
            result(nil)

        case "isMaximizable":
            result(window.standardWindowButton(.zoomButton)?.isEnabled ?? true)

        case "setMaximizable":
            window.standardWindowButton(.zoomButton)?.isEnabled = args?["isMaximizable"] as? Bool ?? true
            result(nil)

        case "isClosable":
            result(window.styleMask.contains(.closable))

        case "setClosable":
            let v = args?["isClosable"] as? Bool ?? true
            if v {
                window.styleMask.insert(.closable)
            } else {
                window.styleMask.remove(.closable)
            }
            result(nil)

        case "isAlwaysOnTop":
            result(window.level == .floating)

        case "setAlwaysOnTop":
            window.level = (args?["isAlwaysOnTop"] as? Bool ?? false) ? .floating : .normal
            result(nil)

        case "isSkipTaskbar":
            result(window.collectionBehavior.contains(.ignoresCycle))

        case "setSkipTaskbar":
            let v = args?["isSkipTaskbar"] as? Bool ?? false
            if v {
                window.collectionBehavior.insert(.ignoresCycle)
                window.collectionBehavior.insert(.transient)
            } else {
                window.collectionBehavior.remove(.ignoresCycle)
                window.collectionBehavior.remove(.transient)
            }
            result(nil)

        case "hasShadow":
            result(window.hasShadow)

        case "setHasShadow":
            window.hasShadow = args?["hasShadow"] as? Bool ?? true
            result(nil)

        case "getOpacity":
            result(Double(window.alphaValue))

        case "setOpacity":
            window.alphaValue = CGFloat(args?["opacity"] as? Double ?? 1.0)
            result(nil)

        case "setBrightness":
            let name = args?["brightness"] as? String ?? "light"
            window.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
            result(nil)

        case "setBackgroundColor":
            let a = args?["backgroundColorA"] as? Int ?? 255
            let r = args?["backgroundColorR"] as? Int ?? 255
            let g = args?["backgroundColorG"] as? Int ?? 255
            let b = args?["backgroundColorB"] as? Int ?? 255
            window.backgroundColor = NSColor(
                calibratedRed: CGFloat(r) / 255,
                green: CGFloat(g) / 255,
                blue: CGFloat(b) / 255,
                alpha: CGFloat(a) / 255
            )
            result(nil)

        case "isVisibleOnAllWorkspaces":
            result(window.collectionBehavior.contains(.canJoinAllSpaces))

        case "setVisibleOnAllWorkspaces":
            let visible = args?["visible"] as? Bool ?? false
            let onFullScreen = args?["visibleOnFullScreen"] as? Bool ?? false
            if visible {
                window.collectionBehavior.insert(.canJoinAllSpaces)
                if onFullScreen {
                    window.collectionBehavior.insert(.fullScreenAuxiliary)
                }
            } else {
                window.collectionBehavior.remove(.canJoinAllSpaces)
                window.collectionBehavior.remove(.fullScreenAuxiliary)
            }
            result(nil)

        case "setBadgeLabel":
            NSApp.dockTile.badgeLabel = args?["label"] as? String
            result(nil)

        case "setProgressBar", "setIgnoreMouseEvents", "startResizing":
            result(nil)

        case "startDragging":
            if let event = NSApp.currentEvent {
                window.performDrag(with: event)
            }
            result(nil)

        case "popUpWindowMenu":
            DispatchQueue.main.async {
                guard let contentView = window.contentView,
                      let event = NSApp.currentEvent
                else {
                    return
                }
                let menu = NSMenu()
                if window.styleMask.contains(.miniaturizable) {
                    menu.addItem(NSMenuItem(
                        title: "Minimize",
                        action: #selector(NSWindow.miniaturize(_:)),
                        keyEquivalent: ""
                    ))
                }
                menu.addItem(NSMenuItem(
                    title: "Zoom",
                    action: #selector(NSWindow.zoom(_:)),
                    keyEquivalent: ""
                ))
                if window.styleMask.contains(.closable) {
                    menu.addItem(.separator())
                    menu.addItem(NSMenuItem(
                        title: "Close",
                        action: #selector(NSWindow.performClose(_:)),
                        keyEquivalent: ""
                    ))
                }
                NSMenu.popUpContextMenu(menu, with: event, for: contentView)
            }
            result(nil)

        case "getTitle":
            result(window.title)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Helpers

    private func emitEvent(_ eventName: String, viewId: Int64) {
        channel?.invokeMethod(
            "onEvent",
            arguments: ["eventName": eventName, "viewId": Int(viewId)]
        )
    }

    private func viewIdForWindow(_ window: NSWindow) -> Int64? {
        windows.first(where: { $0.value === window })?.key
    }

    private func cgFloat(from value: Any?) -> CGFloat? {
        if let v = value as? CGFloat {
            return v
        }
        if let v = value as? NSNumber {
            return CGFloat(truncating: v)
        }
        if let v = value as? Double {
            return CGFloat(v)
        }
        if let v = value as? Int {
            return CGFloat(v)
        }
        return nil
    }

    private func int64(from args: [String: Any], key: String) -> Int64 {
        if let v = args[key] as? Int64 {
            return v
        }
        if let v = args[key] as? Int {
            return Int64(v)
        }
        if let v = args[key] as? NSNumber {
            return v.int64Value
        }
        return -1
    }
}
