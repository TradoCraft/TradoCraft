import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/workspace.dart';
import 'package:tradocraft_app/framework/form/many2one_field.dart';
import 'package:tradocraft_app/framework/form/record_form_controller.dart';
import 'package:tradocraft_app/framework/form/record_form_view.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

class _Rec {
  const _Rec(this.id, this.name, this.version);
  final String id;
  final String name;
  final int version;
}

RecordFormController<_Rec> _controller([_Rec? r]) =>
    RecordFormController<_Rec>(initial: r, versionOf: (r) => r.version);

DioException _http(int status, Map<String, Object?> body) {
  final opts = RequestOptions(path: '/x');
  return DioException(
    requestOptions: opts,
    response: Response(requestOptions: opts, statusCode: status, data: body),
  );
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('RecordFormController', () {
    test('tracks text edits but not cursor moves', () {
      final c = _controller(const _Rec('1', 'A', 1));
      final t = c.track(TextEditingController(text: 'abc'));
      t.selection = const TextSelection.collapsed(offset: 1);
      expect(c.dirty, isFalse);
      t.text = 'abcd';
      expect(c.dirty, isTrue);
    });

    test('a 409 record_changed becomes the save-refused notice', () async {
      final c = _controller(const _Rec('1', 'A', 3))..markDirty();
      final ok = await c.run(
        () async =>
            throw _http(409, {'code': 'record_changed', 'message': 'x'}),
      );
      expect(ok, isFalse);
      expect(c.notice?.kind, RecordNoticeKind.saveRefused);
      expect(c.notice!.isConflict, isTrue);
      expect(c.error, isNull);
      expect(c.dirty, isTrue, reason: 'unsaved edits are kept');
      expect(c.busy, isFalse);
    });

    test(
      'other errors land on the error line; a String is shown as is',
      () async {
        final c = _controller();
        await c.run(() async => throw _http(422, {'message': 'bad input'}));
        expect(c.error, 'bad input');
        await c.run(() async => throw 'choose a customer');
        expect(c.error, 'choose a customer');
        expect(c.notice, isNull);
      },
    );

    test(
      'a saved record clears dirty and a notice it is not older than',
      () async {
        final c = _controller(const _Rec('1', 'A', 3))..markDirty();
        c.debugNotify(
          const RecordNotice(RecordNoticeKind.updatedBy, changedByName: 'Kim'),
          version: 5,
        );
        // Saved, but still older than what the notice announced: the notice stays.
        c.apply(const _Rec('1', 'A', 4));
        expect(c.dirty, isFalse);
        expect(c.notice, isNotNull);
        c.apply(const _Rec('1', 'B', 5));
        expect(c.notice, isNull);
        expect(c.record!.name, 'B');
      },
    );

    test(
      'save does not run when validation fails, nor twice at once',
      () async {
        final c = _controller(const _Rec('1', 'A', 2));
        var calls = 0;
        int? sent;
        Future<_Rec> save(int? v) async {
          calls++;
          sent = v;
          await Future<void>.delayed(Duration.zero);
          return _Rec('1', 'A', (v ?? 0) + 1);
        }

        final first = c.save(save);
        expect(await c.save(save), isNull, reason: 'busy');
        expect((await first)!.version, 3);
        expect(calls, 1);
        expect(sent, 2, reason: 'expected_version is the loaded version');
        expect(c.version, 3);
      },
    );

    test('markDirty is ignored while busy', () async {
      final c = _controller(const _Rec('1', 'A', 1));
      await c.run(() async {
        c.markDirty();
        return null;
      });
      expect(c.dirty, isFalse);
    });
  });

  group('RecordFormView', () {
    testWidgets('reports dirty to the tab and shows the unsaved mark', (
      t,
    ) async {
      final c = _controller(const _Rec('1', 'A', 1));
      final dirty = ValueNotifier(false);
      await t.pumpWidget(
        _app(
          TabScope(
            id: 1,
            active: true,
            dirty: dirty,
            setTitle: (_) {},
            child: RecordFormView<_Rec>(
              controller: c,
              title: 'A',
              body: const Text('fields'),
            ),
          ),
        ),
      );
      expect(find.byTooltip('Unsaved changes'), findsNothing);
      c.markDirty();
      await t.pump();
      expect(dirty.value, isTrue);
      expect(find.byTooltip('Unsaved changes'), findsOneWidget);
      c.apply(const _Rec('1', 'A', 2));
      await t.pump();
      expect(dirty.value, isFalse);
    });

    testWidgets('shows the live notice with reload and dismiss', (t) async {
      final c = _controller(const _Rec('1', 'A', 1));
      var reloads = 0;
      await t.pumpWidget(
        _app(
          RecordFormView<_Rec>(
            controller: c,
            title: 'A',
            body: const Text('fields'),
            onReload: () => reloads++,
          ),
        ),
      );
      c.debugNotify(
        const RecordNotice(RecordNoticeKind.updatedBy, changedByName: 'Kim'),
      );
      await t.pump();
      expect(find.textContaining('Updated by Kim'), findsOneWidget);
      await t.tap(find.text('Reload'));
      expect(reloads, 1);
      await t.tap(find.byTooltip('Cancel'));
      await t.pump();
      expect(find.textContaining('Updated by Kim'), findsNothing);
    });

    testWidgets('validates the body through the controller form key', (
      t,
    ) async {
      final c = _controller();
      await t.pumpWidget(
        _app(
          RecordFormView<_Rec>(
            controller: c,
            title: 'New',
            body: TextFormField(
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
          ),
        ),
      );
      var called = false;
      expect(
        await c.save((_) async {
          called = true;
          return const _Rec('1', 'A', 1);
        }),
        isNull,
      );
      await t.pump();
      expect(called, isFalse);
      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets('tabs keep what was typed while hidden', (t) async {
      final c = _controller();
      await t.pumpWidget(
        _app(
          RecordFormView<_Rec>(
            controller: c,
            title: 'New',
            body: const SizedBox(),
            tabs: [
              FormSheetTab(
                label: 'One',
                child: TextFormField(key: const Key('f1')),
              ),
              const FormSheetTab(label: 'Two', child: Text('second')),
            ],
          ),
        ),
      );
      await t.enterText(find.byKey(const Key('f1')), 'kept');
      await t.tap(find.text('Two'));
      await t.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);
      expect(find.byKey(const Key('f1')), findsNothing);
      await t.tap(find.text('One'));
      await t.pumpAndSettle();
      expect(find.text('kept'), findsOneWidget);
    });

    testWidgets(
      'status bar highlights the current step and appends a side exit',
      (t) async {
        const steps = [
          FormStatusStep('draft', 'Draft'),
          FormStatusStep('sent', 'Sent'),
          FormStatusStep('accepted', 'Accepted'),
        ];
        await t.pumpWidget(
          _app(
            const FormStatusBar(
              steps: steps,
              current: 'rejected',
              offPathLabel: 'Rejected',
            ),
          ),
        );
        expect(find.text('Rejected'), findsOneWidget);
        expect(find.bySemanticsLabel('Status: Rejected'), findsOneWidget);
        await t.pumpWidget(
          _app(const FormStatusBar(steps: steps, current: 'sent')),
        );
        expect(find.bySemanticsLabel('Status: Sent'), findsOneWidget);
        expect(find.text('Rejected'), findsNothing);
      },
    );

    testWidgets('smart button shows count and label', (t) async {
      var taps = 0;
      await t.pumpWidget(
        _app(
          SmartButton(
            icon: Icons.people,
            label: 'Contacts',
            count: '3',
            onPressed: () => taps++,
          ),
        ),
      );
      await t.tap(find.text('Contacts'));
      expect(taps, 1);
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('Many2OneField', () {
    Future<List<_Rec>> search(String q) async => [
      const _Rec('1', 'Alpha', 1),
      const _Rec('2', 'Beta', 1),
    ].where((r) => r.name.toLowerCase().contains(q.toLowerCase())).toList();

    Future<void> pump(
      WidgetTester t,
      GlobalKey<FormState> form,
      ValueNotifier<_Rec?> value, {
      bool required = true,
      bool readOnly = false,
    }) => t.pumpWidget(
      _app(
        Form(
          key: form,
          child: ValueListenableBuilder<_Rec?>(
            valueListenable: value,
            builder: (_, v, _) => Many2OneField<_Rec>(
              value: v,
              label: 'Customer',
              display: (r) => r.name,
              idOf: (r) => r.id,
              search: search,
              required: required,
              readOnly: readOnly,
              onChanged: (r) => value.value = r,
            ),
          ),
        ),
      ),
    );

    testWidgets('required and empty is an error', (t) async {
      final form = GlobalKey<FormState>();
      await pump(t, form, ValueNotifier(null));
      expect(form.currentState!.validate(), isFalse);
      await t.pump();
      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets(
      'picking sets the value; typed text that is not picked is an error',
      (t) async {
        final form = GlobalKey<FormState>();
        final value = ValueNotifier<_Rec?>(null);
        await pump(t, form, value);
        await t.enterText(find.byType(TextField), 'alp');
        await t.pumpAndSettle();
        await t.tap(find.text('Alpha'));
        await t.pumpAndSettle();
        expect(value.value?.id, '1');
        expect(form.currentState!.validate(), isTrue);

        await t.enterText(find.byType(TextField), 'Alphx');
        await t.pumpAndSettle();
        expect(value.value?.id, '1', reason: 'typing alone keeps the link');
        expect(form.currentState!.validate(), isFalse);
        await t.pump();
        expect(find.text('Choose an entry from the list'), findsOneWidget);
      },
    );

    testWidgets('clear button and erasing both unlink', (t) async {
      final form = GlobalKey<FormState>();
      final value = ValueNotifier<_Rec?>(const _Rec('2', 'Beta', 1));
      await pump(t, form, value, required: false);
      expect(find.text('Beta'), findsOneWidget);
      await t.tap(find.byTooltip('Clear'));
      await t.pumpAndSettle();
      expect(value.value, isNull);
      expect(find.text('Beta'), findsNothing);
      expect(form.currentState!.validate(), isTrue);

      value.value = const _Rec('2', 'Beta', 1);
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '');
      await t.pumpAndSettle();
      expect(value.value, isNull);
    });

    testWidgets('read-only shows the text without an input', (t) async {
      await pump(
        t,
        GlobalKey<FormState>(),
        ValueNotifier(const _Rec('2', 'Beta', 1)),
        readOnly: true,
      );
      expect(find.text('Beta'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
