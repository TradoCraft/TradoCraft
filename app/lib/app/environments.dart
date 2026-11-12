import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/field/offline/kv_store.dart';
import 'session.dart';
import 'workspace.dart';

/// What an environment is for (ADR 0043). The server decides; the app only shows it.
enum EnvironmentKind {
  live,
  test,
  tutorial;

  /// The kind written by the server (`live`, `test`, `tutorial`); null for anything else.
  static EnvironmentKind? parse(Object? raw) {
    for (final k in values) {
      if (k.name == raw) return k;
    }
    return null;
  }
}

/// One server the app can talk to: its address, what kind of data it holds and, per environment,
/// who is signed in there (the same fields as [Session]).
class AppEnvironment {
  const AppEnvironment({
    required this.id,
    required this.name,
    required this.kind,
    required this.serverUrl,
    this.devUser,
    this.accessToken,
    this.companyId,
  });

  final String id;
  final String name;
  final EnvironmentKind kind;
  final String serverUrl;
  final String? devUser;
  final String? accessToken;
  final String? companyId;

  /// The session of this environment (signed out when nobody signed in there yet).
  Session get session => Session(
    serverUrl: serverUrl,
    devUser: devUser,
    accessToken: accessToken,
    companyId: companyId,
  );

  /// A copy with the sign-in of [s] (its server address too).
  AppEnvironment withSession(Session s) => AppEnvironment(
    id: id,
    name: name,
    kind: kind,
    serverUrl: s.serverUrl,
    devUser: s.devUser,
    accessToken: s.accessToken,
    companyId: s.companyId,
  );

  /// A copy with another name and/or kind.
  AppEnvironment copyWith({String? name, EnvironmentKind? kind}) =>
      AppEnvironment(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        serverUrl: serverUrl,
        devUser: devUser,
        accessToken: accessToken,
        companyId: companyId,
      );

  /// The stored form of this environment.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'url': serverUrl,
    'dev': devUser,
    'token': accessToken,
    'company': companyId,
  };

  /// Reads one stored environment; null when the entry is unusable.
  static AppEnvironment? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String || j['url'] is! String) return null;
    String? s(String k) => j[k] is String ? j[k] as String : null;
    return AppEnvironment(
      id: j['id'] as String,
      name: s('name') ?? hostOf(j['url'] as String),
      kind: EnvironmentKind.parse(j['kind']) ?? EnvironmentKind.live,
      serverUrl: j['url'] as String,
      devUser: s('dev'),
      accessToken: s('token'),
      companyId: s('company'),
    );
  }
}

/// The list of environments and which one is in use.
class EnvironmentsState {
  const EnvironmentsState({required this.items, required this.activeId});

  /// Every environment known on this device, in the order they were added.
  final List<AppEnvironment> items;

  /// The id of the environment in use.
  final String activeId;

  /// The environment in use (the first one if the id is unknown).
  AppEnvironment get active =>
      items.firstWhere((e) => e.id == activeId, orElse: () => items.first);

  /// A copy with the given list and/or active id replaced.
  EnvironmentsState copyWith({List<AppEnvironment>? items, String? activeId}) =>
      EnvironmentsState(
        items: items ?? this.items,
        activeId: activeId ?? this.activeId,
      );
}

/// The host (and port) of an address, used as the name of an environment nobody named.
String hostOf(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return url;
  return u.hasPort ? '${u.host}:${u.port}' : u.host;
}

/// An address as stored: trimmed, without trailing slashes; null when it is not an http(s)
/// address with a host.
String? normalizeServerUrl(String raw) {
  var t = raw.trim();
  while (t.endsWith('/')) {
    t = t.substring(0, t.length - 1);
  }
  final u = Uri.tryParse(t);
  if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) return null;
  return u.host.isEmpty ? null : t;
}

/// Reads and writes the list of environments in the device (or profile) storage.
class EnvironmentStore {
  static const key = 'environments';

