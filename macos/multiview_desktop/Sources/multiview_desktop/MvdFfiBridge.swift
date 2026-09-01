import Cocoa

// MVD FFI bridge — C ABI called from Dart `FfiBridge`.
// Dart UI isolate == AppKit main thread; no dispatch hop.
//
// Symbol convention: mvd_<verb>_<noun>
// Shared output buffer: mvd_rect_buf_ptr → Double[4] = {x, y, w, h}
// (Flutter logical coords, Y-down)

// MARK: - Shared rect buffer

private let _rectBuf: UnsafeMutablePointer<Double> = {
    let p = UnsafeMutablePointer<Double>.allocate(capacity: 4)
    p.initialize(repeating: 0, count: 4)
    return p
}()

@_cdecl("mvd_rect_buf_ptr")
public func mvdRectBufPtr() -> UnsafeMutablePointer<Double> {
    return _rectBuf
}

// MARK: - Window

/// Writes the frame of window `viewId` into the shared buffer.
/// Buffer: [x, y, w, h] in Flutter logical coords (Y-down).
/// All zeros when the view is not found.
@_cdecl("mvd_get_frame")
public func mvdGetFrame(_ viewId: Int64) {
    guard let window = MultiviewDesktopImpl.shared.windows[viewId] else {
        _rectBuf[0] = 0; _rectBuf[1] = 0; _rectBuf[2] = 0; _rectBuf[3] = 0
        return
    }
    let tl = window.frame.topLeft   // NSRect extension → Flutter Y-down
    _rectBuf[0] = Double(tl.x)
    _rectBuf[1] = Double(tl.y)
    _rectBuf[2] = Double(window.frame.width)
    _rectBuf[3] = Double(window.frame.height)
}

/// Moves/resizes window `viewId` (Flutter logical coords, Y-down).
///
/// When only the position changes (size within 0.5 pt), `setFrameOrigin` is
/// used instead of `setFrame`. This skips `FlutterView.setFrameSize` →
/// `ResizeSynchronizer.beginResize` is never triggered → no Impeller crash.
@_cdecl("mvd_set_frame")
public func mvdSetFrame(
    _ viewId: Int64,
    _ x: Double, _ y: Double,
    _ w: Double, _ h: Double
) {
    guard let window = MultiviewDesktopImpl.shared.windows[viewId] else { return }

    let tolerance: CGFloat = 0.5
    let sizeChanged =
        abs(window.frame.width  - CGFloat(w)) > tolerance ||
        abs(window.frame.height - CGFloat(h)) > tolerance

    if sizeChanged {
        var f = window.frame
        f.size    = NSSize(width: CGFloat(w), height: CGFloat(h))
        f.topLeft = CGPoint(x: CGFloat(x), y: CGFloat(y))
        window.setFrame(f, display: false)
    } else {
        var f = window.frame
        f.topLeft = CGPoint(x: CGFloat(x), y: CGFloat(y))
        window.setFrameOrigin(f.origin)
    }
}

/// Makes window `viewId` ignore (1) or receive (0) mouse/scroll events.
@_cdecl("mvd_set_ignore_mouse_events")
public func mvdSetIgnoreMouseEvents(_ viewId: Int64, _ ignore: Int32) {
    MultiviewDesktopImpl.shared.windows[viewId]?.ignoresMouseEvents = ignore != 0
}

// MARK: - Display

/// Writes the visible frame of the display best containing the given rect.
/// Buffer: [x, y, w, h] in Flutter logical coords (Y-down).
@_cdecl("mvd_get_display_rect")
public func mvdGetDisplayRect(
    _ x: Double, _ y: Double,
    _ w: Double, _ h: Double
) {
    let screens = NSScreen.screens
    guard let primary = screens.first else {
        _rectBuf[0] = 0; _rectBuf[1] = 0; _rectBuf[2] = 2560; _rectBuf[3] = 1440
        return
    }
    let ph = primary.frame.height

    // Convert Flutter rect (Y-down) → NSScreen Y-up for overlap comparison.
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
    _rectBuf[1] = Double(ph - vf.maxY)   // Y-up → Flutter Y-down
    _rectBuf[2] = Double(vf.width)
    _rectBuf[3] = Double(vf.height)
}
