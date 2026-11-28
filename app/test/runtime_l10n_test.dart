import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/admin/translations_page.dart';
import 'package:tradocraft_app/l10n/icu.dart';
import 'package:tradocraft_app/l10n/l10n.dart';
import 'package:tradocraft_app/l10n/runtime_l10n.dart';
import 'package:tradocraft_app/l10n/runtime_localizations.dart';

import '../tool/gen_runtime_l10n.dart';
import 'fake_http.dart';

void main() {
  test('the generated runtime localizations are up to date', () {
    final source = File('lib/l10n/app_localizations.dart').readAsStringSync();
    expect(
      File('lib/l10n/runtime_localizations.dart').readAsStringSync(),
      generateRuntimeLocalizations(source),
      reason: 'run: dart run tool/gen_runtime_l10n.dart',
    );
    final arb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map;
    expect(
      runtimeMessageKeys.toSet(),
      {for (final k in arb.keys) if (!'$k'.startsWith('@')) '$k'},
    );
  });

  group('ICU messages', () {
    test('placeholders, plurals and selects', () {
      expect(formatIcu('Hi {name}!', {'name': 'Ana'}, 'pt'), 'Hi Ana!');
      const plural = '{n, plural, =0{none} =1{one item} other{# items}}';
      expect(formatIcu(plural, {'n': 0}, 'en'), 'none');
      expect(formatIcu(plural, {'n': 1}, 'en'), 'one item');
      expect(formatIcu(plural, {'n': 7}, 'en'), '7 items');
      // CLDR rules of the language: Polish "few".
      const pl = '{n, plural, one{# plik} few{# pliki} many{# plików} other{# pliku}}';
      expect(formatIcu(pl, {'n': 3}, 'pl'), '3 pliki');
      expect(formatIcu(pl, {'n': 5}, 'pl'), '5 plików');
      const select = '{k, select, reply{Answer} other{Note {k}}}';
      expect(formatIcu(select, {'k': 'reply'}, 'en'), 'Answer');
      expect(formatIcu(select, {'k': 'x'}, 'en'), 'Note x');
    });

    test('malformed messages are recognised', () {
      expect(isValidIcu('Fine {a}'), isTrue);
      expect(isValidIcu('Broken {a'), isFalse);
      expect(isValidIcu('{n, plural, one{x}}'), isFalse);
      expect(isValidIcu('Stray }'), isFalse);
    });
  });

  group('runtime catalogues', () {
    test('a new language layers over English', () {
      final l = localizationsFor('pt', {
        'pt': {
          'save': 'Guardar',
          'andMore': '… e mais {count}',
          'cancel': 'Broken {',
        },
      });
      expect(l.save, 'Guardar');
      expect(l.andMore(3), '… e mais 3');
      // Missing and malformed texts come from English.
      expect(l.cancel, 'Cancel');
      expect(l.edit, 'Edit');
      expect(l.localeName, 'pt');
    });

    test('a correction layers over the shipped language', () {
      final l = localizationsFor('nl', {
        'nl': {'save': 'Bewaren'},
      });
      expect(l.save, 'Bewaren');
      expect(l.cancel, 'Annuleren');
      expect(localizationsFor('nl', const {}).save, 'Opslaan');
    });

    testWidgets('an installed language Flutter does not ship still renders', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('kl'),
          supportedLocales: interfaceLocales(['kl']),
          localizationsDelegates: [
            const RuntimeLocalizationsDelegate({
              'kl': {'save': 'Toqqoruk'},
            }),
            ...fallbackFlutterDelegates,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(leading: const BackButton()),
              body: Text(context.l10n.save),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Toqqoruk'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('catalogue files', () {
    test('ARB metadata is left out and unknown keys are reported', () {
      final entries = parseCatalogueFile(
        utf8.encode(
          jsonEncode({
            '@@locale': 'pt',
            'save': 'Guardar',
            '@save': {'description': 'x'},
            'noSuchKey': 'x',
            'cancel': 'Cancelar {',
          }),
        ),
      );
      expect(entries, {
        'save': 'Guardar',
        'noSuchKey': 'x',
        'cancel': 'Cancelar {',
      });
      expect(checkAppCatalogue(entries), ['noSuchKey', 'cancel']);
      expect(
        () => parseCatalogueFile(utf8.encode('[1]')),
        throwsFormatException,
      );
      final arb = jsonDecode(
        utf8.decode(catalogueFile('app', 'pt', {'save': 'Guardar'})),
      );
      expect(arb, {'@@locale': 'pt', 'save': 'Guardar'});
      expect(catalogueFileName('mail', 'pt'), 'mail_pt.json');
    });

    testWidgets('the translations page lists catalogues and removes one', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['users.admin']),
        'GET /api/v1/translations/app': (_) => [
          {'language': 'pt', 'shipped': false, 'company_entries': 12},
        ],
        'DELETE /api/v1/admin/translations/app/pt': (_) => null,
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dioProvider.overrideWithValue(fakeDio(http))],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: TranslationsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Português (pt)'), findsOneWidget);
      expect(find.text('12 company texts'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('translations-delete-pt')));
      await tester.pumpAndSettle();
      expect(http.requests, contains('DELETE /api/v1/admin/translations/app/pt'));
    });
  });
}
