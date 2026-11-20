import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/framework/components/chatter/chatter_panel.dart';
import 'package:tradocraft_app/shared/attachments.dart' show AttachmentPicker;
import 'package:tradocraft_app/framework/components/chatter/chatter_repository.dart';
import 'package:tradocraft_app/framework/form/record_form_controller.dart'
    show ChatterTick;
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/photos.dart';

import 'fake_http.dart';

Map<String, Object?> _note(String id, String body, {bool editable = false}) => {
  'id': id,
  'kind': 'note',
  'author_id': 'u2',
  'author_name': 'Jo',
  'body': body,
  'changes': <Object?>[],
  'files': <Object?>[],
  'created_at': '2027-02-20T10:00:00Z',
  'editable': editable,
};

Map<String, Object?> _change() => {
  'id': 'm0',
  'kind': 'system',
  'author_id': 'u2',
  'author_name': 'Jo',
  'body': '',
  'changes': [
    {'field': 'name', 'from': 'Old', 'to': 'New'},
  ],
  'files': <Object?>[],
  'created_at': '2027-02-20T09:00:00Z',
  'editable': false,
};

Map<String, Object?> _activity() => {
  'id': 'a1',
  'kind': 'call',
  'summary': 'Call back',
  'note': '',
  'assignee_id': 'u1',
  'assignee_name': 'Me',
  'due_date': '2020-01-01',
  'created_by': 'u1',
  'created_at': '2027-02-20T08:00:00Z',
  'overdue': true,
};

const _base = '/api/v1/chatter/customer/c1';

