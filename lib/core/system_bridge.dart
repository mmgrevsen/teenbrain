/// The small set of OS favours GlemtDet asks for at runtime.
///
/// Inside the macOS App Sandbox, `$HOME` is the app's own container — correct
/// for the database and stored frames, but it means Dart cannot see the real
/// Downloads folder or open Finder. Those two things go through the native
/// side; everything else stays in [AppPaths].
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'app_paths.dart';

class SystemBridge {
  const SystemBridge._();

  static const _channel = MethodChannel('dk.glemtdet/system');

  static bool get _hasNative => Platform.isMacOS;

  /// Where an export should be written. Prefers the user's real Downloads
  /// folder, and falls back to GlemtDet's own data directory — which always
  /// works, sandbox or not.
  static Future<Directory> exportDirectory() async {
    if (_hasNative) {
      try {
        final path = await _channel.invokeMethod<String>('downloadsDirectory');
        if (path != null && Directory(path).existsSync()) return Directory(path);
      } on PlatformException {
        // Fall through to the non-native answer.
      } on MissingPluginException {
        // Running under `flutter test`, where there is no platform side.
      }
    }
    return AppPaths.exportDirectory();
  }

  /// Shows a file or folder in Finder / Explorer. Returns false when the
  /// platform cannot do it, so the caller can show the path instead.
  static Future<bool> reveal(String path) async {
    if (_hasNative) {
      try {
        return await _channel.invokeMethod<bool>('reveal', {'path': path}) ?? false;
      } on PlatformException {
        return false;
      } on MissingPluginException {
        return false;
      }
    }
    if (Platform.isWindows) {
      try {
        final result = await Process.run('explorer', [path]);
        return result.exitCode == 0 || result.exitCode == 1;
      } catch (_) {
        return false;
      }
    }
    return false;
  }
}
