import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/api/generated/export.dart' hide Column;
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/vat_field.dart';

VatCheck _check({
  String status = 'valid',
  List<Map<String, Object?>> duplicates = const [],
  Map<String, Object?>? vies,
  String number = 'BE0428759497',
}) => VatCheck.fromJson({
  'vat_number': number,
  'status': status,
  'duplicates': duplicates,
  'vies': ?vies,
});

const _alpha = {'id': 'a', 'code': 'C0001', 'name': 'Alpha NV', 'active': true};

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(width: 420, child: child),
    ),
  ),
);

/// The input, the controller behind it and what the checker was asked.
class _Rig {
  _Rig({String text = '', this.answer, this.onLookup, this.enabled = true})
    : controller = TextEditingController(text: text);

  final TextEditingController controller;
  final Future<VatCheck> Function(String number, bool lookup)? answer;
  final bool Function(ViesLookup)? onLookup;
  final bool enabled;
  final asked = <(String, bool)>[];

  Widget get widget => VatNumberField(
    fieldKey: const ValueKey('vat-input'),
    controller: controller,
    label: 'VAT number',
    enabled: enabled,
    onLookup: onLookup,
    check: ({required String number, required bool lookup}) {
      asked.add((number, lookup));
      return answer!(number, lookup);
    },
  );
}

