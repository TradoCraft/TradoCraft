import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/live_record_watcher.dart';

void main() {
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
        data: {
          'error': 'validation',
          'message': 'bad',
        },
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

  testWidgets('RecordConflictBanner shows message and triggers reload/dismiss', (
    tester,
  ) async {
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
  });
}
