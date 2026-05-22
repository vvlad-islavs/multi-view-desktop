import Cocoa
import FlutterMacOS
import multiview_desktop

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let engine = FlutterEngine(name: "main_flutter_engine", project: nil, allowHeadlessExecution: true)
    MultiviewDesktopPlugin.prepareEngine(engine, window: self)

    // Engine must be running before FlutterViewController(engine:) is created.
    engine.run(withEntrypoint: nil)

    let flutterViewController = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
