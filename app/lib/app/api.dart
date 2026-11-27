import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/generated/export.dart';
import '../features/tutorial/api_events.dart';
import 'session.dart';
import '../l10n/l10n.dart' show companyLanguagesOf, setContentLanguages;

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

final meProvider = FutureProvider<Me>((ref) async {
  final me = await ref.watch(apiProvider).core.me();
  // Language pickers offer the company's content languages (ADR 0101).
  setContentLanguages(companyLanguagesOf(me.company));
  return me;
});

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

final vatRatesProvider = FutureProvider<List<CountryVatRate>>(
  (ref) => ref.watch(apiProvider).core.listVatRates(),
);

const _euVatCountries = <String>{
  'AT', 'BE', 'BG', 'CY', 'CZ', 'DE', 'DK', 'EE', 'EL', 'ES', 'FI', 'FR',
  'GR', 'HR', 'HU', 'IE', 'IT', 'LT', 'LU', 'LV', 'MT', 'NL', 'PL', 'PT',
  'RO', 'SE', 'SI', 'SK', 'XI',
};

/// Whether [countryCode] is in the EU VAT area (EU-27 plus XI).
bool isEuVatCountry(String countryCode) =>
    _euVatCountries.contains(countryCode.trim().toUpperCase());

/// Mirrors backend `tradocraft_core::vat::default_vat_regime`.
String deriveDefaultVatRegime({
  required String companyCountry,
  required String customerCountry,
  required String? vatNumber,
}) {
  final co = companyCountry.trim().toUpperCase();
  final cu = customerCountry.trim().toUpperCase();
  if (co == cu) return 'domestic';
  final hasVat = vatNumber != null && vatNumber.trim().isNotEmpty;
  if (isEuVatCountry(co) && isEuVatCountry(cu)) {
    return hasVat ? 'intra_eu' : 'domestic';
  }
  return 'outside_eu';
}

/// Resolves the active rate for a country + category on [asOf] from loaded rules.
String? resolveCountryCategoryRate(
  List<CountryVatRate> rules, {
  required String countryCode,
  required String category,
  DateTime? asOf,
}) {
  final date = asOf ?? DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  final cc = countryCode.trim().toUpperCase();
  final active = rules.where((r) {
    if (r.countryCode.toUpperCase() != cc) return false;
    final start = DateTime(r.startDate.year, r.startDate.month, r.startDate.day);
    final end = r.endDate == null
        ? null
        : DateTime(r.endDate!.year, r.endDate!.month, r.endDate!.day);
    return !start.isAfter(day) && (end == null || !day.isAfter(end));
  }).toList()
    ..sort((a, b) => b.startDate.compareTo(a.startDate));
  String? findCat(String cat) {
    for (final r in active) {
      if (r.category == cat) return r.rate;
    }
    return null;
  }

  return switch (category) {
    'zero' => findCat('zero') ?? '0',
    'reduced' => findCat('reduced') ?? findCat('standard'),
    'intermediate' => findCat('intermediate') ?? findCat('standard'),
    _ => findCat('standard'),
  };
}

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
