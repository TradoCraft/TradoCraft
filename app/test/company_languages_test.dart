import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/admin/company_languages_section.dart';
import 'package:tradocraft_app/l10n/l10n.dart';

import 'fake_http.dart';

Future<void> _pump(WidgetTester tester, FakeHttp http) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
        home: const Scaffold(
          body: SingleChildScrollView(child: CompanyLanguagesSection()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, Object?> _me(List<String> languages, String def) {
  final me = meJson(['users.admin']);
  final company = Map<String, Object?>.from(me['company']! as Map);
  company['languages'] = languages;
  company['default_language'] = def;
  return {...me, 'company': company};
}

void main() {
  test('language names come from the ISO table', () {
    expect(languageName('pt'), 'Português');
    expect(languageEnglishName('sv'), 'Swedish');
    expect(languageName('zz'), 'zz');
    expect(languageNames.length, 184);
  });

  testWidgets('adds a language, makes it the default and saves the list', (
    tester,
  ) async {
    var me = _me(['nl', 'fr'], 'nl');
    final http = FakeHttp({
      'GET /api/v1/me': (_) => me,
      'PUT /api/v1/admin/company/languages': (body) {
        final b = body! as Map;
        me = _me(List<String>.from(b['languages'] as List), b['default_language'] as String);
        return me['company'];
      },
    });
    await _pump(tester, http);
    expect(find.text('Nederlands'), findsOneWidget);
    expect(find.text('Français'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('company-language-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('language-search')), 'portu');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-pick-pt')));
    await tester.pumpAndSettle();
    expect(find.text('Português'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('company-language-default-pt')));
    await tester.pumpAndSettle();
    // The default cannot be removed.
    final remove = tester.widget<IconButton>(
      find.byKey(const ValueKey('company-language-remove-pt')),
    );
    expect(remove.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('company-languages-save')));
    await tester.pumpAndSettle();
    expect(http.bodies['PUT /api/v1/admin/company/languages'], {
      'languages': ['nl', 'fr', 'pt'],
      'default_language': 'pt',
    });
  });

  test('without a list from the server the five former languages apply', () {
    expect(companyLanguagesOf(null), legacyContentLanguages);
    setContentLanguages(['pt', 'en']);
    expect(languageCodes, ['pt', 'en']);
    expect(languageChoices('nl'), ['pt', 'en', 'nl']);
    expect(languageChoices('pt'), ['pt', 'en']);
    setContentLanguages(const []);
    expect(languageCodes, legacyContentLanguages);
  });
}
