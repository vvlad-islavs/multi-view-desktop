## 1.2.0

- [Check README] Linux. x11 support (setAlignment, alwaysOnTop, setPosition, center). Use GDK_BACKEND=x11 env arg to enable
- [Check README] Taskbar custom menu items on all platforms
- [Check README] MacOS. OnTerminate handler (CMD+Q/terminate the app from taskbar)
- MacOS. Removed `closeAppAfterLastWindowClosed` param. App automatically defines when need to stay in memory
- MacOS. saveLastWindowToReopen now ignored by one of causes: use `closeApp`/ onTerminate/ close mode is `destroy`

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