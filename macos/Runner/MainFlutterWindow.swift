import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    let initialSize = NSSize(width: 480, height: 700)
    self.setContentSize(initialSize)
    self.minSize = NSSize(width: 380, height: 500)
    self.center()
    self.title = "ClipSync"

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