  /// The list from [store]. Without one (an installation from before environments) the stored
  /// [session] becomes the first environment: kind `live` until the server says otherwise.
  static Future<EnvironmentsState> load(KvStore store, Session session) async {
    try {
      final raw = await store.get(key);
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final items = <AppEnvironment>[
          for (final e in (json['items'] as List? ?? const []))
            ?AppEnvironment.fromJson(e),
        ];
        if (items.isNotEmpty) {
          final active = json['active'];
          return EnvironmentsState(
            items: items,
            activeId: items.any((e) => e.id == active)
                ? active as String
                : items.first.id,
          );
        }
      }
    } catch (_) {
      // Unreadable list: start again from the session below.
    }
    return fromSession(session);
  }

  /// A list with one environment made from [session].
  static EnvironmentsState fromSession(Session session) {
    final first = AppEnvironment(
      id: 'env-1',
      name: hostOf(session.serverUrl),
      kind: EnvironmentKind.live,
      serverUrl: session.serverUrl,
      devUser: session.devUser,
      accessToken: session.accessToken,
      companyId: session.companyId,
    );
    return EnvironmentsState(items: [first], activeId: first.id);
  }

  /// Writes the list and the active id to [store].
  static Future<void> save(EnvironmentsState s, KvStore store) => store.set(
    key,
    jsonEncode({
      'active': s.activeId,
      'items': [for (final e in s.items) e.toJson()],
    }),
  );
}

/// What a server says about itself (`GET /api/v1/meta/environment`).
class EnvironmentProbe {
  const EnvironmentProbe({
    required this.name,
    required this.kind,
    required this.dbName,
    required this.version,
  });

  final String name;
  final EnvironmentKind kind;
  final String dbName;
  final String version;
}

/// Asks the server at an address which environment it is. Needs no sign-in. Overridden in tests.
final environmentProbeProvider =
    Provider<Future<EnvironmentProbe> Function(String serverUrl)>(
      (ref) => (url) async {
        final dio = Dio(
          BaseOptions(
            baseUrl: url,
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
          ),
        );
        try {
          final res = await dio.get<Object?>('/api/v1/meta/environment');
          final d = res.data;
          final kind = d is Map ? EnvironmentKind.parse(d['kind']) : null;
          if (d is! Map || kind == null || d['name'] is! String) {
            throw const FormatException('Not a TradoCraft server');
          }
          return EnvironmentProbe(
            name: d['name'] as String,
            kind: kind,
            dbName: '${d['db_name'] ?? ''}',
            version: '${d['version'] ?? ''}',
          );
        } finally {
          dio.close();
        }
      },
    );

/// The environments known at start-up (overridden in `main` with the stored list).
final initialEnvironmentsProvider = Provider<EnvironmentsState>(
  (ref) => EnvironmentStore.fromSession(ref.read(initialSessionProvider)),
);

/// What a change to the list of environments came to.
enum EnvChange {
  /// Applied and stored.
  done,

  /// Applied for this run (the session and the list in memory), but the list could not be stored,
  /// so the next start may not remember it.
  notSaved,

  /// Nothing changed: an address already in the list, an unknown id, or the active environment.
  rejected,
}

/// Owns the list of environments and keeps it in step with [sessionProvider].
class EnvironmentsNotifier extends Notifier<EnvironmentsState> {
  @override
  EnvironmentsState build() {
    final initial = ref.read(initialEnvironmentsProvider);
    // The session is the truth for the active environment's sign-in: keep the list in step.
    ref.listen(sessionProvider, (_, s) => _followSession(s));
    Future.microtask(refreshActive);
    return initial;
  }

  /// Takes over a session change. The same server: the sign-in is stored on the active
  /// environment. Another server (a sign-in to a different address from the login page): the
  /// active environment keeps its name, kind and sign-in, and the other address becomes an
  /// environment of its own (an existing one for that address, or a new one that counts as live
  /// until the server says otherwise), which then becomes the active one.
  void _followSession(Session s) {
    final a = state.active;
    if (a.serverUrl == s.serverUrl) {
      state = state.copyWith(
        items: [
          for (final e in state.items) e.id == a.id ? e.withSession(s) : e,
        ],
      );
      _persist();
      return;
    }
    final known = state.items
        .where((e) => sameServer(e.serverUrl, s.serverUrl))
        .firstOrNull;
    if (known != null) {
      state = EnvironmentsState(
        items: [
          for (final e in state.items) e.id == known.id ? e.withSession(s) : e,
        ],
        activeId: known.id,
      );
      _persist();
      return;
    }
    final env = AppEnvironment(
      id: _freshId(),
      name: hostOf(s.serverUrl),
      kind: EnvironmentKind.live,
      serverUrl: s.serverUrl,
    ).withSession(s);
    state = EnvironmentsState(items: [...state.items, env], activeId: env.id);
    _persist();
    refreshActive();
  }

