import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/live_record_watcher.dart';

import 'fake_http.dart';

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

  test('isVersionedChange distinguishes save events from resync and unversioned events', () {
    expect(isVersionedChange('updated'), isTrue);
    expect(isVersionedChange('note'), isTrue);
    expect(isVersionedChange('resync'), isFalse);
    expect(isVersionedChange('tag'), isFalse);
    expect(isVersionedChange('time'), isFalse);
    expect(isVersionedChange('presence'), isFalse);
  });

  testWidgets('watchRecordChanges lets ticket reconnect resync at cur pass while rejecting stale saves', (
    tester,
  ) async {
    final adapter = _WatchAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    addTearDown(() async {
      await adapter.closeStreams();
      dio.close();
    });

    final received = <RecordChangeEvent>[];
    var currentVersion = 2;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: _WatcherHarness(
          entityType: 'ticket',
          recordId: 't1',
          currentVersion: () => currentVersion,
          onExternalChange: received.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    // Initial connect resync at version == cur (2) must not trigger a false notification.
    await settle();
    expect(received, isEmpty);

    // Older or equal versioned save events must still be rejected.
    adapter.pushRecordChanged(kind: 'updated', version: 2);
    adapter.pushRecordChanged(kind: 'note', version: 1);
    await settle();
    expect(received, isEmpty);

    // Reconnect resync at version == cur (2) for a ticket must proceed (e.g. unversioned panels).
    adapter.pushRaw('event: resync\ndata: {}\n\n');
    await settle();
    expect(received.map((e) => (e.kind, e.version, e.isReconnect)), [
      ('resync', 2, true),
    ]);

    // Transport drop + reconnect at version == cur (2) also proceeds as a reconnect resync.
    await adapter.dropAndPrepareReconnect();
    await tester.pump(const Duration(seconds: 2));
    await settle();
    expect(received.map((e) => (e.kind, e.version, e.isReconnect)), [
      ('resync', 2, true),
      ('resync', 2, true),
    ]);

    // Older resync (version < cur) must still be rejected.
    adapter.version = 1;
    adapter.pushRaw('event: resync\ndata: {}\n\n');
    await settle();
    expect(received.length, 2);

    // Unversioned event at version == cur and newer save event both proceed.
    adapter.pushRecordChanged(kind: 'tag', version: 2);
    adapter.pushRecordChanged(kind: 'updated', version: 3);
    await settle();
    expect(received.map((e) => (e.kind, e.version)), [
      ('resync', 2),
      ('resync', 2),
      ('tag', 2),
      ('updated', 3),
    ]);
  });

  testWidgets('watchRecordChanges rejects non-ticket resync when version equals cur', (
    tester,
  ) async {
    final adapter = _WatchAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = adapter;
    addTearDown(() async {
      await adapter.closeStreams();
      dio.close();
    });

    final received = <RecordChangeEvent>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: _WatcherHarness(
          entityType: 'customer',
          recordId: 'c1',
          currentVersion: () => 2,
          onExternalChange: received.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    adapter.pushRaw('event: resync\ndata: {}\n\n');
    await settle();
    expect(received, isEmpty);

    adapter.version = 3;
    adapter.pushRaw('event: resync\ndata: {}\n\n');
    await settle();
    expect(received.map((e) => (e.kind, e.version)), [('resync', 3)]);
  });
}

class _WatchAdapter implements HttpClientAdapter {
  StreamController<Uint8List> _stream = StreamController<Uint8List>();
  int version = 2;

  void pushRaw(String frame) =>
      _stream.add(Uint8List.fromList(utf8.encode(frame)));

  Future<void> dropAndPrepareReconnect() async {
    final prev = _stream;
    _stream = StreamController<Uint8List>();
    await prev.close();
  }

  void pushRecordChanged({required String kind, required int version}) {
    pushRaw(
      'event: record_changed\ndata: ${jsonEncode({'entity_type': 'ticket', 'record_id': 't1', 'version': version, 'changed_by_id': 'u2', 'changed_by_name': 'Jo', 'kind': kind, 'summary': null, 'at': '2026-11-09T11:00:00Z'})}\n\n',
    );
  }

  Future<void> closeStreams() => _stream.close();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/api/v1/me') {
      return ResponseBody.fromString(
        jsonEncode(meJson(['helpdesk.read'])),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.path.endsWith('/events/records')) {
      return ResponseBody(_stream.stream, 200);
    }
    final payload = options.path.startsWith('/api/v1/tickets/')
        ? {'ticket': {'version': version}}
        : {'version': version};
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _WatcherHarness extends ConsumerStatefulWidget {
  const _WatcherHarness({
    required this.entityType,
    required this.recordId,
    required this.currentVersion,
    required this.onExternalChange,
  });

  final String entityType;
  final String recordId;
  final int? Function() currentVersion;
  final void Function(RecordChangeEvent event) onExternalChange;

  @override
  ConsumerState<_WatcherHarness> createState() => _WatcherHarnessState();
}

class _WatcherHarnessState extends ConsumerState<_WatcherHarness> {
  RecordLiveWatcher? _watcher;

  @override
  void initState() {
    super.initState();
    ref.read(meProvider);
    _watcher = watchRecordChanges(
      ref,
      entityType: widget.entityType,
      recordId: widget.recordId,
      currentVersion: widget.currentVersion,
      onExternalChange: widget.onExternalChange,
    );
  }

  @override
  void dispose() {
    _watcher?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
