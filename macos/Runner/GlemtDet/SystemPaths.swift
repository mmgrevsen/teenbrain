import AppKit
import Foundation

/// The few things GlemtDet needs from the OS that Dart cannot work out on its
/// own inside the App Sandbox.
///
/// Inside the sandbox `$HOME` points at the app's own container, which is
/// exactly what we want for the database and stored frames — but it means Dart
/// cannot see the user's real Downloads folder. `FileManager` can, given the
/// downloads entitlement, so exporting asks the native side for the path.
enum SystemPaths {

  static func downloadsDirectory() -> String? {
    let urls = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
    return urls.first?.path
  }

  static func applicationSupportDirectory() -> String? {
    let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    return urls.first?.path
  }

  /// Opens Finder with the given file or folder selected, so "Vis datamappe"
  /// does something rather than printing a path the user has to hunt for.
  @discardableResult
  static func reveal(path: String) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
      return false
    }
    if isDirectory.boolValue {
      NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    } else {
      NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
    return true
  }
}
