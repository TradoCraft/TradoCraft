import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/generated/export.dart';

/// Where the portal finds the API and which company's portal this is. Set at build time:
/// `flutter build web -t lib/portal/portal_main.dart --dart-define=PORTAL_API_URL=https://...`
const portalApiUrl = String.fromEnvironment(
  'PORTAL_API_URL',
  defaultValue: 'http://localhost:8080',
);

/// The company this portal belongs to (customers can do business with several legal entities).
/// The default is the development seed company.
const portalCompanyId = String.fromEnvironment(
  'PORTAL_COMPANY_ID',
  defaultValue: '00000000-0000-7000-8000-000000000001',
);

const _tokenKey = 'portal_session_token';

class PortalTokenStore {
  static Future<String?> load() async =>
      (await SharedPreferences.getInstance()).getString(_tokenKey);

  static Future<void> save(String? token) async {
    final p = await SharedPreferences.getInstance();
    token == null
        ? await p.remove(_tokenKey)
        : await p.setString(_tokenKey, token);
  }
}

/// The login-link token in an address: `/login#token=tcl_...` (what the e-mail contains) or,
/// for convenience, `?token=`. Null when there is none.
String? linkTokenFromUri(Uri uri) {
  String? token;
  try {
    if (uri.fragment.contains('=')) {
      token = Uri.splitQueryString(uri.fragment)['token'];
    }
  } on FormatException {
    token = null;
  }
  token ??= uri.queryParameters['token'];
  return token != null && token.startsWith('tcl_') ? token : null;
}

/// The satisfaction survey link the portal was opened with: `/csat#token=tcq_...&rating=good`.
class CsatLink {
  const CsatLink(this.token, this.rating);
  final String token;

  /// good | bad, as clicked in the e-mail; null when the link did not say.
  final String? rating;
}

CsatLink? csatLinkFromUri(Uri uri) {
  try {
    if (!uri.fragment.contains('=')) return null;
    final q = Uri.splitQueryString(uri.fragment);
    final token = q['token'];
    if (token == null || !token.startsWith('tcq_')) return null;
    final rating = q['rating'];
    return CsatLink(token, rating == 'good' || rating == 'bad' ? rating : null);
  } on FormatException {
    return null;
  }
}

/// Read in `main` before the router rewrites the address (the fragment would be lost).
final initialCsatLinkProvider = Provider<CsatLink?>((ref) => null);

/// The login-link token the app was opened with. It must be read in `main`, before the router
/// starts: the router rewrites the address and drops the fragment.
final initialPortalLinkTokenProvider = Provider<String?>((ref) => null);

/// The link token still to be exchanged; cleared once tried, so it is never used twice.
class PortalLinkTokenNotifier extends Notifier<String?> {
  @override
  String? build() => ref.read(initialPortalLinkTokenProvider);

  void clear() => state = null;
}

final portalLinkTokenProvider =
    NotifierProvider<PortalLinkTokenNotifier, String?>(
      PortalLinkTokenNotifier.new,
    );

/// The session token read from storage at start-up (overridden in main and in tests).
final initialPortalTokenProvider = Provider<String?>((ref) => null);

/// The portal session token; null when signed out.
class PortalTokenNotifier extends Notifier<String?> {
  @override
  String? build() => ref.read(initialPortalTokenProvider);

  Future<void> set(String? token) async {
    state = token;
    await PortalTokenStore.save(token);
  }
}

final portalTokenProvider = NotifierProvider<PortalTokenNotifier, String?>(
  PortalTokenNotifier.new,
);

final portalDioProvider = Provider<Dio>((ref) {
  final token = ref.watch(portalTokenProvider);
  return Dio(
    BaseOptions(
      baseUrl: portalApiUrl,
      headers: {'Authorization': ?(token == null ? null : 'Bearer $token')},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );
});

final portalApiProvider = Provider<PortalClient>(
  (ref) => TradocraftApi(ref.watch(portalDioProvider)).portal,
);

/// Who is signed in. An expired or revoked session ends here: the token is dropped and the router
/// sends the person to the login page.
final portalProfileProvider = FutureProvider<PortalProfile>((ref) async {
  final api = ref.watch(portalApiProvider);
  try {
    return await api.getMe();
  } on DioException catch (e) {
    if (e.response?.statusCode == 401) {
      await ref.read(portalTokenProvider.notifier).set(null);
    }
    rethrow;
  }
});

final portalTicketsProvider = FutureProvider.autoDispose<List<PortalTicket>>(
  (ref) => ref.watch(portalApiProvider).listPortalTickets(),
);

final portalTicketProvider = FutureProvider.autoDispose
    .family<PortalTicketDetail, String>(
      (ref, id) => ref.watch(portalApiProvider).getPortalTicket(id: id),
    );

final portalRepairsProvider = FutureProvider.autoDispose<List<PortalRepair>>(
  (ref) => ref.watch(portalApiProvider).listPortalRepairs(),
);

final portalRepairProvider = FutureProvider.autoDispose
    .family<PortalRepairDetail, String>(
      (ref, id) => ref.watch(portalApiProvider).getPortalRepair(id: id),
    );

final portalOrdersProvider = FutureProvider.autoDispose<List<PortalOrder>>(
  (ref) => ref.watch(portalApiProvider).listPortalOrders(),
);

final portalOrderProvider = FutureProvider.autoDispose
    .family<PortalOrderDetail, String>(
      (ref, id) => ref.watch(portalApiProvider).getPortalOrder(id: id),
    );

/// The language of the portal: the person's own, once known; before login the device's.
class PortalLocaleNotifier extends Notifier<Locale?> {
  @override
  Locale? build() => null;

  void set(Locale? locale) => state = locale;
}

final portalLocaleProvider = NotifierProvider<PortalLocaleNotifier, Locale?>(
  PortalLocaleNotifier.new,
);

/// Turns an API error into a sentence for the customer.
String portalError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    if (error.response == null) return 'Cannot reach the server.';
    return 'Error ${error.response?.statusCode}.';
  }
  return error.toString();
}
