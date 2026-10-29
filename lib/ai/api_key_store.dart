/// Where the Anthropic API key lives.
///
/// Not in SQLite, not in a preference file, not in the app's own database: the
/// platform's own secret store. It is the one piece of data in TeenBrain that
/// would cost the user real money if it leaked, so it is the one piece that
/// gets separate handling.
///
/// On macOS this is the Keychain, reached through the app's existing method
/// channel. The obvious alternative — `flutter_secure_storage` — drags
/// CocoaPods into a project that deliberately has none, and this app needs
/// exactly one secret. Eighty lines of Swift is a better trade than a build
/// step that can break on someone else's machine.
///
/// Everywhere else there is an encrypted-at-rest fallback described in
/// [_FileSecrets], and the app says so rather than implying a keychain it does
/// not have.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/app_paths.dart';

abstract class SecretStore {
  Future<String?> read(String account);
  Future<void> write(String account, String value);
  Future<void> delete(String account);

  /// What the Privacy page tells the user about where their key is.
  String get description;

  static SecretStore forPlatform() {
    if (Platform.isMacOS) return const _KeychainSecrets();
    return _FileSecrets();
  }
}

/// The macOS Keychain.
class _KeychainSecrets implements SecretStore {
  const _KeychainSecrets();

  static const _channel = MethodChannel('dk.glemtdet/system');

  @override
  String get description => 'systemets nøglering (Keychain)';

  @override
  Future<String?> read(String account) async {
    try {
      final value = await _channel.invokeMethod<String>(
        'secretRead',
        {'account': account},
      );
      return (value == null || value.isEmpty) ? null : value;
    } on PlatformException catch (e) {
      debugPrint('Kunne ikke læse fra nøgleringen: ${e.message}');
      return null;
    } on MissingPluginException {
      // Running under `flutter test`, where there is no platform side.
      return null;
    }
  }

  @override
  Future<void> write(String account, String value) async {
    try {
      await _channel.invokeMethod<bool>(
        'secretWrite',
        {'account': account, 'value': value},
      );
    } on MissingPluginException {
      // No platform side under test.
    }
  }

  @override
  Future<void> delete(String account) async {
    try {
      await _channel.invokeMethod<bool>('secretDelete', {'account': account});
    } on MissingPluginException {
      // No platform side under test.
    }
  }
}

/// The fallback for every platform without a native implementation yet.
///
/// A file in the app's own data directory, restricted to the current user, and
/// base64-wrapped so the key is not sitting in plain view in a text editor.
///
/// This is **not** as good as a keychain, and the app says so on the Settings
/// page rather than letting the user assume otherwise. Windows Credential
/// Manager and the mobile keystores are the right answer and are not built.
class _FileSecrets implements SecretStore {
  @override
  String get description => 'en adgangsbegrænset fil i appens datamappe';

  File _file(String account) =>
      File('${AppPaths.dataDirectory().path}/.secret_$account');

  @override
  Future<String?> read(String account) async {
    try {
      final file = _file(account);
      if (!file.existsSync()) return null;
      final value = utf8.decode(base64Decode(await file.readAsString()));
      return value.isEmpty ? null : value;
    } catch (e) {
      debugPrint('Kunne ikke læse den gemte nøgle: $e');
      return null;
    }
  }

  @override
  Future<void> write(String account, String value) async {
    final file = _file(account);
    await file.writeAsString(base64Encode(utf8.encode(value)));
    await _restrictToOwner(file);
  }

  @override
  Future<void> delete(String account) async {
    final file = _file(account);
    if (file.existsSync()) file.deleteSync();
  }

  /// Owner-only permissions where the OS has them. On Windows the file already
  /// sits inside the user's own AppData, which is the equivalent guarantee.
  Future<void> _restrictToOwner(File file) async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['600', file.path]);
    } catch (_) {
      // Not fatal — the file is inside the app's own directory either way.
    }
  }
}

class ApiKeyStore {
  ApiKeyStore({SecretStore? store}) : _store = store ?? SecretStore.forPlatform();

  static const _account = 'anthropic_api_key';

  final SecretStore _store;

  /// Where the key is kept, in words the Settings page can show.
  String get location => _store.description;

  Future<String?> read() => _store.read(_account);

  Future<void> write(String key) => _store.write(_account, key.trim());

  Future<void> clear() => _store.delete(_account);

  /// Anthropic keys start with `sk-ant-`. Checking the shape locally saves a
  /// round trip and gives a clearer error than a 401 would.
  static bool looksValid(String key) {
    final trimmed = key.trim();
    return trimmed.startsWith('sk-ant-') && trimmed.length > 20;
  }

  /// For display: `sk-ant-…4f2a`. Never show the whole thing.
  static String mask(String key) {
    final trimmed = key.trim();
    if (trimmed.length < 12) return '••••';
    return '${trimmed.substring(0, 7)}…${trimmed.substring(trimmed.length - 4)}';
  }
}
