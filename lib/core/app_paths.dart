/// Where GlemtDet keeps its data on each desktop platform.
///
/// This is deliberately a tiny module rather than a plugin dependency: the two
/// target platforms both derive their application-support directory from a
/// single environment variable, and keeping it here means the macOS build has
/// no FFI plugin, no CocoaPods step and nothing to go wrong at install time.
///
/// On iPhone and Android the sandbox path is not derivable, so those two ask
/// `path_provider` instead. Desktop keeps the dependency-free path: it is one
/// environment variable per platform, and it means the macOS build has no FFI
/// plugin and nothing to go wrong at install time.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppPaths {
  const AppPaths._();

  /// Deliberately unchanged from GlemtDet. The database in this folder carries
  /// the v1 tables, and migrating in place is the whole point of schema v2 —
  /// a new folder name would silently abandon an existing install's data.
  static const String appFolderName = 'GlemtDet';

  /// The async form, which is the only one that works on iOS and Android.
  /// Desktop falls through to the synchronous derivation below.
  static Future<Directory> resolveDataDirectory() async {
    if (Platform.isIOS || Platform.isAndroid) {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(p.join(support.path, appFolderName));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    }
    return dataDirectory();
  }

  /// Everything GlemtDet stores lives under here: the SQLite file and the
  /// `frames/` directory of reference images. Nothing is written anywhere else.
  static Directory dataDirectory() {
    final dir = Directory(p.join(_supportRoot(), appFolderName));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Where an export lands. Falls back to the data directory if the user has
  /// no Downloads folder.
  static Directory exportDirectory() {
    final candidates = <String>[
      if (Platform.isWindows)
        p.join(_env('USERPROFILE') ?? _env('HOMEPATH') ?? '.', 'Downloads')
      else
        p.join(_home(), 'Downloads'),
    ];
    for (final path in candidates) {
      final dir = Directory(path);
      if (dir.existsSync()) return dir;
    }
    return dataDirectory();
  }

  static String _supportRoot() {
    if (Platform.isMacOS) {
      return p.join(_home(), 'Library', 'Application Support');
    }
    if (Platform.isWindows) {
      final appData = _env('APPDATA');
      if (appData != null && appData.isNotEmpty) return appData;
      return p.join(_env('USERPROFILE') ?? '.', 'AppData', 'Roaming');
    }
    // Linux and anything else: the XDG base directory spec.
    final xdg = _env('XDG_DATA_HOME');
    if (xdg != null && xdg.isNotEmpty) return xdg;
    return p.join(_home(), '.local', 'share');
  }

  static String _home() {
    return _env('HOME') ?? _env('USERPROFILE') ?? Directory.current.path;
  }

  static String? _env(String key) => Platform.environment[key];
}
