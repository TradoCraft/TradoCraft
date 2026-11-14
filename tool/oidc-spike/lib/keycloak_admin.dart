import 'dart:convert';
import 'dart:io';

import 'fake_browser.dart';

/// Minimal Keycloak admin REST helper (admin/admin on the master realm) used
/// to revoke sessions and offline tokens like an administrator would.
class KeycloakAdmin {
  final HttpClient _h = HttpClient();
  static const base = 'http://127.0.0.1:18080';

  Future<String> _token() async {
    final req = await _h.postUrl(
      Uri.parse('$base/realms/master/protocol/openid-connect/token'),
    );
    req.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
    );
    req.write(
      'grant_type=password&client_id=admin-cli&username=admin&password=admin',
    );
    final res = await req.close();
    return (jsonDecode(await utf8.decoder.bind(res).join())
            as Map)['access_token']
        as String;
  }

  Future<String> _call(String method, String path) async {
    final t = await _token();
    final req = await _h.openUrl(
      method,
      Uri.parse('$base/admin/realms/tradocraft$path'),
    );
    req.headers.set('authorization', 'Bearer $t');
    final res = await req.close();
    final body = await utf8.decoder.bind(res).join();
    if (res.statusCode >= 300) {
      throw StateError('admin $method $path -> ${res.statusCode} $body');
    }
    return body;
  }

  Future<String> userId(String username) async {
    final l = jsonDecode(
      await _call('GET', '/users?username=$username&exact=true'),
    ) as List;
    return (l.first as Map)['id'] as String;
  }

  /// Revokes offline tokens of the client for the user (consent revocation).
  Future<void> revokeOfflineTokens(String userId) =>
      _call('DELETE', '/users/$userId/consents/$kClientId');

  /// Ends all online sessions of the user.
  Future<void> logoutUser(String userId) =>
      _call('POST', '/users/$userId/logout');

  void close() => _h.close(force: true);
}
