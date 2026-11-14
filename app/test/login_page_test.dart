import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/profile.dart';
import 'package:tradocraft_app/app/session.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/features/login/login_page.dart';
import 'package:tradocraft_app/features/setup/setup_api.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

/// A store that answers reads only after [release], so the remembered user arrives late.
class _LateStore extends MemoryKvStore {
  final _gate = Completer<void>();
  void release() => _gate.complete();

  @override
  Future<String?> get(String key) async {
    final v = await super.get(key);
    await _gate.future;
    return v;
  }
}

void main() {
  Future<_LateStore> pump(WidgetTester tester) async {
    final store = _LateStore()..data[SessionStore.lastDevUserKey] = 'admin@x.y';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWithValue('admin'),
          kvStoreProvider.overrideWithValue(store),
          setupStatusProvider.overrideWithValue(
            (_) async => throw Exception('offline'),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: LoginPage(),
        ),
      ),
    );
    await tester.pump();
    return store;
  }

  testWidgets('the remembered user fills the field when it was not touched', (
    tester,
  ) async {
    final store = await pump(tester);
    store.release();
    await tester.pumpAndSettle();
    expect(find.text('admin@x.y'), findsOneWidget);
  });

  testWidgets('typing the default user back still counts as an edit', (
    tester,
  ) async {
    final store = await pump(tester);
    final field = find.widgetWithText(TextField, 'sales@example.com');
    await tester.enterText(field, 'other@x.y');
    await tester.enterText(
      find.widgetWithText(TextField, 'other@x.y'),
      'sales@example.com',
    );
    store.release();
    await tester.pumpAndSettle();
    expect(find.text('sales@example.com'), findsOneWidget);
    expect(find.text('admin@x.y'), findsNothing);
  });
}
