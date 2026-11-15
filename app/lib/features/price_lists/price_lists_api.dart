import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';

/// All price lists of the company.
final priceListsProvider = FutureProvider<List<PriceList>>(
  (ref) => ref.watch(apiProvider).products.listPriceLists(),
);

/// One price list (the editor header).
final priceListProvider = FutureProvider.family<PriceList, String>(
  (ref, id) => ref.watch(apiProvider).products.getPriceList(id: id),
);

/// The groups of a list, flat (the tree is built from `parent_id`).
final priceListGroupsProvider = FutureProvider.family<List<PriceListGroup>, String>(
  (ref, id) => ref.watch(apiProvider).products.listGroups(id: id),
);

/// The items of a list.
final priceListItemsProvider = FutureProvider.family<List<PriceListItem>, String>(
  (ref, id) => ref.watch(apiProvider).products.listItems(id: id),
);

/// The languages a price list can be published in, in the order the app shows them.
const priceListLanguages = ['nl', 'fr', 'en', 'de', 'es'];

/// Deepest nesting of groups the server accepts.
const maxGroupDepth = 4;

/// The languages the zones of a list are published in, in the app's order. Titles and
/// descriptions are edited in these; a list without zones offers all five.
extension PriceListLanguages on PriceList {
  List<String> get publishedLanguages {
    final used = {for (final z in zones) ...z.languages};
    final ordered = [
      for (final c in priceListLanguages)
        if (used.contains(c)) c,
    ];
    return ordered.isEmpty ? priceListLanguages : ordered;
  }
}

/// The export profiles of a list.
final priceListExportsProvider =
    FutureProvider.family<List<PriceListExport>, String>(
      (ref, id) => ref.watch(apiProvider).products.listExports(id: id),
    );

/// Renders one file of the plan (the whole list, or one export profile, for one zone and language)
/// as PDF or Excel and returns its bytes. The generated client cannot return bytes, so this goes
/// through Dio directly.
Future<Uint8List> renderPriceList(
  Dio dio,
  String id, {
  required String zoneId,
  required String lang,
  required String format,
  String? exportId,
}) async {
  final res = await dio.post<List<int>>(
    '/api/v1/price-lists/$id/render',
    queryParameters: {
      'zone_id': zoneId,
      'lang': lang,
      'export_id': ?exportId,
      'format': format,
    },
    options: Options(responseType: ResponseType.bytes),
  );
  return Uint8List.fromList(res.data ?? const []);
}

/// What the server knows of the company logo: null when none was uploaded.
final companyLogoInfoProvider = FutureProvider<CompanyLogoInfo?>((ref) async {
  // There is no metadata-only endpoint: the PUT answer describes the logo; GET returns the bytes.
  final bytes = await ref.watch(companyLogoBytesProvider.future);
  return bytes == null ? null : CompanyLogoInfo(
    contentType: _sniff(bytes),
    sizeBytes: bytes.length,
    updatedAt: DateTime.now(),
  );
});

/// The logo image, or null on a 404.
final companyLogoBytesProvider = FutureProvider<Uint8List?>((ref) async {
  try {
    return Uint8List.fromList(
      await downloadBytes(ref.watch(dioProvider), '/api/v1/admin/company/logo'),
    );
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) return null;
    rethrow;
  }
});

/// The image type of [bytes], read from the first bytes the way the server does.
String _sniff(Uint8List b) => logoContentType(b) ?? 'application/octet-stream';

/// `image/png`, `image/jpeg` or `image/svg+xml` from the first bytes; null for anything else.
String? logoContentType(Uint8List b) {
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4e &&
      b[3] == 0x47) {
    return 'image/png';
  }
  if (b.length >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) {
    return 'image/jpeg';
  }
  final head = String.fromCharCodes(b.take(512)).toLowerCase();
  if (head.contains('<svg') || (head.contains('<?xml') && head.contains('svg'))) {
    return 'image/svg+xml';
  }
  return null;
}

/// Largest logo the server accepts.
const maxLogoBytes = 512 * 1024;

/// Uploads the logo (the request body is the image file).
Future<CompanyLogoInfo> uploadLogo(Dio dio, Uint8List bytes) async {
  final r = await dio.put<Map<String, dynamic>>(
    '/api/v1/admin/company/logo',
    data: bytes,
    options: Options(
      contentType: 'application/octet-stream',
      headers: {Headers.contentLengthHeader: bytes.length},
    ),
  );
  return CompanyLogoInfo.fromJson(r.data!);
}
