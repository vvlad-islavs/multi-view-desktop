import Cocoa
import FlutterMacOS

public class MultiviewDesktopPlugin: NSObject, FlutterPlugin {

  // MARK: - Pre-flight engine setup

  /// Call this in `MainFlutterWindow.awakeFromNib` before creating any
  /// `FlutterViewController(engine:nibName:bundle:)`.
  public static func prepareEngine(_ engine: FlutterEngine, window: NSWindow) {
    let impl = MultiviewDesktopImpl.shared
    impl.engine = engine
    impl.mainWindowRef = window

    let sel = NSSelectorFromString("enableMultiView")
    if engine.responds(to: sel) {
      engine.perform(sel)
    }
  }

  // MARK: - FlutterPlugin

  public static func register(with registrar: FlutterPluginRegistrar) {
    let impl = MultiviewDesktopImpl.shared
    impl.setup(messenger: registrar.messenger)

    if let window = impl.mainWindowRef,
       let vc = window.contentViewController as? FlutterViewController {
      impl.registerWindow(window, viewId: vc.viewIdentifier)
    }

    MvdScreenRetrieverPlugin.register(with: registrar.messenger)
  }
}