  String _freshId() {
    var n = state.items.length + 1;
    while (state.items.any((e) => e.id == 'env-$n')) {
      n++;
    }
    return 'env-$n';
  }

  /// Stores the list; false when that failed (the in-memory list stays as it is).
  Future<bool> _persist() async {
    try {
      await EnvironmentStore.save(state, ref.read(kvStoreProvider));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Asks the active environment's server what it is and takes over its kind (and the name, when
  /// that is still the address). A server that does not answer leaves things as they are.
  Future<void> refreshActive() async {
    final a = state.active;
    try {
      final info = await ref.read(environmentProbeProvider)(a.serverUrl);
      if (!ref.mounted) return;
      final stillActive = state.active.id == a.id;
      if (!stillActive) return;
      final rename = a.name == hostOf(a.serverUrl);
      state = state.copyWith(
        items: [
          for (final e in state.items)
            e.id == a.id
                ? e.copyWith(name: rename ? info.name : null, kind: info.kind)
                : e,
        ],
      );
      await _persist();
    } catch (_) {
      // Unreachable or not a TradoCraft server: keep the stored kind.
    }
  }

  /// Adds the environment at [serverUrl] (already checked with the server) and makes it active.
  /// [EnvChange.rejected] when that address is already in the list (compared in canonical form);
  /// the active sign-in is then left alone.
  Future<EnvChange> add({
    required String name,
    required String serverUrl,
    required EnvironmentKind kind,
  }) async {
    final url = normalizeServerUrl(serverUrl) ?? serverUrl;
    if (state.items.any((e) => sameServer(e.serverUrl, url))) {
      return EnvChange.rejected;
    }
    final env = AppEnvironment(
      id: _freshId(),
      name: name,
      kind: kind,
      serverUrl: url,
    );
    state = state.copyWith(items: [...state.items, env]);
    final saved = await _persist();
    final switched = await switchTo(env.id);
    return saved && switched == EnvChange.done
        ? EnvChange.done
        : EnvChange.notSaved;
  }

  /// Makes [id] the active environment: the open tabs are closed and the session is replaced by
  /// the one of that environment, so the HTTP client, the company and the storage of the user
  /// all change together and nothing of the previous environment stays on screen. When storing
  /// fails the switch still happens in memory and [EnvChange.notSaved] is returned.
  Future<EnvChange> switchTo(String id) async {
    final target = state.items.where((e) => e.id == id).firstOrNull;
    if (target == null || target.id == state.activeId) {
      return EnvChange.rejected;
    }
    ref.read(workspaceProvider.notifier).closeAll();
    state = state.copyWith(activeId: id);
    var saved = await _persist();
    try {
      await ref.read(sessionProvider.notifier).signIn(target.session);
    } catch (_) {
      // The session is set in memory before it is stored; only the storing failed.
      saved = false;
    }
    refreshActive();
    return saved ? EnvChange.done : EnvChange.notSaved;
  }

  /// Removes [id] from this device; the active environment cannot be removed.
  Future<EnvChange> remove(String id) async {
    if (id == state.activeId || !state.items.any((e) => e.id == id)) {
      return EnvChange.rejected;
    }
    state = state.copyWith(
      items: [
        for (final e in state.items)
          if (e.id != id) e,
      ],
    );
    return await _persist() ? EnvChange.done : EnvChange.notSaved;
  }
}

/// Whether two server addresses are the same once written in canonical form.
bool sameServer(String a, String b) =>
    (normalizeServerUrl(a) ?? a) == (normalizeServerUrl(b) ?? b);

/// The list of environments and the one in use; follows the session.
final environmentsProvider =
    NotifierProvider<EnvironmentsNotifier, EnvironmentsState>(
      EnvironmentsNotifier.new,
    );

/// The environment in use.
final activeEnvironmentProvider = Provider<AppEnvironment>(
  (ref) => ref.watch(environmentsProvider).active,
);
