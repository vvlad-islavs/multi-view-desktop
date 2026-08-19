import Cocoa
import FlutterMacOS

private extension NSScreen {
    var mvdDisplayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    /// Returns a dictionary describing this screen in Flutter/logical coordinate space
    /// (Y-down, origin at top-left of the primary screen).
    func toMvdDictionary() -> NSDictionary {
        var name = ""
        if #available(macOS 10.15, *) {
            name = localizedName
        }
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? frame.maxY

        // Full screen bounds in Flutter coords.
        let size: NSDictionary = [
            "width": frame.width,
            "height": frame.height,
        ]

        // Visible area (excludes Dock / menu bar) in Flutter coords.
        // visibleFrame.origin is in Cocoa coords (Y-up from primary bottom).
        let vf = visibleFrame
        let visiblePosition: NSDictionary = [
            "dx": vf.origin.x,
            "dy": primaryMaxY - vf.origin.y - vf.height,
        ]
        let visibleSize: NSDictionary = [
            "width": vf.width,
            "height": vf.height,
        ]

        return [
            "id": mvdDisplayID.description,
            "name": name,
            "size": size,
            "visiblePosition": visiblePosition,
            "visibleSize": visibleSize,
        ]
    }
}

enum MvdScreenQuery {
    static func cursorPoint() -> NSPoint {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? (NSScreen.main?.frame.maxY ?? 0)
        let mouseLocation = NSEvent.mouseLocation
        return NSPoint(x: mouseLocation.x, y: primaryMaxY - mouseLocation.y)
    }

    static func primaryDictionary() -> NSDictionary? {
        NSScreen.screens.first?.toMvdDictionary()
    }

    static func allDictionaries() -> [NSDictionary] {
        NSScreen.screens.map { $0.toMvdDictionary() }
    }

    static func jsonString(from object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }
}

// MARK: - MvdScreenRetrieverPlugin

class MvdScreenRetrieverPlugin: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var externalDisplayCount = 0

    static func register(with messenger: FlutterBinaryMessenger) {
        let instance = MvdScreenRetrieverPlugin()

        let methodChannel = FlutterMethodChannel(
            name: "multiview_desktop/screen_retriever",
            binaryMessenger: messenger
        )
        methodChannel.setMethodCallHandler(instance.handle)

        let eventChannel = FlutterEventChannel(
            name: "multiview_desktop/screen_retriever_event",
            binaryMessenger: messenger
        )
        eventChannel.setStreamHandler(instance)

        instance.externalDisplayCount = NSScreen.screens.count
        instance.setupNotificationCenter()
    }

    // MARK: FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: Private

    private func setupNotificationCenter() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDisplayChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func handleDisplayChange(notification: Notification) {
        let current = NSScreen.screens.count
        if externalDisplayCount < current {
            emitEvent("display-added")
        } else if externalDisplayCount > current {
            emitEvent("display-removed")
        }
        externalDisplayCount = current
    }

    private func emitEvent(_ eventName: String) {
        mvdScreenTryEmit(eventName)
        guard let sink = eventSink else { return }
        sink(["type": eventName] as NSDictionary)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getCursorScreenPoint":
            let point = MvdScreenQuery.cursorPoint()
            result(["dx": point.x, "dy": point.y] as NSDictionary)
        case "getPrimaryDisplay":
            guard let screen = MvdScreenQuery.primaryDictionary() else {
                result(FlutterError(code: "NO_SCREEN", message: "No primary display found", details: nil))
                return
            }
            result(screen)
        case "getAllDisplays":
            result(["displays": MvdScreenQuery.allDictionaries()] as NSDictionary)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

private let kScreenStrCap = 8192

private let _screenRectBuf: UnsafeMutablePointer<Double> = {
    let p = UnsafeMutablePointer<Double>.allocate(capacity: 4)
    p.initialize(repeating: 0, count: 4)
    return p
}()

private let _screenStrBuf: UnsafeMutablePointer<CChar> = {
    let p = UnsafeMutablePointer<CChar>.allocate(capacity: kScreenStrCap)
    p.initialize(repeating: 0, count: kScreenStrCap)
    return p
}()

public typealias MvdScreenEventCallback = @convention(c) (UnsafePointer<CChar>?) -> Void

private var _screenEventCb: MvdScreenEventCallback?

func mvdScreenTryEmit(_ name: String) {
    guard let cb = _screenEventCb else { return }
    name.withCString { cstr in cb(cstr) }
}

private func writeScreenStr(_ s: String) {
    let chars = Array(s.utf8CString)
    let n = min(chars.count, kScreenStrCap)
    _screenStrBuf.update(from: chars, count: n)
    _screenStrBuf[kScreenStrCap - 1] = 0
}

@_cdecl("mvd_screen_rect_buf_ptr")
public func mvdScreenRectBufPtr() -> UnsafeMutablePointer<Double> { _screenRectBuf }

@_cdecl("mvd_screen_str_buf_ptr")
public func mvdScreenStrBufPtr() -> UnsafeMutablePointer<CChar> { _screenStrBuf }

@_cdecl("mvd_set_screen_event_callback")
public func mvdSetScreenEventCallback(_ cb: MvdScreenEventCallback?) {
    _screenEventCb = cb
}

@_cdecl("mvd_get_cursor_screen_point")
public func mvdGetCursorScreenPoint(_: Double) -> Int32 {
    let point = MvdScreenQuery.cursorPoint()
    _screenRectBuf[0] = Double(point.x)
    _screenRectBuf[1] = Double(point.y)
    return 1
}

@_cdecl("mvd_get_primary_display")
public func mvdGetPrimaryDisplay() -> Int32 {
    guard let dict = MvdScreenQuery.primaryDictionary() else { return 0 }
    let json = MvdScreenQuery.jsonString(from: dict)
    if json.isEmpty { return 0 }
    writeScreenStr(json)
    return 1
}

@_cdecl("mvd_get_all_displays")
public func mvdGetAllDisplays() -> Int32 {
    let json = MvdScreenQuery.jsonString(from: MvdScreenQuery.allDictionaries())
    if json.isEmpty { return 0 }
    writeScreenStr(json)
    return 1
}
