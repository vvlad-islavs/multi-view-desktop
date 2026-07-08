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
        window.orderOut(nil)


        // turn engine to multiView mode. Critical part that
        // could will crashed on new flutter versions
        let sel = NSSelectorFromString("enableMultiView")
        if engine.responds(to: sel) {
            engine.perform(sel)
        }
        engine.run(withEntrypoint: nil)
    }

    // MARK: - FlutterPlugin

    public static func register(with registrar: FlutterPluginRegistrar) {
        let impl = MultiviewDesktopImpl.shared
        impl.setup(messenger: registrar.messenger)
        impl.installLifecycleObservers()

        if let window = impl.mainWindowRef,
           let vc = window.contentViewController as? FlutterViewController {
            impl.registerMain(window, viewId: vc.viewIdentifier)
            window.orderOut(nil)
        }


        MvdScreenRetrieverPlugin.register(with: registrar.messenger)
    }

    /// Fallback when `applicationShouldTerminate` is not overridden in AppDelegate.
    ///
    /// With the recommended `applicationShouldTerminate` forward, last-window policy is
    /// applied inside [MultiviewDesktopImpl.handleApplicationShouldTerminate] instead.
    public static func applicationShouldTerminateAfterLastWindowClosed() -> Bool {
        MultiviewDesktopImpl.shared.shouldTerminateAfterLastWindowClosed()
    }

    /// Forward from `AppDelegate.applicationShouldHandleReopen(_:hasVisibleWindows:)`.
    ///
    /// Restores windows hidden via [CloseMode.macos] when the user clicks the dock icon.
    public static func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        MultiviewDesktopImpl.shared.handleApplicationReopen(hasVisibleWindows: flag)
    }

    public static func applicationShouldTerminate(_ sender: Any?) -> NSApplication.TerminateReply {
        MultiviewDesktopImpl.shared.handleApplicationShouldTerminate(sender: sender)
    }
}
