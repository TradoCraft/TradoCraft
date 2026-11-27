import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/runtime_l10n.dart';
import 'api.dart';
import 'session.dart';

/// Interface languages an administrator installed as runtime catalogues of the `app` domain
/// (ADR 0101): the languages with company texts. Empty while signed out or when the server is
/// unreachable, so the shipped languages always work.
final installedInterfaceLanguagesProvider = FutureProvider<List<String>>((
  ref,
) async {
  await ref.watch(meProvider.future);
  final res = await ref
      .watch(dioProvider)
      .get<List<dynamic>>('/api/v1/translations/app');
  return [
    for (final c in res.data ?? const [])
      if (((c as Map)['company_entries'] as num? ?? 0) > 0)
        c['language'] as String,
  ];
});

/// The company texts of the `app` catalogue of one language (`key → ICU message`).
final interfaceCatalogueProvider =
    FutureProvider.family<Map<String, String>, String>((ref, code) async {
      final res = await ref
          .watch(dioProvider)
          .get<Map<String, dynamic>>('/api/v1/translations/app/$code');
      final entries = (res.data?['entries'] as Map?) ?? const {};
      return {
        for (final e in entries.entries) '${e.key}': '${e.value}',
      };
    });

/// The interface language in use: the person's choice, else the device's.
String activeInterfaceLanguage(Ref ref) =>
    ref.watch(localeProvider)?.languageCode ??
    PlatformDispatcher.instance.locale.languageCode;

/// The runtime catalogues the app layers over its shipped texts: the catalogue of the active
/// interface language when one is installed.
final runtimeCataloguesProvider = Provider<Map<String, Map<String, String>>>((
  ref,
) {
  final code = activeInterfaceLanguage(ref);
  final installed = ref.watch(installedInterfaceLanguagesProvider).value;
  if (installed == null || !installed.contains(code)) return const {};
  final catalogue = ref.watch(interfaceCatalogueProvider(code)).value;
  return catalogue == null ? const {} : {code: catalogue};
});

/// The interface languages a person can choose: the shipped ones and the installed ones.
final interfaceLanguagesProvider = Provider<List<String>>((ref) {
  final installed =
      ref.watch(installedInterfaceLanguagesProvider).value ?? const [];
  return [
    ...shippedInterfaceLanguages,
    for (final l in installed)
      if (!shippedInterfaceLanguages.contains(l)) l,
  ];
});