void main() {
  testWidgets('the verdict and the duplicates appear once typing stops', (
    tester,
  ) async {
    final rig = _Rig(
      answer: (n, _) async =>
          _check(status: 'bad_checksum', number: n, duplicates: [_alpha]),
    );
    await tester.pumpWidget(_host(rig.widget));
    expect(find.byKey(const ValueKey('vat-status')), findsNothing);

    // Typing quickly asks once, after the pause, with the trimmed text.
    await tester.enterText(find.byKey(const ValueKey('vat-input')), 'BE04287');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.byKey(const ValueKey('vat-input')),
      ' BE0428759498 ',
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(rig.asked, isEmpty, reason: 'still typing');
    await tester.pump(vatCheckDelay);
    await tester.pumpAndSettle();

    expect(rig.asked, [('BE0428759498', false)]);
    expect(
      find.text('The check digits do not match: please check for a typo.'),
      findsOneWidget,
    );
    expect(find.text('Also used by: C0001 Alpha NV'), findsOneWidget);
  });

  testWidgets('each verdict has its own words', (tester) async {
    final words = {
      'valid': 'The format and check digits are right. This does not show that the number is registered.',
      'format_ok': "The format is right. This country's check digits are not verified here.",
      'bad_format': 'This is not shaped like a VAT number of this country.',
      'not_checked': 'Not an EU VAT number, so it is not checked.',
    };
    for (final e in words.entries) {
      final rig = _Rig(
        text: 'X',
        answer: (n, _) async => _check(status: e.key, number: n),
      );
      await tester.pumpWidget(_host(rig.widget));
      await tester.pumpAndSettle();
      expect(find.text(e.value), findsOneWidget, reason: e.key);
    }
    // Nothing to say about an empty number, and no line for "empty".
    final rig = _Rig(
      text: 'X',
      answer: (n, _) async => _check(status: 'empty', number: n),
    );
    await tester.pumpWidget(_host(rig.widget));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vat-status')), findsNothing);
  });

  testWidgets('an existing number is checked when the form opens', (
    tester,
  ) async {
    final rig = _Rig(
      text: 'DE000000000',
      answer: (n, _) async => _check(status: 'bad_checksum', number: n),
    );
    await tester.pumpWidget(_host(rig.widget));
    await tester.pumpAndSettle();
    expect(rig.asked, [('DE000000000', false)]);
    expect(find.byKey(const ValueKey('vat-status')), findsOneWidget);
  });

  testWidgets(
    'an inactive duplicate is called inactive and long lists are cut',
    (tester) async {
      Map<String, Object?> dup(int i, {bool active = true}) => {
        'id': 'd$i',
        'code': 'C$i',
        'name': 'Name $i',
        'active': active,
      };
      final rig = _Rig(
        text: 'X',
        answer: (n, _) async => _check(
          number: n,
          duplicates: [dup(1, active: false), dup(2), dup(3), dup(4)],
        ),
      );
      await tester.pumpWidget(_host(rig.widget));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Also used by: C1 Name 1 (inactive), C2 Name 2, C3 Name 3, …',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('a failing check says nothing and does not break the form', (
    tester,
  ) async {
    final rig = _Rig(
      text: 'BE0428759497',
      answer: (n, _) async => throw StateError('offline'),
    );
    await tester.pumpWidget(_host(rig.widget));
    await tester.pumpAndSettle();
    expect(rig.asked, hasLength(1));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('vat-status')), findsNothing);
    // Typing still works.
    await tester.enterText(find.byKey(const ValueKey('vat-input')), 'BE1');
    expect(rig.controller.text, 'BE1');
  });

  testWidgets('only the newest answer is shown when answers arrive late', (
    tester,
  ) async {
    final first = Completer<VatCheck>();
    var calls = 0;
    final rig = _Rig(
      text: 'A',
      answer: (n, _) {
        calls++;
        return calls == 1
            ? first.future
            : Future.value(_check(status: 'valid', number: n));
      },
    );
    await tester.pumpWidget(_host(rig.widget));
    await tester.pump(
      const Duration(milliseconds: 1),
    ); // the first check starts and waits
    await tester.enterText(find.byKey(const ValueKey('vat-input')), 'B');
    await tester.pump(vatCheckDelay);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The format and check digits are right. This does not show that the number is registered.',
      ),
      findsOneWidget,
    );
    // The old answer arrives now and must not overwrite the newer one.
    first.complete(_check(status: 'bad_checksum', number: 'A'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'The format and check digits are right. This does not show that the number is registered.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('The check digits do not match: please check for a typo.'),
      findsNothing,
    );
  });

  testWidgets(
    'a lookup answer for a number that was edited since fills nothing',
    (tester) async {
      final pending = Completer<VatCheck>();
      var handed = 0;
      final rig = _Rig(
        text: 'BE0428759497',
        answer: (n, lookup) => lookup
            ? pending.future
            : Future.value(_check(number: n, status: 'valid')),
        onLookup: (_) {
          handed++;
          return true;
        },
      );
      await tester.pumpWidget(_host(rig.widget));
      await tester.pumpAndSettle();
      // The lookup is on its way ...
      await tester.tap(find.byKey(const ValueKey('vat-lookup')));
      await tester.pump();
      // ... and the number is edited before it answers.
      await tester.enterText(find.byKey(const ValueKey('vat-input')), 'BE1');
      await tester.pump();
      pending.complete(
        _check(
          number: 'BE0428759497',
          vies: {'state': 'valid', 'name': 'OLD NUMBER NV'},
        ),
      );
      await tester.pump();
      expect(
        handed,
        0,
        reason: 'the form must not be filled from the old number',
      );
      expect(find.text('Registered and active in VIES.'), findsNothing);
      // Nor does any advice about the old number stay on screen while the new one is typed.
      expect(find.byKey(const ValueKey('vat-status')), findsNothing);
      // The button is usable again for the new number.
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('vat-lookup')))
            .onPressed,
        isNotNull,
      );
      await tester.pumpAndSettle();
    },
  );

  group('the VIES lookup', () {
    Map<String, Object?> valid({String? name, String? street}) => {
      'state': 'valid',
      'name': ?name,
      'street': ?street,
    };

    testWidgets('has a button only for those who may use it', (tester) async {
      final none = _Rig(
        text: 'X',
        answer: (n, _) async => _check(number: n),
      );
      await tester.pumpWidget(_host(none.widget));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vat-lookup')), findsNothing);

      final some = _Rig(
        text: 'X',
        answer: (n, _) async => _check(number: n),
        onLookup: (_) => false,
      );
      await tester.pumpWidget(_host(some.widget));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vat-lookup')), findsOneWidget);
    });

    testWidgets('asks VIES, hands the answer over and says what it did', (
      tester,
    ) async {
      ViesLookup? got;
      final rig = _Rig(
        text: 'BE0428759497',
        answer: (n, lookup) async => _check(
          number: n,
          vies: lookup ? valid(name: 'ACME NV', street: 'RUE X 1') : null,
        ),
        onLookup: (v) {
          got = v;
          return true;
        },
      );
      await tester.pumpWidget(_host(rig.widget));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vat-lookup')));
      await tester.pumpAndSettle();

      expect(rig.asked.last, ('BE0428759497', true));
      expect(got?.name, 'ACME NV');
      expect(find.text('Registered and active in VIES.'), findsOneWidget);
      expect(find.text('Empty fields filled in from VIES.'), findsOneWidget);

      // Editing the number makes what VIES said about the old one stale.
      await tester.enterText(find.byKey(const ValueKey('vat-input')), 'BE1');
      await tester.pump();
      expect(find.text('Registered and active in VIES.'), findsNothing);
    });

    testWidgets('does not claim to have filled what it did not', (
      tester,
    ) async {
      final rig = _Rig(
        text: 'BE0428759497',
        answer: (n, lookup) async => _check(
          number: n,
          vies: lookup ? valid(name: 'ACME NV') : null,
        ),
        onLookup: (_) => false, // the fields already had text
      );
      await tester.pumpWidget(_host(rig.widget));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vat-lookup')));
      await tester.pumpAndSettle();
      expect(find.text('Registered and active in VIES.'), findsOneWidget);
      expect(find.byKey(const ValueKey('vat-vies-detail')), findsNothing);
    });

    testWidgets('says when the member state discloses nothing', (tester) async {
      final rig = _Rig(
        text: 'DE136695976',
        answer: (n, lookup) async =>
            _check(number: n, vies: lookup ? valid() : null),
        onLookup: (_) => false,
      );
      await tester.pumpWidget(_host(rig.widget));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vat-lookup')));
      await tester.pumpAndSettle();
      expect(
        find.text('The member state does not disclose a name or address.'),
        findsOneWidget,
      );
    });

    testWidgets('falls back to filling in by hand when VIES cannot answer', (
      tester,
    ) async {
      var filled = false;
      for (final (reason, text) in [
        (
          'ms_unavailable',
          'VIES could not answer (ms_unavailable). Fill in the details by hand.',
        ),
        ('disabled', 'The VIES lookup is switched off on this server.'),
      ]) {
        final rig = _Rig(
          text: 'BE0428759497',
          answer: (n, lookup) async => _check(
            number: n,
            vies: lookup ? {'state': 'unavailable', 'reason': reason} : null,
          ),
          onLookup: (_) => filled = true,
        );
        await tester.pumpWidget(_host(rig.widget));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('vat-lookup')));
        await tester.pumpAndSettle();
        expect(find.text(text), findsOneWidget, reason: reason);
      }
      expect(filled, isFalse, reason: 'nothing to fill from');
    });

    testWidgets('an unknown number is reported', (tester) async {
      final rig = _Rig(
        text: 'BE0000000196',
        answer: (n, lookup) async =>
            _check(number: n, vies: lookup ? {'state': 'invalid'} : null),
        onLookup: (_) => false,
      );
      await tester.pumpWidget(_host(rig.widget));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vat-lookup')));
      await tester.pumpAndSettle();
      expect(find.text('VIES does not know this number.'), findsOneWidget);
    });

    testWidgets('is off while saving or without a number', (tester) async {
      final empty = _Rig(
        answer: (n, _) async => _check(number: n),
        onLookup: (_) => false,
      );
      await tester.pumpWidget(_host(empty.widget));
      await tester.pump();
      final button = find.byKey(const ValueKey('vat-lookup'));
      expect(tester.widget<IconButton>(button).onPressed, isNull);

      final busy = _Rig(
        text: 'BE0428759497',
        enabled: false,
        answer: (n, _) async => _check(number: n),
        onLookup: (_) => false,
      );
      await tester.pumpWidget(_host(busy.widget));
      await tester.pump();
      expect(tester.widget<IconButton>(button).onPressed, isNull);
    });
  });
}
