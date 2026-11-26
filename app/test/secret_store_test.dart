import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/secret_store.dart';
import 'package:tradocraft_app/app/session.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';

void main() {
  late MemoryKvStore plain;
  late MemorySecretStore secrets;
  late SecureKvStore store;

  setUp(() {
    plain = MemoryKvStore();
    secrets = MemorySecretStore();
    store = SecureKvStore(plain, secrets);
  });

  test('the session token goes to the secret store, not the plain one', () async {
    await SessionStore.save(
      const Session(
        serverUrl: 'https://x.test',
        accessToken: 'tok-1',
        companyId: 'c1',
      ),
      store,
    );
    expect(plain.data.containsKey('access_token'), isFalse);
    expect(secrets.data.values, contains('tok-1'));
    expect(plain.data['company_id'], 'c1');
    final loaded = await SessionStore.load(store);
    expect(loaded.accessToken, 'tok-1');
    expect(loaded.serverUrl, 'https://x.test');
  });

  test('signing out deletes the token everywhere', () async {
    await SessionStore.save(
      const Session(serverUrl: 'u', accessToken: 'tok'),
      store,
    );
    await SessionStore.save(const Session(serverUrl: 'u'), store);
    expect(secrets.data, isEmpty);
    expect((await SessionStore.load(store)).accessToken, isNull);
  });

  test('migrates an old plain token once', () async {
    plain.data['access_token'] = 'old';
    expect(await store.get('access_token'), 'old');
    expect(plain.data.containsKey('access_token'), isFalse);
    expect(secrets.data.values, ['old']);
    expect(await store.get('access_token'), 'old');
  });

  test('migration keeps a newer secure token', () async {
    await store.set('access_token', 'new');
    plain.data['access_token'] = 'old';
    expect(await store.get('access_token'), 'new');
    expect(plain.data.containsKey('access_token'), isFalse);
  });

  test('environment tokens are stripped from the stored list', () async {
    final list = jsonEncode({
      'active': 'env-1',
      'items': [
        {'id': 'env-1', 'url': 'u', 'token': 'secret-env', 'dev': null},
        {'id': 'env-2', 'url': 'v', 'token': null},
      ],
    });
    await store.set('environments', list);
    expect(plain.data['environments'], isNot(contains('secret-env')));
    expect(secrets.data.values, ['secret-env']);
    final back = jsonDecode((await store.get('environments'))!) as Map;
    final items = back['items'] as List;
    expect((items[0] as Map)['token'], 'secret-env');
    expect((items[1] as Map)['token'], isNull);
  });

  test('migrates tokens inside an old environments list', () async {
    plain.data['environments'] = jsonEncode({
      'active': 'env-1',
      'items': [
        {'id': 'env-1', 'url': 'u', 'token': 'legacy'},
      ],
    });
    final back = jsonDecode((await store.get('environments'))!) as Map;
    expect(((back['items'] as List)[0] as Map)['token'], 'legacy');
    expect(plain.data['environments'], isNot(contains('legacy')));
    expect(secrets.data.values, ['legacy']);
  });

  test('other keys stay in the plain store', () async {
    await store.set('locale', 'nl');
    expect(plain.data['locale'], 'nl');
    expect(secrets.data, isEmpty);
    await store.remove('locale');
    expect(await store.get('locale'), isNull);
  });

  test('profiles do not share secrets', () async {
    final a = SecureKvStore(MemoryKvStore(), secrets, namespace: 'a');
    final b = SecureKvStore(MemoryKvStore(), secrets, namespace: 'b');
    await a.set('access_token', 'ta');
    expect(await b.get('access_token'), isNull);
  });
}
