import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // A sidebar layout needs room; below this the two columns fight.
    self.minSize = NSSize(width: 940, height: 640)
    self.title = "GlemtDet"
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.isMovableByWindowBackground = true

    RegisterGeneratedPlugins(registry: flutterViewController)

    // GlemtDet's own camera and Vision stack. Registered by hand because it
    // lives in the app target rather than in a pub package.
    GlemtDetPlugin.register(
      with: flutterViewController.registrar(forPlugin: "GlemtDetPlugin"))

    super.awakeFromNib()
  }
}
