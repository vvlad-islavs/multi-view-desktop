import Cocoa
import FlutterMacOS
import multiview_desktop


@main
class AppDelegate: FlutterAppDelegate {
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return MultiviewDesktopPlugin.applicationShouldTerminateAfterLastWindowClosed()
    }

    override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if MultiviewDesktopPlugin.applicationShouldHandleReopen(sender, hasVisibleWindows: flag) {
            return true
        }
        return super.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // add new items to taskbar menu
//    override func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
//        let menu = NSMenu()
//        menu.addItem(NSMenuItem(
//            title: "New Window",
//            action: #selector (openNewWindow),
//            keyEquivalent: ""
//        ))
//        menu.addItem(.separator())
//        menu.addItem(NSMenuItem(
//            title: "Sync from Dart...",
//            action: #selector (openNewWindow),
//            keyEquivalent: ""
//        ))
//        // target обязателен, иначе action не сработает
//        menu.items.forEach {
//            $0.target = self
//        }
//        return menu
//    }
//
//    @objc private func openNewWindow() {
//        // вызов native / method channel во Flutter
//    }
}
// Пример на будущее
//override func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
//    let menu = NSMenu()
//    for window in NSApp.windows where window.isVisible && !window.title.isEmpty {
//        let item = NSMenuItem(title: window.title, action: #selector(focusWindow(_:)), keyEquivalent: "")
//        item.target = self
//        item.representedObject = window
//        menu.addItem(item)
//    }
//    return menu.isEmpty ? nil : menu
//}
//@objc private func focusWindow(_ sender: NSMenuItem) {
//    (sender.representedObject as? NSWindow)?.makeKeyAndOrderFront(nil)
//}
