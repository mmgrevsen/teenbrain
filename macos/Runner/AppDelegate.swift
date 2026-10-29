import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {

  /// GlemtDet keeps running when the window is closed, because that is what
  /// "Hukommelse aktiv" means: the capture session stays open and observations
  /// keep being recorded.
  ///
  /// This is as far as macOS allows an app to go. A quit app cannot use the
  /// camera, and GlemtDet does not install a background agent to work around
  /// that — the camera indicator stays lit for exactly as long as the app is
  /// looking, which is the behaviour a user is entitled to. Quit with ⌘Q, or
  /// switch the memory off in the sidebar.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// Clicking the Dock icon brings the window back.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      for window in sender.windows { window.makeKeyAndOrderFront(self) }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
