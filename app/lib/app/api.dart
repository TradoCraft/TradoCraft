import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/generated/export.dart';
import '../features/tutorial/api_events.dart';
import 'session.dart';

// The generated import-column model `Column` would shadow Flutter's `Column` widget in every file
// that imports this barrel; import it from api/generated/models/column.dart (prefixed) where needed.
export '../api/generated/export.dart';

final dioProvider = Provider<Dio>((ref) {
  final session = ref.watch(sessionProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: session.serverUrl,
      headers: session.headers,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );
  // Tells the tutorial which calls finished; silent unless a mission is running.
  dio.interceptors.add(
    ApiEventInterceptor(
      ref.read(apiEventBusProvider),
      scope: tutorialSessionId(session),
    ),
  );
  return dio;
});

/// Typed client generated from the backend's OpenAPI document.
final apiProvider = Provider<TradocraftApi>(
  (ref) => TradocraftApi(ref.watch(dioProvider)),
);

final meProvider = FutureProvider<Me>(
  (ref) => ref.watch(apiProvider).core.me(),
);

/// Whether the signed-in user holds [permission]. False while `me` is loading or failed, so
/// controls guarded by it stay hidden until the server has answered. Watches [meProvider].
bool can(WidgetRef ref, String permission) =>
    ref.watch(meProvider).value?.permissions.contains(permission) ?? false;

/// Power grids, optionally of one country (ISO alpha-2; empty = all).
final powerGridsProvider = FutureProvider.autoDispose
    .family<List<PowerGrid>, String>(
      (ref, country) => ref
          .watch(apiProvider)
          .products
          .listPowerGrids(country: country.isEmpty ? null : country),
    );

final priceZonesProvider = FutureProvider<List<PriceZone>>(
  (ref) => ref.watch(apiProvider).products.listPriceZones(),
);

/// The stable `code` the API adds to errors a client must tell apart (null when absent).
String? errorCode(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['code'] is String) return data['code'] as String;
  }
  return null;
}

/// The HTTP status of a failed API call (null for other errors, e.g. no connection). A detail
/// screen uses it to tell "this record is gone" (404) from other failures.
int? errorStatus(Object error) =>
    error is DioException ? error.response?.statusCode : null;

/// Turns API errors into a sentence for the user (the server sends `{error, message}`).
String errorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    if (error.response == null) {
      return 'Cannot reach the server (${error.message ?? error.type.name}).';
    }
    return 'Server error ${error.response?.statusCode}.';
  }
  return error.toString();
}

/// Downloads a file produced by the API (a PDF, a CSV, a spreadsheet).
Future<List<int>> downloadBytes(
  Dio dio,
  String path, {
  Map<String, dynamic>? queryParameters,
}) async {
  final res = await dio.get<List<int>>(
    path,
    queryParameters: queryParameters,
    options: Options(responseType: ResponseType.bytes),
  );
  return res.data ?? const [];
}
