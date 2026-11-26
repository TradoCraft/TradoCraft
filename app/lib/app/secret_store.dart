import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../features/field/offline/kv_store.dart';

/// Storage for secrets (bearer and refresh tokens). Kept apart from [KvStore], which holds
/// non-secret preferences in SharedPreferences or a profile file.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// In memory only: tests, and the last-resort fallback of [PlatformSecretStore].
class MemorySecretStore implements SecretStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// The platform's secure store through `flutter_secure_storage`:
/// * Android: AES keys in the Android Keystore; the data is excluded from backups (see the manifest);
/// * iOS and macOS: Keychain; Windows: Credential Manager (DPAPI); Linux: libsecret;
/// * web: WebCrypto-encrypted values in localStorage. The key sits in the same origin, so this only
///   protects against casual reading, not against script running in the page (XSS).
///
/// Where no secure store exists (for instance Linux without libsecret) the plugin throws; the
/// secret then lives in memory for the rest of the run and is never written to disk in clear text:
/// the user signs in again on the next start.
class PlatformSecretStore implements SecretStore {
  PlatformSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final MemorySecretStore _memory = MemorySecretStore();

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key) ?? await _memory.read(key);
    } catch (_) {
      return _memory.read(key);
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      await _memory.delete(key);
    } catch (_) {
      await _memory.write(key, value);
    }
  }

  @override
  Future<void> delete(String key) async {
    await _memory.delete(key);
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // Nothing stored there.
    }
  }
}

/// Wraps a [KvStore] so the tokens never reach it: the session token and the tokens inside the
/// stored list of environments go to a [SecretStore]. Everything else passes straight through.
///
/// Migration: a token still found in the old plain storage is copied to the secret store and
/// removed from the plain one, once, on first read.
class SecureKvStore implements KvStore {
  SecureKvStore(this._plain, this._secrets, {this.namespace = ''});

  final KvStore _plain;
  final SecretStore _secrets;

  /// Separates profiles that share one secure store (the profile name).
  final String namespace;

  static const sessionTokenKey = 'access_token';
  static const environmentsKey = 'environments';

  String _sk(String name) => 'tradocraft:$namespace:$name';

  @override
  Future<String?> get(String key) async {
    if (key == sessionTokenKey) return _getToken(key, _sk(key));
    if (key == environmentsKey) return _getEnvironments();
    return _plain.get(key);
  }

  @override
  Future<void> set(String key, String value) async {
    if (key == sessionTokenKey) return _secrets.write(_sk(key), value);
    if (key == environmentsKey) return _setEnvironments(value);
    return _plain.set(key, value);
  }

  @override
  Future<void> remove(String key) async {
    if (key == sessionTokenKey) {
      await _secrets.delete(_sk(key));
      await _plain.remove(key);
      return;
    }
    return _plain.remove(key);
  }

  Future<String?> _getToken(String plainKey, String secretKey) async {
    final secret = await _secrets.read(secretKey);
    final old = await _plain.get(plainKey);
    if (old != null) {
      // Migrate: secure copy first, then delete the clear-text one.
      if (secret == null) await _secrets.write(secretKey, old);
      await _plain.remove(plainKey);
    }
    return secret ?? old;
  }

  String _envKey(Object? id) => _sk('env_token:$id');

  Future<String?> _getEnvironments() async {
    final raw = await _plain.get(environmentsKey);
    if (raw == null) return null;
    final Object? json;
    try {
      json = jsonDecode(raw);
    } catch (_) {
      return raw;
    }
    if (json is! Map || json['items'] is! List) return raw;
    var legacy = false;
    for (final item in json['items'] as List) {
      if (item is! Map) continue;
      final id = item['id'];
      final secret = await _secrets.read(_envKey(id));
      final old = item['token'];
      if (old is String && old.isNotEmpty) {
        legacy = true;
        if (secret == null) await _secrets.write(_envKey(id), old);
      }
      item['token'] = secret ?? (old is String ? old : null);
    }
    if (legacy) await _setEnvironments(jsonEncode(json));
    return jsonEncode(json);
  }

  Future<void> _setEnvironments(String value) async {
    final Object? json;
    try {
      json = jsonDecode(value);
    } catch (_) {
      return _plain.set(environmentsKey, value);
    }
    if (json is! Map || json['items'] is! List) {
      return _plain.set(environmentsKey, value);
    }
    final stripped = <Object?>[];
    for (final item in json['items'] as List) {
      if (item is! Map) {
        stripped.add(item);
        continue;
      }
      final copy = Map<String, Object?>.from(item);
      final token = copy.remove('token');
      final key = _envKey(copy['id']);
      if (token is String && token.isNotEmpty) {
        await _secrets.write(key, token);
      } else {
        await _secrets.delete(key);
      }
      stripped.add(copy);
    }
    await _plain.set(environmentsKey, jsonEncode({...json, 'items': stripped}));
  }
}
