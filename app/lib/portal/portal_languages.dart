import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'portal_state.dart';

/// Interface languages the company installed as runtime catalogues for the app (ADR 0101), as
/// the portal server serves them to a signed-in contact. Empty when signed out.
final portalInstalledLanguagesProvider = FutureProvider<List<String>>((
  ref,
) async {
  await ref.watch(portalProfileProvider.future);
  final res = await ref
      .watch(portalDioProvider)
      .get<List<dynamic>>('/portal/translations/app');
  return [for (final l in res.data ?? const []) '$l'];
});

/// The company texts of the `app` catalogue of one language.
final portalCatalogueProvider =
    FutureProvider.family<Map<String, String>, String>((ref, code) async {
      final res = await ref
          .watch(portalDioProvider)
          .get<Map<String, dynamic>>('/portal/translations/app/$code');
      return {
        for (final e in (res.data ?? const {}).entries) e.key: '${e.value}',
      };
    });

/// The runtime catalogue of the portal's language, when one is installed.
final portalRuntimeCataloguesProvider =
    Provider<Map<String, Map<String, String>>>((ref) {
      final code = ref.watch(portalLocaleProvider)?.languageCode;
      final installed = ref.watch(portalInstalledLanguagesProvider).value;
      if (code == null || installed == null || !installed.contains(code)) {
        return const {};
      }
      final catalogue = ref.watch(portalCatalogueProvider(code)).value;
      return catalogue == null ? const {} : {code: catalogue};
    });
