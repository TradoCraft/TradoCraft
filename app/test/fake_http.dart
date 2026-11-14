import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A route answer with another status than 200, for example `FakeStatus(409, {'error': 'conflict',
/// 'message': '...'})`.
class FakeStatus {
  const FakeStatus(this.status, this.body);
  final int status;
  final Object? body;
}

/// A fake server for widget tests: [routes] maps `"METHOD /path"` to a JSON body (or a function
/// of the request body). Unknown routes answer 404. Requests are recorded.
class FakeHttp implements HttpClientAdapter {
  FakeHttp(this.routes);

  final Map<String, Object? Function(Object? body)> routes;
  final requests = <String>[];
  final bodies = <String, Object?>{};

  /// Query parameters of each request, in the order of [requests].
  final queries = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final key = '${o.method} ${o.path}';
    requests.add(key);
    queries.add(o.queryParameters);
    Object? sent;
    if ((o.contentType ?? '').contains('json')) {
      if (body != null) {
        final bytes = Uint8List.fromList(await body.expand((c) => c).toList());
        if (bytes.isNotEmpty) sent = jsonDecode(utf8.decode(bytes));
      }
    } else {
      // A photo: keep the bytes the app handed to Dio (draining the stream is not needed).
      sent = o.data;
    }
    bodies[key] = sent;
    final route = routes[key];
    if (route == null) {
      return ResponseBody.fromString(
        jsonEncode({'error': 'not_found', 'message': key}),
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    // A route may answer with a Future, to keep a request under way for as long as a test needs.
    final json = await Future<Object?>.sync(() => route(sent));
    if (json is FakeStatus) {
      return ResponseBody.fromString(
        jsonEncode(json.body),
        json.status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (json is Uint8List) {
      return ResponseBody.fromBytes(
        json,
        200,
        headers: {
          Headers.contentTypeHeader: ['image/jpeg'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(json),
      json == null ? 204 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio fakeDio(FakeHttp http) =>
    Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = http;

Map<String, Object?> contactJson({
  String id = 'p1',
  String first = 'Luc',
  String last = 'Claes',
  String customer = 'Bêta Industrie SA',
  String customerId = 'c2',
  String customerLanguage = 'fr',
  String? language = 'nl',
  String greeting = 'Dag Luc,',
  List<String> roles = const ['technical'],
  bool portal = false,
}) => {
  'id': id,
  'customer_id': customerId,
  'customer_code': 'C0002',
  'customer_name': customer,
  'first_name': first,
  'last_name': last,
  'full_name': '$first $last',
  'job_title': 'Technician',
  'title': 'mr',
  'address_form': 'informal',
  'language': language,
  'customer_language': customerLanguage,
  'effective_language': language ?? customerLanguage,
  'greeting': greeting,
  'roles': roles,
  'notes': '',
  'active': true,
  'portal_access': portal,
  'portal_scope': 'own',
  'emails': [
    {'email': 'luc.claes@beta.example', 'is_primary': true},
  ],
  'phones': [
    {
      'label': 'mobile',
      'number': '+32 478 00 00 44',
      'normalized': '32478000044',
    },
  ],
  'created_at': '2026-11-05T10:00:00Z',
  'updated_at': '2026-11-05T10:00:00Z',
};

Map<String, Object?> meJson(List<String> permissions, {bool primary = true}) => {
  'user_id': 'u1',
  'email': 'support@example.com',
  'display_name': 'Support Agent',
  'roles': ['support'],
  'permissions': permissions,
  'modules': [],
  'memberships': [],
  'company': {
    'id': 'co',
    'name': 'Demo',
    'street': '',
    'postal_code': '',
    'city': '',
    'country_code': 'BE',
    'currency': 'EUR',
    'default_language': 'nl',
    'is_primary': primary,
  },
};

Map<String, Object?> customerJson() => {
  'id': 'c2',
  'code': 'C0002',
  'name': 'Bêta Industrie SA',
  'street': '',
  'postal_code': '',
  'city': 'Liège',
  'vat_regime': 'domestic',
  'country_code': 'BE',
  'language': 'fr',
  'active': true,
};

/// A tiny JPEG-looking byte string (the app only displays what the server returns).
final fakeJpeg = Uint8List.fromList([
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0,
  0x10,
  0x4A,
  0x46,
  0x49,
  0x46,
]);

Map<String, Object?> repairJson({
  String status = 'received',
  String? department,
  int photos = 0,
}) => {
  'id': 'r1',
  'number': 'R2026-00001',
  'status': status,
  'priority': 'normal',
  'customer_id': 'c1',
  'customer_name': 'Alpha Installaties NV',
  'contact_name': 'Jan Peeters',
  'product_description': 'Pump 5 kW',
  'serial_number': 'SN-1',
  'fault_description': 'Does not start',
  'customer_reference': 'RMA-77',
  'warranty': 'unknown',
  'warranty_auto': 'unknown',
  'warranty_overridden': false,
  'findings': '',
  'diagnosis': '',
  'department_id': department == null ? null : 'd1',
  'department_name': department,
  'source': 'staff',
  'photo_count': photos,
  'created_at': '2026-11-06T10:00:00Z',
  'updated_at': '2026-11-06T10:00:00Z',
};

Map<String, Object?> departmentJson(
  String id,
  String name, {
  List<Map<String, Object?>> members = const [],
}) => {
  'id': id,
  'code': name.toUpperCase().substring(0, 4),
  'name': name,
  'sort_order': 1,
  'active': true,
  'members': members,
  'open_repairs': 0,
};

/// The fields every ticket carries since the helpdesk got SLA, tags and time tracking.
Map<String, Object?> ticketExtras() => {
  'unread': false,
  'watching': false,
  'tags': <String>[],
  'time_minutes': 0,
  'sla': {
    'state': 'none',
    'paused': false,
    'first_response': {'breached': false, 'at_risk': false},
    'resolution': {'breached': false, 'at_risk': false},
    'first_response_breached': false,
    'resolution_breached': false,
  },
};

/// The collaboration fields every ticket detail carries (watchers and readers).
Map<String, Object?> detailExtras() => {
  'watchers': <Object?>[],
  'readers': <Object?>[],
};