Future<FakeHttp> _pump(
  WidgetTester t, {
  List<String> permissions = const ['customers.read', 'customers.write'],
  List<Object?> notes = const [],
  bool following = false,
  Map<String, Object? Function(Object?)> extra = const {},
  AttachmentPicker? pick,
  Listenable? refresh,
}) async {
  t.view.physicalSize = const Size(500, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final feed = [...notes];
  final http = FakeHttp({
    'GET /api/v1/me': (_) => meJson(permissions),
    'GET $_base/thread': (_) => {'items': feed},
    'GET $_base/activities': (_) => [_activity()],
    'GET $_base/followers': (_) => {
      'items': <Object?>[],
      'following': following,
    },
    'POST $_base/read': (_) => null,
    'POST $_base/notes': (b) {
      feed.insert(0, _note('n9', (b as Map)['body'] as String));
      return feed.first;
    },
    'PUT $_base/follow': (_) => {'items': <Object?>[], 'following': true},
    'GET /api/v1/users': (_) => [
      {'id': 'u1', 'email': 'me@x', 'display_name': 'Me', 'roles': <Object?>[]},
    ],
    ...extra,
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChatterPanel(
              kind: ChatterKind.customer,
              recordId: 'c1',
              pickFiles: pick,
              refresh: refresh,
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return http;
}

void main() {
  testWidgets('shows notes, change messages and open activities', (t) async {
    await _pump(t, notes: [_note('n1', 'Called, all good'), _change()]);
    expect(find.text('Called, all good'), findsOneWidget);
    expect(find.textContaining('Jo changed Name: Old → New'), findsOneWidget);
    expect(find.textContaining('Call: Call back'), findsOneWidget);
    expect(find.textContaining('Overdue'), findsOneWidget);
    expect(find.byKey(const ValueKey('chatter-empty')), findsNothing);
  });

  testWidgets('says so when there is nothing yet', (t) async {
    await _pump(t);
    expect(find.byKey(const ValueKey('chatter-empty')), findsOneWidget);
  });

  testWidgets('posting a note sends it and shows it', (t) async {
    final http = await _pump(t);
    await t.enterText(
      find.byKey(const ValueKey('chatter-composer')),
      '  New note ',
    );
    await t.tap(find.byKey(const ValueKey('chatter-post')));
    await t.pumpAndSettle();
    expect(http.bodies['POST $_base/notes'], containsPair('body', 'New note'));
    expect(find.text('New note'), findsOneWidget);
    // The composer is empty again.
    final field = t.widget<TextField>(
      find.byKey(const ValueKey('chatter-composer')),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('a read-only user sees the thread but cannot write', (t) async {
    await _pump(t, permissions: ['customers.read'], notes: [_note('n1', 'Hi')]);
    expect(find.text('Hi'), findsOneWidget);
    expect(find.byKey(const ValueKey('chatter-composer')), findsNothing);
    expect(find.byKey(const ValueKey('chatter-schedule')), findsNothing);
    expect(find.byKey(const ValueKey('activity-done-a1')), findsNothing);
    // but may follow
    expect(find.byKey(const ValueKey('chatter-follow')), findsOneWidget);
  });

  testWidgets('following toggles and is sent to the server', (t) async {
    final http = await _pump(t);
    await t.tap(find.byKey(const ValueKey('chatter-follow')));
    await t.pumpAndSettle();
    expect(http.requests, contains('PUT $_base/follow'));
  });

  testWidgets('only own, recent notes can be edited', (t) async {
    await _pump(
      t,
      notes: [_note('n1', 'Mine', editable: true), _note('n2', 'Theirs')],
    );
    expect(find.byKey(const ValueKey('chatter-edit-n1')), findsOneWidget);
    expect(find.byKey(const ValueKey('chatter-edit-n2')), findsNothing);
  });

  testWidgets(
    'scheduling an activity sends a date, the kind and the assignee',
    (t) async {
      final http = await _pump(
        t,
        extra: {'POST $_base/activities': (_) => _activity()},
      );
      await t.tap(find.byKey(const ValueKey('chatter-schedule')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('activity-summary')),
        'Visit',
      );
      await t.pump();
      await t.tap(find.byKey(const ValueKey('activity-ok')));
      await t.pumpAndSettle();
      final body = http.bodies['POST $_base/activities'] as Map;
      expect(body['summary'], 'Visit');
      expect(body['kind'], 'todo');
      expect(body['assignee_id'], 'u1');
      expect(body['due_date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}')));
    },
  );

  testWidgets('a failed load can be retried', (t) async {
    var fail = true;
    await _pump(
      t,
      extra: {
        'GET $_base/thread': (_) => fail
            ? const FakeStatus(500, {'error': 'internal', 'message': 'x'})
            : {
                'items': [_note('n1', 'Back')],
              },
      },
    );
    expect(find.text('The messages could not be loaded.'), findsOneWidget);
    fail = false;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('Back'), findsOneWidget);
  });

  testWidgets('files are uploaded, sent with the note and shown on it', (
    t,
  ) async {
    final http = await _pump(
      t,
      pick: (_) async => [
        PickedPhoto(Uint8List.fromList([1, 2, 3]), 'plan.png'),
      ],
      extra: {
        'POST $_base/files': (_) => {
          'id': 'f1',
          'filename': 'plan.png',
          'content_type': 'image/png',
          'size_bytes': 3,
          'uploader_name': 'Me',
          'created_at': '2027-02-20T10:00:00Z',
        },
        'POST $_base/notes': (b) => {
          ..._note('n9', (b as Map)['body'] as String),
          'files': [
            {
              'id': 'f1',
              'filename': 'plan.png',
              'content_type': 'image/png',
              'size_bytes': 3,
              'uploader_name': 'Me',
              'created_at': '2027-02-20T10:00:00Z',
            },
          ],
        },
        'GET $_base/thread': (_) => {
          'items': [
            {
              ..._note('n9', 'See plan'),
              'files': [
                {
                  'id': 'f1',
                  'filename': 'plan.png',
                  'content_type': 'image/png',
                  'size_bytes': 3,
                  'uploader_name': 'Me',
                  'created_at': '2027-02-20T10:00:00Z',
                },
              ],
            },
          ],
        },
      },
    );
    await t.tap(find.byKey(const ValueKey('attach-file')));
    await t.pumpAndSettle();
    expect(http.requests, contains('POST $_base/files'));
    expect(find.byKey(const ValueKey('pending-f1')), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('chatter-composer')),
      'See plan',
    );
    await t.tap(find.byKey(const ValueKey('chatter-post')));
    await t.pumpAndSettle();
    expect(http.bodies['POST $_base/notes'], containsPair('file_ids', ['f1']));
    // the pending chip is gone, the note shows the file
    expect(find.byKey(const ValueKey('pending-f1')), findsNothing);
    expect(find.byKey(const ValueKey('attachment-f1')), findsOneWidget);
  });

  testWidgets('an activity can be edited', (t) async {
    final http = await _pump(
      t,
      extra: {
        'GET /api/v1/me': (_) => {
          ...meJson(['customers.read', 'customers.write']),
          'user_id': 'u1',
        },
        'PATCH /api/v1/chatter/activities/a1': (_) => _activity(),
      },
    );
    await t.tap(find.byKey(const ValueKey('activity-edit-a1')));
    await t.pumpAndSettle();
    // the dialog is filled with the activity
    expect(find.widgetWithText(TextField, 'Call back'), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('activity-summary')),
      'Call Monday',
    );
    await t.pump();
    await t.tap(find.byKey(const ValueKey('activity-ok')));
    await t.pumpAndSettle();
    final body = http.bodies['PATCH /api/v1/chatter/activities/a1'] as Map;
    expect(body['summary'], 'Call Monday');
    expect(body['kind'], 'call');
    expect(body['assignee_id'], 'u1');
    expect(body['due_date'], startsWith('2020-01-01'));
  });

  testWidgets('a live tick reloads the thread', (t) async {
    final tick = ChatterTick();
    addTearDown(tick.dispose);
    final feed = <Object?>[];
    final http = await _pump(
      t,
      refresh: tick,
      extra: {
        'GET $_base/thread': (_) => {'items': feed},
      },
    );
    expect(find.text('From a colleague'), findsNothing);
    feed.add(_note('n5', 'From a colleague'));
    tick.fire();
    await t.pumpAndSettle();
    expect(find.text('From a colleague'), findsOneWidget);
    expect(http.requests.where((r) => r == 'GET $_base/thread').length, 2);
  });
}
