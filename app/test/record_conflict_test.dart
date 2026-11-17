import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/live_record_watcher.dart';

class _LiveAdapter implements HttpClientAdapter {
  final stream = StreamController<Uint8List>();
  int version = 2;
  int reads = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/events/records')) {
      return ResponseBody(stream.stream, 200);
    }
    expect(options.path, '/api/v1/tickets/t1');
    reads++;
    return ResponseBody.fromString(
      '{"ticket":{"version":$version}}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'watcher checks the version on connect and after a resync signal',
    () async {
      final adapter = _LiveAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final events = <RecordChangeEvent>[];
      final connected = Completer<void>();
      final resynced = Completer<void>();
      final watcher = RecordLiveWatcher(
        dio: dio,
        entityType: 'ticket',
        recordId: 't1',
        onChange: (event) {
          events.add(event);
          if (events.length == 1) connected.complete();
          if (events.length == 2) resynced.complete();
        },
      );
      watcher.start();
      try {
        await connected.future.timeout(const Duration(seconds: 2));
        adapter.version = 5;
        adapter.stream.add(
          Uint8List.fromList('event: resync\ndata: {}\n\n'.codeUnits),
        );
        await resynced.future.timeout(const Duration(seconds: 2));
        expect(events.map((e) => e.version), [2, 5]);
        expect(adapter.reads, 2);
      } finally {
        watcher.dispose();
        await adapter.stream.close();
        dio.close();
      }
    },
  );

  testWidgets('reload is disabled while an operation is pending', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: RecordConflictBanner(
            message: 'Changed',
            isConflict: false,
            onReload: null,
          ),
        ),
      ),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  test('isRecordChangedError detects 409 record_changed payloads', () {
    final opts = RequestOptions(path: '/api/v1/customers/1');
    final conflict = DioException(
      requestOptions: opts,
      response: Response(
        requestOptions: opts,
        statusCode: 409,
        data: {
          'error': 'conflict',
          'code': 'record_changed',
          'message': 'changed',
        },
      ),
    );
    final other = DioException(
      requestOptions: opts,
      response: Response(
        requestOptions: opts,
        statusCode: 422,
        data: {'error': 'validation', 'message': 'bad'},
      ),
    );
    expect(isRecordChangedError(conflict), isTrue);
    expect(isRecordChangedError(other), isFalse);
    expect(isRecordChangedError('plain error'), isFalse);
  });

  test('RecordChangeEvent.fromJson parses SSE payload', () {
    final ev = RecordChangeEvent.fromJson({
      'entity_type': 'ticket',
      'record_id': '00000000-0000-7000-8000-000000000001',
      'version': 4,
      'changed_by_id': '00000000-0000-7000-8000-000000000101',
      'changed_by_name': 'Alice',
      'kind': 'updated',
      'summary': null,
      'at': '2026-11-17T05:30:00Z',
    });
    expect(ev.entityType, 'ticket');
    expect(ev.version, 4);
    expect(ev.changedByName, 'Alice');
    expect(ev.kind, 'updated');
  });

  testWidgets(
    'RecordConflictBanner shows message and triggers reload/dismiss',
    (tester) async {
      var reloaded = false;
      var dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RecordConflictBanner(
              message: 'Updated by Alice',
              isConflict: false,
              onReload: () => reloaded = true,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );

    expect(find.text('Updated by Alice'), findsOneWidget);
    await tester.tap(find.text('Reload'));
    expect(reloaded, isTrue);

      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    },
  );
}
