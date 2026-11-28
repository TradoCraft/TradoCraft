import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'app_localizations.dart';
import 'runtime_localizations.dart';

/// The interface languages compiled into the app (one ARB file each).
final shippedInterfaceLanguages = [
  for (final l in AppLocalizations.supportedLocales) l.languageCode,
];

/// Loads [AppLocalizations] for shipped languages and for languages an administrator installed
/// as a runtime catalogue (ADR 0101). A catalogue is layered over the shipped localization of
/// its language, or over English for a language the app does not ship.
class RuntimeLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const RuntimeLocalizationsDelegate([this.catalogues = const {}]);

  /// Runtime catalogues by language code: `message key → ICU text`.
  final Map<String, Map<String, String>> catalogues;

  @override
  bool isSupported(Locale locale) =>
      shippedInterfaceLanguages.contains(locale.languageCode) ||
      catalogues.containsKey(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(localizationsFor(locale.languageCode, catalogues));

  @override
  bool shouldReload(RuntimeLocalizationsDelegate old) =>
      !mapEquals(old.catalogues, catalogues);
}

/// The localization of [code]: the runtime catalogue (if any) over the shipped localization of
/// the language, else over English.
AppLocalizations localizationsFor(
  String code,
  Map<String, Map<String, String>> catalogues,
) {
  final shipped = shippedInterfaceLanguages.contains(code);
  final base = lookupAppLocalizations(Locale(shipped ? code : 'en'));
  final catalogue = catalogues[code];
  if (catalogue == null || catalogue.isEmpty) {
    return shipped ? base : RuntimeAppLocalizations(code, base, const {});
  }
  return RuntimeAppLocalizations(code, base, catalogue);
}

/// Wraps a Flutter localizations delegate so that a language Flutter itself does not translate
/// gets its English texts (date pickers, tooltips) instead of failing to load.
class _EnglishFallbackDelegate extends LocalizationsDelegate<dynamic> {
  const _EnglishFallbackDelegate(this.inner);

  final LocalizationsDelegate<dynamic> inner;

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<dynamic> load(Locale locale) =>
      inner.load(inner.isSupported(locale) ? locale : const Locale('en'));

  @override
  bool shouldReload(_EnglishFallbackDelegate old) => false;

  @override
  Type get type => inner.type;
}

/// Material, Cupertino and Widgets localizations for any language, English where Flutter has no
/// translation; use in place of `GlobalMaterialLocalizations.delegates`.
final List<LocalizationsDelegate<dynamic>> fallbackFlutterDelegates = [
  for (final d in GlobalMaterialLocalizations.delegates)
    _EnglishFallbackDelegate(d),
];

/// The locales [MaterialApp] must list so that every shipped and installed language resolves.
List<Locale> interfaceLocales(Iterable<String> installed) => [
  for (final code in {...shippedInterfaceLanguages, ...installed}) Locale(code),
];
